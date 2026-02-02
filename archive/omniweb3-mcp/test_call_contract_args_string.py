#!/usr/bin/env python3
"""Test call_contract with args as JSON string."""

import json
import subprocess
import time


def send_request(proc, method, params=None):
    if proc.stdin is None or proc.stdout is None:
        raise RuntimeError("Process pipes not available")
    request_id = int(time.time() * 1000)
    request = {
        "jsonrpc": "2.0",
        "id": request_id,
        "method": method,
        "params": params or {},
    }
    proc.stdin.write(json.dumps(request) + "\n")
    proc.stdin.flush()
    response_line = proc.stdout.readline()
    if not response_line:
        return None
    try:
        return json.loads(response_line)
    except json.JSONDecodeError:
        return None


def call_tool(proc, tool_name, args):
    response = send_request(
        proc, "tools/call", {"name": tool_name, "arguments": args or {}}
    )
    if not response or "error" in response:
        return None, response.get("error") if response else "No response"

    result = response.get("result", {})
    if result.get("isError"):
        error_msg = ""
        if "content" in result:
            for item in result["content"]:
                if "text" in item:
                    text = (
                        item["text"]["text"]
                        if isinstance(item["text"], dict)
                        else item["text"]
                    )
                    error_msg = text
        return None, error_msg

    if "content" in result:
        for item in result["content"]:
            if "text" in item:
                text = (
                    item["text"]["text"]
                    if isinstance(item["text"], dict)
                    else item["text"]
                )
                try:
                    return json.loads(text), None
                except json.JSONDecodeError:
                    return text, None
    return None, "No content"


def main():
    print("\n🧪 Testing call_contract with string args...\n")

    proc = subprocess.Popen(
        ["./zig-out/bin/omniweb3-mcp"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    if proc.stdin is None or proc.stdout is None:
        raise RuntimeError("Failed to open stdio pipes")

    try:
        time.sleep(0.5)

        send_request(
            proc,
            "initialize",
            {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "test", "version": "1.0.0"},
            },
        )
        proc.stdin.write(
            json.dumps(
                {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}}
            )
            + "\n"
        )
        proc.stdin.flush()

        time.sleep(0.2)

        print("📍 Reading WBNB name via string args...")
        args_string = json.dumps([])
        data, error = call_tool(
            proc,
            "call_contract",
            {
                "chain": "bsc",
                "network": "testnet",
                "contract": "wbnb_test",
                "function": "name",
                "args": args_string,
            },
        )

        if error:
            print(f"❌ Failed: {error}")
        else:
            print("✅ Success")
            print(json.dumps(data, indent=2))

        time.sleep(0.5)
    finally:
        proc.terminate()
        proc.wait(timeout=5)


if __name__ == "__main__":
    main()
