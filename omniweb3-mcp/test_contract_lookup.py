#!/usr/bin/env python3
"""Test contract name resolution"""
import json
import subprocess
import time

def send_request(proc, method, params=None):
    request_id = int(time.time() * 1000)
    request = {
        "jsonrpc": "2.0",
        "id": request_id,
        "method": method,
        "params": params or {}
    }
    proc.stdin.write(json.dumps(request) + '\n')
    proc.stdin.flush()
    response_line = proc.stdout.readline()
    if not response_line:
        return None
    try:
        return json.loads(response_line)
    except:
        return None

def call_tool(proc, tool_name, args):
    response = send_request(proc, "tools/call", {
        "name": tool_name,
        "arguments": args or {}
    })

    if not response or 'error' in response:
        return None, response.get('error') if response else 'No response'

    result = response.get('result', {})
    if result.get('isError'):
        error_msg = ''
        if 'content' in result:
            for item in result['content']:
                if 'text' in item:
                    text = item['text']['text'] if isinstance(item['text'], dict) else item['text']
                    error_msg = text
        return None, error_msg

    if 'content' in result:
        for item in result['content']:
            if 'text' in item:
                text = item['text']['text'] if isinstance(item['text'], dict) else item['text']
                try:
                    return json.loads(text), None
                except:
                    return text, None
    return None, "No content"

def main():
    print("Testing contract name resolution...")

    proc = subprocess.Popen(
        ['./zig-out/bin/omniweb3-mcp'],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1
    )

    try:
        # Initialize
        send_request(proc, "initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "test", "version": "1.0.0"}
        })
        proc.stdin.write(json.dumps({
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
            "params": {}
        }) + '\n')
        proc.stdin.flush()

        # Try a simple read-only call to pancake_testnet
        print("\n📍 Testing pancake_testnet contract resolution...")
        print("   Chain: bsc")
        print("   Contract: pancake_testnet")
        print("   Network: testnet")

        # Try to call a view function (getAmountsOut)
        WBNB = "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd"
        BUSD = "0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee"

        data, error = call_tool(proc, "call_contract", {
            "chain": "bsc",
            "contract": "pancake_testnet",
            "function": "getAmountsOut",
            "args": ["1000000000000000", [WBNB, BUSD]],  # 0.001 BNB
            "network": "testnet",
            "send_transaction": False
        })

        if error:
            print(f"   ❌ Failed: {error}")
        else:
            print(f"   ✅ Success!")
            if data:
                print(f"   Result: {json.dumps(data, indent=2)}")

    finally:
        proc.terminate()
        proc.wait(timeout=5)

if __name__ == '__main__':
    main()
