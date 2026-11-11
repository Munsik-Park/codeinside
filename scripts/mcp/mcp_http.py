#!/usr/bin/env python3
"""표준 라이브러리만으로 쓰는 streamable HTTP MCP 클라이언트 (docs/plan.md 단계 6).

러너 이미지에는 Python 3.10만 있고 mcp 패키지가 없다. 분석 워크플로가 패키지를 내려받지 않고
codebadger MCP를 부를 수 있게 initialize, notifications/initialized, tools/call만 구현한다.
응답은 JSON 또는 SSE(text/event-stream) 둘 다 받는다.

모듈로 쓸 때:
  c = McpHttpClient(url); c.initialize(); res = c.call_tool("get_cpg_status", {...})
명령으로 쓸 때(출력 형식은 mcp_call.py의 --call 줄과 같다):
  python3 mcp_http.py --url <주소> --call 도구 '<JSON 인자>' [--call ...]
"""
import argparse
import itertools
import json
import sys
import time
import urllib.request

PROTOCOL_VERSION = "2025-06-18"


class McpError(RuntimeError):
    pass


class McpHttpClient:
    def __init__(self, url, timeout=900):
        self.url = url
        self.timeout = timeout
        self.session_id = None
        self._ids = itertools.count(1)

    def _post(self, payload, expect_response=True):
        headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
            headers["MCP-Protocol-Version"] = PROTOCOL_VERSION
        req = urllib.request.Request(self.url, data=json.dumps(payload).encode(), headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=self.timeout) as resp:
            sid = resp.headers.get("Mcp-Session-Id")
            if sid:
                self.session_id = sid
            if not expect_response:
                resp.read()
                return None
            ctype = resp.headers.get("Content-Type", "")
            if ctype.startswith("text/event-stream"):
                return self._read_sse(resp, payload.get("id"))
            return json.loads(resp.read().decode())

    @staticmethod
    def _read_sse(resp, want_id):
        data = []
        for raw in resp:
            line = raw.decode().rstrip("\r\n")
            if line.startswith("data:"):
                data.append(line[5:].lstrip())
            elif line == "" and data:
                msg = json.loads("\n".join(data))
                data = []
                if msg.get("id") == want_id and ("result" in msg or "error" in msg):
                    return msg
        raise McpError("SSE 스트림이 응답 없이 끝났다")

    def request(self, method, params):
        msg = self._post({"jsonrpc": "2.0", "id": next(self._ids), "method": method, "params": params})
        if "error" in msg:
            raise McpError(json.dumps(msg["error"], ensure_ascii=False))
        return msg["result"]

    def initialize(self):
        res = self.request("initialize", {"protocolVersion": PROTOCOL_VERSION, "capabilities": {},
                                          "clientInfo": {"name": "codeinside-mcp-http", "version": "1"}})
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"}, expect_response=False)
        return res

    def call_tool(self, name, arguments):
        """도구 결과의 text 부분을 이어 붙여 (text, is_error)로 돌려준다."""
        res = self.request("tools/call", {"name": name, "arguments": arguments})
        text = "".join(c.get("text", "") for c in res.get("content", []) if c.get("type") == "text")
        return text, bool(res.get("isError"))

    def call_tool_json(self, name, arguments):
        text, is_error = self.call_tool(name, arguments)
        if is_error:
            raise McpError(f"{name}: {text}")
        return json.loads(text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", required=True)
    ap.add_argument("--call", nargs=2, action="append", default=[], metavar=("TOOL", "JSON"))
    ap.add_argument("--timeout", type=float, default=900)
    a = ap.parse_args()
    c = McpHttpClient(a.url, a.timeout)
    c.initialize()
    for name, raw in a.call:
        args = json.loads(raw)
        t0 = time.monotonic()
        try:
            text, is_error = c.call_tool(name, args)
        except Exception as e:  # 서버가 호출을 거부하면 예외로 온다
            print(json.dumps({"call": name, "args": args, "exception": f"{type(e).__name__}: {e}"},
                             ensure_ascii=False), flush=True)
            continue
        print(json.dumps({"call": name, "args": args, "seconds": round(time.monotonic() - t0, 3),
                          "is_error": is_error, "text": text}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    sys.exit(main())
