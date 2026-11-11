#!/usr/bin/env python3
"""docs/plan.md 단계 5: 3단계 Q1~Q5(scripts/queries.sc)를 Joern MCP의 CPGQL 실행 도구로 다시 묻는다.

각 질의를 run 1, 2로 두 번 보낸다. 질의 문자열에 run 번호를 넣어 MCP 쪽 결과 캐시를 피한다.
codebadger는 질의를 `(<질의>).take(N).toJsonPretty`로 감싸므로 결과를 한 줄짜리 List로 돌려준다.
질의 안에서 System.nanoTime으로 Joern 안의 실행 시간을 재고, 바깥에서는 MCP 호출 왕복 시간을 잰다.

사용: python3 queries.py <tool 이름> <codebase 인자 JSON> > out.json
  예: python3 queries.py run_cpgql_query '{"codebase_hash":"..."}'
출력: mcp_call.py에 넘길 --call 인자 목록(JSON 배열)
"""
import json
import sys

E = "core/domain/types/evidence.py:<module>.record_evidence_entry"
R = "core/llm/shared/llm_retry.py:<module>.maybe_raise_credit_exhausted"
G = ".github/ci/git_changes.py:<module>.git"

Q = {
    "Q1": f'cpg.method.fullNameExact("{E}").callIn.method.fullName.dedup.l',
    "Q2": f'cpg.method.fullNameExact("{R}").callOut.name.dedup.l',
    "Q3": f'cpg.method.fullNameExact("{E}").callIn.method.callIn.method.fullName.dedup.l',
    "Q4": (f'{{ def source = cpg.method.fullNameExact("{G}").parameter; '
           f'def sink = cpg.call.methodFullNameExact("subprocess.py:<module>.check_output").argument; '
           f'sink.reachableByFlows(source).l }}'),
    "Q5": (f'{{ def source = cpg.method.fullNameExact("{E}").callIn.method.parameter; '
           f'def sink = cpg.method.fullNameExact("{E}").callIn.argument; '
           f'sink.reachableByFlows(source).l }}'),
}


def wrap(q, label, run):
    return ('{ val run = %d; val s = System.nanoTime(); val r = %s; '
            'val ms = (System.nanoTime() - s) / 1e6; List(s"RESULT %s run=$run size=${r.size} joern_ms=$ms") }') % (run, q, label)


if __name__ == "__main__":
    tool, base = sys.argv[1], json.loads(sys.argv[2])
    calls = []
    for run in (1, 2):
        for label, q in Q.items():
            calls.append([tool, json.dumps({**base, "query": wrap(q, label, run)})])
    print(json.dumps(calls))
