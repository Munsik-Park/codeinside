#!/usr/bin/env python3
"""opensre 분석 워크플로가 부르는 그래프 생성 작업 (docs/plan.md 단계 6).

한 커밋 SHA에 대해:
  1. 커밋 상태 `codeinside/joern-cpg`를 pending으로 둔다.
  2. `git archive <SHA>`로 소스를 codebadger playground의 CI 폴더에 푼다(이미 있으면 그대로 쓴다).
  3. codebadger MCP `generate_cpg`(source_type=local)를 부르고 `get_cpg_status`가 ready가 될 때까지 기다린다.
  4. 커밋 상태를 success로 바꾸고 설명에 `codebase_hash=<hash>`를 적는다. 이 상태가 SHA와 그래프의 대응 기록이다.
  5. 확인 질의 Q1(3단계와 같은 식)을 MCP로 묻고 결과를 작업 요약에 남긴다.

codebadger의 local 소스 캐시 키는 파일 내용 해시다(core_tools.py `_fingerprint_local_source`).
github 소스는 레포·브랜치 이름이 키라서 브랜치가 움직이면 다른 커밋의 그래프를 다시 쓴다. 그래서 local로 부른다.

환경 변수(러너 컨테이너가 넘긴다):
  CODEBADGER_MCP_URL       러너 네트워크에서 본 MCP 주소(프록시)
  CODEBADGER_SRC_DIR       러너 컨테이너 안에서 본 CI 소스 폴더
  CODEBADGER_SRC_MCP_DIR   같은 폴더를 MCP 컨테이너 안에서 본 경로
환경 변수(워크플로가 넘긴다):
  GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_SERVER_URL, GITHUB_RUN_ID, GITHUB_STEP_SUMMARY(선택)

사용: python3 joern_cpg_job.py --checkout <opensre 체크아웃> --sha <커밋 SHA>
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "mcp"))
from mcp_http import McpHttpClient  # noqa: E402

STATUS_CONTEXT = "codeinside/joern-cpg"
E = "core/domain/types/evidence.py:<module>.record_evidence_entry"
Q1 = f'cpg.method.fullNameExact("{E}").callIn.method.fullName.dedup.l'
Q1_WRAPPED = ('{ val s = System.nanoTime(); val r = %s; val ms = (System.nanoTime() - s) / 1e6; '
              'List(s"RESULT Q1 size=${r.size} joern_ms=$ms") }') % Q1


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def set_status(sha, state, description):
    repo = os.environ["GITHUB_REPOSITORY"]
    run_url = f"{os.environ.get('GITHUB_SERVER_URL', 'https://github.com')}/{repo}/actions/runs/{os.environ.get('GITHUB_RUN_ID', '')}"
    body = json.dumps({"state": state, "context": STATUS_CONTEXT, "description": description[:140],
                       "target_url": run_url}).encode()
    req = urllib.request.Request(
        f"https://api.github.com/repos/{repo}/statuses/{sha}", data=body, method="POST",
        headers={"Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}",
                 "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"})
    with urllib.request.urlopen(req, timeout=30) as r:
        r.read()
    log(f"commit status {state}: {description}")


def extract(checkout, sha, src_dir):
    dest = os.path.join(src_dir, f"opensre-{sha}")
    if os.path.isdir(dest):
        log(f"source already extracted: opensre-{sha}")
        return dest
    tmp = tempfile.mkdtemp(prefix=f".opensre-{sha}.", dir=src_dir)
    archive = subprocess.Popen(["git", "-C", checkout, "archive", "--format=tar", sha], stdout=subprocess.PIPE)
    subprocess.run(["tar", "-x", "-C", tmp], stdin=archive.stdout, check=True)
    if archive.wait() != 0:
        shutil.rmtree(tmp, ignore_errors=True)
        raise RuntimeError("git archive failed")
    os.chmod(tmp, 0o755)
    os.rename(tmp, dest)
    log(f"extracted opensre-{sha}")
    return dest


def wait_ready(client, codebase_hash, timeout_s):
    t0 = time.monotonic()
    last = None
    while True:
        st = client.call_tool_json("get_cpg_status", {"codebase_hash": codebase_hash})
        status = st.get("status")
        if status != last:
            log(f"cpg status: {status}")
            last = status
        if status == "ready":
            return st, time.monotonic() - t0
        if status in ("failed", "error", "not_found"):
            raise RuntimeError(f"cpg {codebase_hash} {status}: {st.get('error') or st.get('message')}")
        if time.monotonic() - t0 > timeout_s:
            raise TimeoutError(f"cpg {codebase_hash} not ready after {timeout_s}s (last status {status})")
        time.sleep(5)


def summary(lines):
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a") as f:
            f.write("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkout", required=True)
    ap.add_argument("--sha", required=True)
    ap.add_argument("--timeout", type=int, default=1200, help="그래프가 ready가 될 때까지 기다리는 최대 초")
    a = ap.parse_args()
    sha = subprocess.run(["git", "-C", a.checkout, "rev-parse", "--verify", f"{a.sha}^{{commit}}"],
                         check=True, capture_output=True, text=True).stdout.strip()
    src_dir = os.environ["CODEBADGER_SRC_DIR"]
    mcp_src_dir = os.environ["CODEBADGER_SRC_MCP_DIR"]

    set_status(sha, "pending", "building Joern CPG")
    try:
        extract(a.checkout, sha, src_dir)
        client = McpHttpClient(os.environ["CODEBADGER_MCP_URL"], timeout=600)
        client.initialize()
        t0 = time.monotonic()
        gen = client.call_tool_json("generate_cpg", {
            "source_type": "local", "source_path": f"{mcp_src_dir}/opensre-{sha}",
            "language": "python", "force": True})
        codebase_hash = gen.get("codebase_hash")
        if not codebase_hash:
            raise RuntimeError(f"generate_cpg returned no codebase_hash: {json.dumps(gen)[:500]}")
        log(f"generate_cpg: codebase_hash={codebase_hash} status={gen.get('status')}")
        _, waited = wait_ready(client, codebase_hash, a.timeout)
        total = time.monotonic() - t0
        set_status(sha, "success", f"codebase_hash={codebase_hash}")
    except Exception as e:
        set_status(sha, "failure", f"{type(e).__name__}: {e}")
        raise

    q0 = time.monotonic()
    text, is_error = client.call_tool("run_cpgql_query", {"codebase_hash": codebase_hash, "query": Q1_WRAPPED})
    q_seconds = time.monotonic() - q0
    result = json.dumps(text)[:300] if is_error else text.strip()
    log(f"Q1 via MCP ({q_seconds:.2f}s): {result}")
    record = {"sha": sha, "codebase_hash": codebase_hash, "generate_status": gen.get("status"),
              "generate_to_ready_seconds": round(total, 1), "q1": result, "q1_mcp_seconds": round(q_seconds, 3),
              "q1_is_error": is_error}
    print("RECORD " + json.dumps(record, ensure_ascii=False), flush=True)
    summary([f"### Joern CPG for `{sha[:12]}`", "",
             f"- codebase_hash: `{codebase_hash}` (generate_cpg status `{gen.get('status')}`)",
             f"- generate → ready: {total:.1f}s", f"- Q1 via MCP ({q_seconds:.2f}s): `{result}`"])
    return 1 if is_error else 0


if __name__ == "__main__":
    sys.exit(main())
