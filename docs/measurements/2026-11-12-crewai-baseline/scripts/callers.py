#!/usr/bin/env python3
"""Q1과 C1의 호출자·호출 지점을 codebadger MCP로 뽑는다 (docs/plan.md 단계 6, crewAI 기준값).
4단계 callers.sc와 같은 식(callIn.method)이고, 출력 줄 형식(TIME/RESULT/CALLER/CALLSITE)도 같아서 4단계 compare.py에 그대로 넣는다.
사용(러너 네트워크의 컨테이너 안): python3 callers.py <MCP 주소> <codebase_hash>
"""
import json
import os
import sys
import time

sys.path.insert(0, os.environ.get("MCP_HTTP_DIR", "/s"))
from mcp_http import McpHttpClient  # noqa: E402

TARGETS = [
    ("Q1", "lib/crewai/src/crewai/llms/base_llm.py:<module>.BaseLLM._emit_call_completed_event"),
    ("C1", "lib/crewai/src/crewai/memory/unified_memory.py:<module>.Memory.close"),
]
c = McpHttpClient(sys.argv[1], timeout=600)
c.initialize()
for q, fn in TARGETS:
    query = ('{ val s = System.nanoTime(); val callers = cpg.method.fullNameExact("%s").callIn.method.fullName.dedup.l.sorted; '
             'val ms = (System.nanoTime() - s) / 1e6; '
             'val sites = cpg.method.fullNameExact("%s").callIn.map(c => (c.method.fullName, c.method.filename, c.lineNumber.getOrElse(-1), '
             'c.code.linesIterator.nextOption.getOrElse(""))).l.sortBy(x => (x._2, x._3)); '
             'List(f"TIME %s callers $ms%%.1f ms", s"RESULT %s ${callers.size}") ++ callers.map(x => s"CALLER %s\\t$x") ++ '
             'sites.map { case (m, f, l, code) => s"CALLSITE %s\\t$f\\t$l\\t$m\\t$code" } }') % (fn, fn, q, q, q, q)
    t0 = time.monotonic()
    text, err = c.call_tool("run_cpgql_query", {"codebase_hash": sys.argv[2], "query": query, "timeout": 300})
    if err:
        print(f"ERROR {q} {text[:500]}")
        continue
    for line in json.loads(text)["data"]:
        print(line)
    print(f"MCP {q} {time.monotonic() - t0:.3f} s")
