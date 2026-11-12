#!/usr/bin/env python3
"""분석 워크플로가 만든 그래프 중 남길 것만 두고 나머지를 지운다 (docs/plan.md 단계 6, 보관 정리).

남기는 것:
  - main의 first-parent 최근 N개 커밋(기본 20)의 그래프. main 푸시는 머지 커밋 단위라 푸시마다 하나다.
  - 열린 PR의 head 커밋 그래프
SHA와 그래프의 대응은 커밋 상태 `codeinside/joern-cpg`(success, 설명 `codebase_hash=<hash>`)에서 읽는다.

지우는 것:
  - 색인(CI 소스 폴더의 .cpg-index.jsonl, joern_cpg_job.py가 쓴다)에 있는 이 레포의 그래프 중
    남길 SHA가 가리키지 않는 것. codebadger `remove_cpg`(delete_files=true)로 그래프, 소스 사본, DB 기록을 지운다.
  - codebase_hash는 파일 내용 해시라 여러 SHA가 같은 그래프를 가리킬 수 있다. 남길 SHA 하나라도 가리키면 지우지 않는다.
  - 색인에 없는 그래프(수동으로 만든 기준값 그래프 등)는 건드리지 않는다.
  - CI 소스 폴더에 남은 `<레포 이름>-<SHA>` 폴더와 임시 폴더(`.<레포 이름>-<SHA>.*`). 러너가 하나라 이 작업이 도는 동안
    다른 작업이 소스를 풀고 있지 않다.

환경 변수: GITHUB_TOKEN, GITHUB_REPOSITORY, CODEBADGER_MCP_URL, CODEBADGER_SRC_DIR, GITHUB_STEP_SUMMARY(선택)
사용: python3 prune_cpgs.py [--keep-main 20] [--dry-run]
출력: 마지막 줄에 `PRUNE {json}`
"""
import argparse
import glob
import json
import os
import re
import shutil
import sys
import time
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "mcp"))
from mcp_http import McpHttpClient  # noqa: E402

STATUS_CONTEXT = "codeinside/joern-cpg"
INDEX = ".cpg-index.jsonl"
HASH_RE = re.compile(r"codebase_hash=([0-9a-f]{16,64})")


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def api(path, body=None):
    req = urllib.request.Request(
        f"https://api.github.com{path}", data=json.dumps(body).encode() if body else None,
        method="POST" if body else "GET",
        headers={"Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}",
                 "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read())


def main_first_parent(repo, n):
    """main의 first-parent 커밋 n개. 커밋 목록 100개 안에서 parents[0]를 따라간다."""
    commits = api(f"/repos/{repo}/commits?sha=main&per_page=100")
    parent = {c["sha"]: (c["parents"][0]["sha"] if c["parents"] else None) for c in commits}
    out, sha = [], commits[0]["sha"]
    while sha and sha in parent and len(out) < n:
        out.append(sha)
        sha = parent[sha]
    return out


def open_pr_heads(repo):
    return [p["head"]["sha"] for p in api(f"/repos/{repo}/pulls?state=open&per_page=100")]


def statuses(repo, shas):
    """SHA -> codebase_hash (커밋 상태 success만). GraphQL 한 번."""
    if not shas:
        return {}
    owner, name = repo.split("/")
    fields = "\n".join(
        f'c{i}: object(oid: "{s}") {{ ... on Commit {{ status {{ context(name: "{STATUS_CONTEXT}") '
        f'{{ state description }} }} }} }}' for i, s in enumerate(shas))
    data = api("/graphql", {"query": f'query {{ repository(owner: "{owner}", name: "{name}") {{ {fields} }} }}'})
    repo_data = data["data"]["repository"]
    out = {}
    for i, s in enumerate(shas):
        ctx = ((repo_data.get(f"c{i}") or {}).get("status") or {}).get("context")
        m = HASH_RE.search((ctx or {}).get("description") or "") if ctx and ctx["state"] == "SUCCESS" else None
        if m:
            out[s] = m.group(1)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep-main", type=int, default=20)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    repo = os.environ["GITHUB_REPOSITORY"]
    name = repo.split("/")[1]
    src_dir = os.environ["CODEBADGER_SRC_DIR"]
    index_path = os.path.join(src_dir, INDEX)

    main_shas = main_first_parent(repo, a.keep_main)
    pr_shas = open_pr_heads(repo)
    keep_map = statuses(repo, list(dict.fromkeys(main_shas + pr_shas)))
    keep_hashes = set(keep_map.values())
    log(f"keep: main first-parent {len(main_shas)} commits, open PR heads {len(pr_shas)}, "
        f"graphs {sorted(keep_hashes)}")

    entries = []
    if os.path.exists(index_path):
        with open(index_path) as f:
            entries = [json.loads(line) for line in f if line.strip()]
    mine = [e for e in entries if e["repo"] == repo]
    delete = sorted({e["codebase_hash"] for e in mine} - keep_hashes)

    removed, errors = [], []
    client = None
    for h in delete:
        if a.dry_run:
            log(f"would remove {h}")
            continue
        if client is None:
            client = McpHttpClient(os.environ["CODEBADGER_MCP_URL"], timeout=120)
            client.initialize()
        text, is_error = client.call_tool("remove_cpg", {"codebase_hash": h, "delete_files": True})
        try:
            res = json.loads(text)
        except Exception:
            res = {"raw": text[:300]}
        gone = (not is_error and res.get("success")) or "not found" in text.lower()
        (removed if gone else errors).append({"codebase_hash": h, "result": res})
        log(f"remove_cpg {h}: {'ok' if gone else 'error'} {json.dumps(res)[:200]}")

    if not a.dry_run:
        gone = {r["codebase_hash"] for r in removed}
        kept_entries = [e for e in entries if not (e["repo"] == repo and e["codebase_hash"] in gone)]
        tmp = index_path + ".tmp"
        with open(tmp, "w") as f:
            f.writelines(json.dumps(e) + "\n" for e in kept_entries)
        os.replace(tmp, index_path)

    leftovers = sorted(glob.glob(os.path.join(src_dir, f"{name}-*")) + glob.glob(os.path.join(src_dir, f".{name}-*")))
    for d in leftovers:
        if a.dry_run:
            log(f"would remove source {os.path.basename(d)}")
        elif os.path.isdir(d):
            shutil.rmtree(d)
            log(f"removed source {os.path.basename(d)}")

    record = {"repo": repo, "keep_main": main_shas, "keep_pr_heads": pr_shas, "keep_graphs": keep_map,
              "removed": [r["codebase_hash"] for r in removed], "errors": errors,
              "removed_sources": [os.path.basename(d) for d in leftovers], "dry_run": a.dry_run}
    print("PRUNE " + json.dumps(record, ensure_ascii=False), flush=True)
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a") as f:
            f.write(f"### Joern CPG retention\n\n- kept graphs: {', '.join(f'`{h}`' for h in sorted(keep_hashes)) or 'none'}\n"
                    f"- removed graphs: {', '.join(f'`{h}`' for h in record['removed']) or 'none'}\n"
                    f"- removed source folders: {len(leftovers)}\n")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
