#!/usr/bin/env python3
"""stdio MCP 서버를 띄워 tools/list와 tools/call을 직접 보낸다.

Claude Code를 거치지 않고 MCP 서버가 실제로 내놓는 도구 목록과 응답을 기록하려고 쓴다.

사용:
  uv run --with mcp==<버전> python scripts/mcp/mcp_call.py [--call 도구 '<JSON 인자>']... -- <서버 명령...>

출력: 한 줄에 JSON 하나. 첫 줄은 tools/list 결과(이름 정렬), 이어서 --call마다 한 줄.
"""
import argparse
import asyncio
import json
import sys
import time

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def main(calls, server_cmd, timeout):
    params = StdioServerParameters(command=server_cmd[0], args=server_cmd[1:])
    async with stdio_client(params) as (r, w):
        async with ClientSession(r, w) as s:
            await s.initialize()
            tools = await s.list_tools()
            names = sorted(t.name for t in tools.tools)
            print(json.dumps({"tools": names}, ensure_ascii=False), flush=True)
            for name, raw in calls:
                t0 = time.monotonic()
                try:
                    res = await asyncio.wait_for(s.call_tool(name, json.loads(raw)), timeout)
                except Exception as e:  # 서버가 호출을 거부하면 예외로 온다
                    print(json.dumps({"call": name, "args": json.loads(raw), "exception": f"{type(e).__name__}: {e}"},
                                     ensure_ascii=False), flush=True)
                    continue
                dt = time.monotonic() - t0
                text = "".join(c.text for c in res.content if getattr(c, "type", "") == "text")
                print(json.dumps({"call": name, "args": json.loads(raw), "seconds": round(dt, 3),
                                  "is_error": bool(getattr(res, "is_error", getattr(res, "isError", False))), "text": text}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    argv = sys.argv[1:]
    if "--" not in argv:
        sys.exit("서버 명령 앞에 -- 가 필요하다")
    i = argv.index("--")
    ap = argparse.ArgumentParser()
    ap.add_argument("--call", nargs=2, action="append", default=[], metavar=("TOOL", "JSON"))
    ap.add_argument("--timeout", type=float, default=900)
    a = ap.parse_args(argv[:i])
    asyncio.run(main(a.call, argv[i + 1:], a.timeout))
