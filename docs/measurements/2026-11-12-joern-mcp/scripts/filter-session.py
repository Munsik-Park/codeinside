#!/usr/bin/env python3
"""docs/plan.md 단계 5: Claude Code stream-json 기록에서 MCP 호출과 답만 남긴다.

init 이벤트의 plugin, skill, slash command, agent, cwd 같은 작업 환경 정보는 버리고
MCP 서버 상태와 이 세 서버의 도구 이름만 남긴다. 긴 도구 결과는 앞부분만 남긴다.
사용: python3 filter-session.py <stream-json> > out.jsonl
"""
import json
import sys

KEEP = ("mcp__joern__", "mcp__ast-grep__", "mcp__serena__")
LIMIT = 6000

for line in open(sys.argv[1], encoding="utf-8"):
    d = json.loads(line)
    t = d.get("type")
    if t == "system" and d.get("subtype") == "init":
        out = {"type": "init", "model": d.get("model"), "mcp_servers": d.get("mcp_servers"),
               "mcp_tools": sorted(x for x in d.get("tools", []) if x.startswith(KEEP))}
    elif t == "assistant":
        items = []
        for c in d["message"]["content"]:
            if c["type"] == "tool_use":
                items.append({"tool_use": c["name"], "input": c["input"]})
            elif c["type"] == "text":
                items.append({"text": c["text"]})
        if not items:
            continue
        out = {"type": "assistant", "content": items}
    elif t == "user":
        items = []
        for c in d["message"]["content"]:
            if isinstance(c, dict) and c.get("type") == "tool_result":
                cc = c["content"]
                s = cc if isinstance(cc, str) else "".join(x.get("text", "") for x in cc)
                items.append({"tool_result_chars": len(s), "is_error": c.get("is_error"),
                              "text": s[:LIMIT] + ("…(잘림)" if len(s) > LIMIT else "")})
        if not items:
            continue
        out = {"type": "tool_result", "content": items}
    elif t == "result":
        out = {"type": "result", "subtype": d.get("subtype"), "num_turns": d.get("num_turns"),
               "duration_ms": d.get("duration_ms"), "total_cost_usd": d.get("total_cost_usd")}
    else:
        continue
    print(json.dumps(out, ensure_ascii=False))
