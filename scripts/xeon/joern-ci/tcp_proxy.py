#!/usr/bin/env python3
"""TCP 포워더: LISTEN 포트로 들어온 연결을 고정된 TARGET 한 곳으로만 넘긴다 (docs/plan.md 단계 6).

opensre 분석 러너가 codebadger 네트워크에 직접 붙지 않고 MCP 4242에만 닿게 하려고 쓴다.
대상은 환경 변수로 고정하고, 클라이언트가 바꿀 수 있는 값은 없다.

환경 변수: PROXY_LISTEN_PORT(기본 4242), PROXY_TARGET_HOST(기본 codebadger-mcp), PROXY_TARGET_PORT(기본 4242)
"""
import asyncio
import os

LISTEN_PORT = int(os.environ.get("PROXY_LISTEN_PORT", "4242"))
TARGET_HOST = os.environ.get("PROXY_TARGET_HOST", "codebadger-mcp")
TARGET_PORT = int(os.environ.get("PROXY_TARGET_PORT", "4242"))


async def pipe(reader, writer):
    try:
        while data := await reader.read(65536):
            writer.write(data)
            await writer.drain()
    except (ConnectionError, asyncio.CancelledError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def handle(c_reader, c_writer):
    peer = c_writer.get_extra_info("peername")
    try:
        t_reader, t_writer = await asyncio.open_connection(TARGET_HOST, TARGET_PORT)
    except OSError as e:
        print(f"connect to {TARGET_HOST}:{TARGET_PORT} failed for {peer}: {e}", flush=True)
        c_writer.close()
        return
    await asyncio.gather(pipe(c_reader, t_writer), pipe(t_reader, c_writer))


async def main():
    server = await asyncio.start_server(handle, "0.0.0.0", LISTEN_PORT)
    print(f"listening on :{LISTEN_PORT} -> {TARGET_HOST}:{TARGET_PORT}", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
