#!/usr/bin/env python3
"""커밋 SHA로 질의할 codebadger 그래프를 고른다 (docs/plan.md 단계 6, 조상 그래프 대체).

대응 기록은 opensre 커밋 상태 `codeinside/joern-cpg`다. 분석 워크플로가 그래프를 만들면
success 상태의 설명에 `codebase_hash=<hash>`를 적는다.

고르는 순서:
  1. 요청한 SHA부터 first-parent 조상을 가까운 순서로 본다(`git rev-list --first-parent`).
     PR 브랜치는 PR 커밋을 거쳐 분기점의 main 커밋으로, main은 푸시 단위 커밋으로 이어진다.
  2. 상태가 success인 첫 커밋의 codebase_hash를 고른다. --mcp-url을 주면 codebadger에 그래프가
     아직 있는지(ready, sleeping, loading) 확인하고, 지워졌으면 다음 조상으로 넘어간다.
  3. 요청한 SHA가 아닌 조상을 골랐으면 그 사이에 바뀐 파일 목록을 같이 돌려준다.
     질의하는 쪽은 이 파일에 대한 답이 요청한 커밋과 다를 수 있음을 알고 쓴다.

상태 조회는 GraphQL 한 번에 묶는다(`gh api graphql`, 작업자 쪽 gh 인증을 쓴다).

사용:
  python3 resolve_graph.py --checkout <opensre 체크아웃> --sha <SHA> [--repo Munsik-Park/opensre]
                           [--mcp-url http://127.0.0.1:<터널 포트>/mcp] [--max-ancestors 100]
출력: JSON 한 줄
"""
import argparse
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "mcp"))

STATUS_CONTEXT = "codeinside/joern-cpg"
AVAILABLE = ("ready", "sleeping", "loading")
HASH_RE = re.compile(r"codebase_hash=([0-9a-f]{16,64})")


def git(checkout, *args):
    return subprocess.run(["git", "-C", checkout, *args], check=True, capture_output=True, text=True).stdout


def fetch_statuses(repo, shas):
    owner, name = repo.split("/")
    fields = "\n".join(
        f'c{i}: object(oid: "{sha}") {{ ... on Commit {{ status {{ context(name: "{STATUS_CONTEXT}") '
        f'{{ state description }} }} }} }}' for i, sha in enumerate(shas))
    query = f'query {{ repository(owner: "{owner}", name: "{name}") {{ {fields} }} }}'
    out = subprocess.run(["gh", "api", "graphql", "-f", f"query={query}"], check=True,
                         capture_output=True, text=True).stdout
    repo_data = json.loads(out)["data"]["repository"]
    result = {}
    for i, sha in enumerate(shas):
        ctx = ((repo_data.get(f"c{i}") or {}).get("status") or {}).get("context")
        result[sha] = ctx  # None이면 상태 없음
    return result


def graph_available(mcp_url, codebase_hash, cache={}):
    if not mcp_url:
        return None
    if "client" not in cache:
        from mcp_http import McpHttpClient
        cache["client"] = McpHttpClient(mcp_url, timeout=60)
        cache["client"].initialize()
    st = cache["client"].call_tool_json("get_cpg_status", {"codebase_hash": codebase_hash})
    return st.get("status")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkout", required=True)
    ap.add_argument("--sha", required=True)
    ap.add_argument("--repo", default="Munsik-Park/opensre")
    ap.add_argument("--mcp-url")
    ap.add_argument("--max-ancestors", type=int, default=100)
    a = ap.parse_args()

    shas = git(a.checkout, "rev-list", "--first-parent", f"--max-count={a.max_ancestors}", a.sha).split()
    requested = shas[0]
    statuses = fetch_statuses(a.repo, shas)
    req_ctx = statuses[requested]
    skipped = []
    for distance, sha in enumerate(shas):
        ctx = statuses[sha]
        if not ctx or ctx["state"] != "SUCCESS":
            continue
        m = HASH_RE.search(ctx["description"] or "")
        if not m:
            continue
        codebase_hash = m.group(1)
        cb_status = graph_available(a.mcp_url, codebase_hash)
        if cb_status is not None and cb_status not in AVAILABLE:
            skipped.append({"sha": sha, "codebase_hash": codebase_hash, "codebadger_status": cb_status})
            continue
        out = {"requested_sha": requested,
               "requested_status": req_ctx["state"].lower() if req_ctx else None,
               "graph_sha": sha, "codebase_hash": codebase_hash, "exact": distance == 0,
               "first_parent_distance": distance, "codebadger_status": cb_status, "skipped": skipped}
        if distance:
            changed = git(a.checkout, "diff", "--name-only", sha, requested).split()
            out["changed_files_since_graph"] = len(changed)
            out["changed_files"] = changed[:100]
        print(json.dumps(out, ensure_ascii=False))
        return 0
    print(json.dumps({"requested_sha": requested, "graph_sha": None, "searched": len(shas), "skipped": skipped},
                     ensure_ascii=False))
    return 2


if __name__ == "__main__":
    sys.exit(main())
