"""Synthetic tools served by the unmodified official MCP Python SDK 2.2.0."""

from __future__ import annotations

import argparse
import asyncio
import importlib.metadata
import json
import os
import signal
import socket
from pathlib import Path
from typing import Any

import uvicorn
from mcp.server import MCPServer
from mcp.server.mcpserver import Context
from mcp.server.mcpserver.exceptions import ToolError


SDK_VERSION = "2.2.0"
PROFILES = {
    "stdio": {"protocol": "2024-11-05"},
    "http-json-session": {"protocol": "2025-06-18", "json": True, "stateless": False},
    "http-json-stateless": {"protocol": "2025-06-18", "json": True, "stateless": True},
    "http-sse-session": {"protocol": "2025-06-18", "json": False, "stateless": False},
    "http-sse-stateless": {"protocol": "2025-06-18", "json": False, "stateless": True},
}


def versions() -> dict[str, str]:
    result = {name: importlib.metadata.version(name) for name in ("mcp", "mcp-types")}
    if set(result.values()) != {SDK_VERSION}:
        raise RuntimeError(f"Expected official mcp and mcp-types {SDK_VERSION}, got {result}")
    return result


class Journal:
    def __init__(self, path: Path):
        self.path = path

    def write(self, event: str, **fields: Any) -> None:
        # Tools and endpoints are synthetic. Never log an inherited environment.
        line = json.dumps({"event": event, **fields}, ensure_ascii=False)
        with self.path.open("a", encoding="utf-8") as stream:
            stream.write(line + "\n")


def server(journal: Journal) -> MCPServer:
    async def observe(ctx: Any, call_next: Any) -> Any:
        journal.write(
            "request", method=ctx.method, id=ctx.request_id,
            protocol=ctx.protocol_version, params=ctx.params,
        )
        try:
            result = await call_next(ctx)
            journal.write("handled", method=ctx.method, id=ctx.request_id)
            return result
        except BaseException as error:
            journal.write("handler_error", method=ctx.method, id=ctx.request_id, kind=type(error).__name__)
            raise

    mcp = MCPServer("ExAgent official SDK interop", version="1", middleware=[observe], log_level="WARNING")

    def identity(ctx: Context) -> Any:
        # Preserve the SDK's actual request ID type; Context.request_id returns a string.
        return ctx.request_context.request_id

    @mcp.tool(structured_output=False)
    async def echo(text: str, ctx: Context) -> str:
        """Return synthetic text and the exact SDK request ID."""
        return json.dumps({"text": text, "request_id": identity(ctx)}, ensure_ascii=False)

    @mcp.tool(structured_output=False)
    async def record(token: str, text: str, ctx: Context) -> str:
        """Append one observable effect. No deduplication hides replay."""
        journal.write("effect", token=token, text=text, id=identity(ctx))
        return json.dumps({"token": token, "text": text, "request_id": identity(ctx)}, ensure_ascii=False)

    @mcp.tool(structured_output=False)
    async def fail() -> str:
        """Return an anticipated SDK tool error, with text content."""
        raise ToolError("synthetic tool failure")

    @mcp.tool(structured_output=False)
    async def large() -> str:
        """Produce text exceeding the harness's HTTP response cap."""
        return "x" * (65 * 1024 + 1)

    return mcp


