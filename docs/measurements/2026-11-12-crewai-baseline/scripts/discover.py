#!/usr/bin/env python3
"""crewAI 기준 그래프에서 Q1~Q5 후보와 흔한 이름 메서드 후보를 찾는다 (docs/plan.md 단계 6, crewAI 기준값).
3단계 discover.sc, discover2.sc, 4단계 common-candidates.sc와 같은 기준을 codebadger MCP 질의로 묻는다.

사용(러너 네트워크의 컨테이너 안): python3 discover.py <MCP 주소> <codebase_hash>
출력: 질의마다 JSON 한 줄(label, query, 결과 문자열 목록)
"""
import json
import os
import sys

sys.path.insert(0, os.environ.get("MCP_HTTP_DIR", "/s"))
from mcp_http import McpHttpClient  # noqa: E402

INTERNAL = 'cpg.method.isExternal(false).filterNot(_.name.contains("<")).l'
QUERIES = {
    # 3단계 discover2.sc: 이름이 레포 안에서 하나뿐인 함수 중 호출이 많은 것
    "UNIQUE_TOP_CALLED": f'{INTERNAL}.groupBy(_.name).filter(_._2.size == 1).values.map(_.head).toList'
                         '.map(m => (m.fullName, m.callIn.size, m.callOut.size, m.parameter.size)).sortBy(-_._2).take(25).map(_.toString)',
    # 4단계 common-candidates.sc: 정의가 여러 개인 이름과 그 이름의 호출 지점 수
    "COMMON_NAMES": f'{INTERNAL}.groupBy(_.name).filter(_._2.size >= 5).toList'
                    '.map { case (n, ms) => (n, ms.size, cpg.call.nameExact(n).size) }.sortBy(-_._2).take(30).map(_.toString)',
    # 3단계 discover2.sc: subprocess 호출 지점(데이터 흐름 Q4 후보)
    "SUBPROCESS_CALLS": 'cpg.call.methodFullName(".*subprocess.*").map(c => (c.methodFullName, c.method.fullName, c.lineNumber.getOrElse(-1)).toString).l.take(40)',
}

def main():
    url, h = sys.argv[1], sys.argv[2]
    c = McpHttpClient(url, timeout=600)
    c.initialize()
    for label, q in QUERIES.items():
        text, err = c.call_tool("run_cpgql_query", {"codebase_hash": h, "query": q, "timeout": 300})
        try:
            data = json.loads(text).get("data")
        except Exception:
            data = None
        print(json.dumps({"label": label, "query": q, "is_error": err, "data": data if data is not None else text[:2000]},
                         ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
