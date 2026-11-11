#!/usr/bin/env python3
"""crewAI Q1~Q5(config/queries/crewai.json)를 codebadger MCP로 두 번씩 묻는다 (docs/plan.md 단계 6, crewAI 기준값).
5단계 queries.py와 같이 질의 안에서 System.nanoTime으로 Joern 안 실행 시간을, 바깥에서 MCP 왕복 시간을 잰다.
질의 문자열에 run 번호를 넣어 codebadger 결과 캐시를 피한다.
사용(러너 네트워크의 컨테이너 안): python3 run-queries.py <MCP 주소> <codebase_hash> <queries.json> [--list Q1,Q2]
--list로 준 질의는 결과 목록 전체도 남긴다.
"""
import json
import os
import sys
import time

sys.path.insert(0, os.environ.get("MCP_HTTP_DIR", "/s"))
from mcp_http import McpHttpClient  # noqa: E402


def wrap(q, label, run, full):
    body = 'List(s"RESULT %s run=$run size=${r.size} joern_ms=$ms")' % label
    if full:
        body += ' ++ r.map(x => s"ITEM %s\\t$x")' % label
    return '{ val run = %d; val s = System.nanoTime(); val r = %s; val ms = (System.nanoTime() - s) / 1e6; %s }' % (run, q, body)


def main():
    url, h, qfile = sys.argv[1:4]
    full = set(sys.argv[5].split(",")) if len(sys.argv) > 5 and sys.argv[4] == "--list" else set()
    queries = json.load(open(qfile))
    c = McpHttpClient(url, timeout=900)
    c.initialize()
    for run in (1, 2):
        for label, q in queries.items():
            t0 = time.monotonic()
            text, err = c.call_tool("run_cpgql_query", {"codebase_hash": h, "query": wrap(q, label, run, run == 1 and label in full), "timeout": 600})
            dt = round(time.monotonic() - t0, 3)
            try:
                data = json.loads(text).get("data")
            except Exception:
                data = text[:2000]
            print(json.dumps({"label": label, "run": run, "mcp_seconds": dt, "is_error": err, "data": data}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