class HTTPObserver:
    """Pass-through ASGI observation; the SDK owns every MCP reply and session."""

    def __init__(self, app: Any, journal: Journal):
        self.app = app
        self.journal = journal

    async def __call__(self, scope: Any, receive: Any, send: Any) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        incoming = bytearray()
        outgoing = bytearray()
        status = None
        response_headers = []
        complete = False

        async def tap_receive() -> Any:
            message = await receive()
            if message["type"] == "http.request":
                incoming.extend(message.get("body", b""))
                if len(incoming) > 256 * 1024:
                    raise RuntimeError("Synthetic observation request cap exceeded")
            return message

        async def tap_send(message: Any) -> None:
            nonlocal status, response_headers, complete
            if message["type"] == "http.response.start":
                status = message["status"]
                response_headers = [(k.decode("ascii"), v.decode("ascii")) for k, v in message["headers"]]
            if message["type"] == "http.response.body":
                outgoing.extend(message.get("body", b""))
                if len(outgoing) > 256 * 1024:
                    raise RuntimeError("Synthetic observation response cap exceeded")
                complete = not message.get("more_body", False)
            await send(message)

        try:
            await self.app(scope, tap_receive, tap_send)
        finally:
            # The raw, synthetic response permits auditing JSON/SSE IDs without
            # injecting messages, changing framing, or replacing the SDK transport.
            self.journal.write(
                "http", verb=scope["method"], path=scope["path"], status=status,
                request_headers=[(k.decode("ascii"), v.decode("ascii")) for k, v in scope["headers"]],
                response_headers=response_headers,
                request_body=incoming.decode("utf-8"), response_body=outgoing.decode("utf-8"),
                complete=complete,
            )


async def serve_http(mcp: MCPServer, profile: str, journal: Journal, ready: Path) -> None:
    config = PROFILES[profile]
    app = mcp.streamable_http_app(
        json_response=config["json"], stateless_http=config["stateless"], host="127.0.0.1",
    )
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.bind(("127.0.0.1", 0))
    listener.listen(16)
    http = uvicorn.Server(uvicorn.Config(
        HTTPObserver(app, journal), host="127.0.0.1", port=0, log_level="warning",
        access_log=False, lifespan="on", http="h11", timeout_graceful_shutdown=3,
    ))
    task = asyncio.create_task(http.serve(sockets=[listener]))
    try:
        deadline = asyncio.get_running_loop().time() + 15
        while not http.started:
            if task.done():
                await task
                raise RuntimeError("SDK HTTP peer exited before readiness")
            if asyncio.get_running_loop().time() >= deadline:
                raise TimeoutError("SDK HTTP peer readiness deadline")
            await asyncio.sleep(0.01)
        endpoint = f"http://127.0.0.1:{listener.getsockname()[1]}/mcp"
        ready.write_text(json.dumps({"url": endpoint, "pid": os.getpid()}), encoding="utf-8")
        journal.write("ready", url=endpoint, pid=os.getpid())
        await task
    finally:
        listener.close()
        if not task.done():
            http.should_exit = True
            await task


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=PROFILES, required=True)
    parser.add_argument("--journal", type=Path, required=True)
    parser.add_argument("--ready", type=Path)
    parser.add_argument("--check", action="store_true", help="Inspect SDK API/schema only; no transport starts")
    args = parser.parse_args()
    sdk = versions()
    journal = Journal(args.journal)
    mcp = server(journal)
    if args.check:
        tools = asyncio.run(mcp.list_tools())
        assert {tool.name for tool in tools} == {"echo", "record", "fail", "large"}
        record = next(tool for tool in tools if tool.name == "record")
        assert set(record.input_schema["required"]) == {"token", "text"}
        assert set(record.input_schema["properties"]) == {"token", "text"}
        print(json.dumps({"sdk": sdk, "tools": sorted(tool.name for tool in tools), "interop_executed": False}))
        return
    journal.write("start", sdk=sdk, pid=os.getpid(), profile=args.profile, config=PROFILES[args.profile])
    try:
        if args.profile == "stdio":
            mcp.run(transport="stdio")
        elif args.ready is None:
            raise ValueError("HTTP profiles require --ready")
        else:
            # Uvicorn owns TERM while serving and replays it after orderly ASGI
            # shutdown. Consume that final replay in the host so journal/stdio
            # cleanup below runs and the peer exits normally. No SDK is patched.
            signal.signal(signal.SIGTERM, lambda _signum, _frame: None)
            asyncio.run(serve_http(mcp, args.profile, journal, args.ready))
    finally:
        journal.write("stop", pid=os.getpid())


if __name__ == "__main__":
    main()
