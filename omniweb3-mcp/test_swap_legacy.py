#!/usr/bin/env python3
"""Test swap with legacy tx and full stderr"""
import json
import subprocess
import time
import threading

def read_stderr(proc):
    for line in proc.stderr:
        print(f"[STDERR] {line.rstrip()}", flush=True)

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
    print("🚀 Testing swap with legacy transaction...\n")

    WBNB = "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd"
    BUSD = "0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee"

    proc = subprocess.Popen(
        ['./zig-out/bin/omniweb3-mcp'],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1
    )

    stderr_thread = threading.Thread(target=read_stderr, args=(proc,), daemon=True)
    stderr_thread.start()

    try:
        time.sleep(0.5)

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

        time.sleep(0.2)

        data, error = call_tool(proc, "wallet_status", {})
        if error:
            print(f"❌ Error: {error}")
            return

        local_address = data['wallets']['ethereum']['local']['address']
        print(f"✅ Address: {local_address}\n")

        amount_in = "10000000000000000"  # 0.01 BNB
        amount_out_min = "0"
        path = [WBNB, BUSD]
        to = local_address
        deadline = str(int(time.time()) + 1200)

        print("🚀 Executing swap with LEGACY transaction...")
        print(f"   Value: 0.01 BNB\n")

        data, error = call_tool(proc, "call_contract", {
            "chain": "bsc",
            "contract": "pancake_testnet",
            "function": "swapExactETHForTokens",
            "args": [amount_out_min, path, to, deadline],
            "value": amount_in,
            "send_transaction": True,
            "network": "testnet",
            "tx_type": "legacy",
            "confirmations": 1
        })

        time.sleep(2)  # Let stderr flush

        if error:
            print(f"\n❌ Swap failed: {error}")
        else:
            print(f"\n✅ Swap succeeded!")
            if data:
                print(f"Result: {json.dumps(data, indent=2)}")

        time.sleep(1)

    finally:
        proc.terminate()
        proc.wait(timeout=5)

if __name__ == '__main__':
    main()
