#!/usr/bin/env python3
"""Test complete swap functionality with transaction signing"""

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
    except:
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
                except:
                    return text, None
    return None, "No content"


def wait_for_receipt(proc, tx_hash, timeout_seconds=60, poll_interval=3):
    print("\n⏳ 等待交易确认...")
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        data, error = call_tool(
            proc,
            "get_transaction",
            {
                "chain": "bsc",
                "tx_hash": tx_hash,
                "network": "testnet",
            },
        )
        if data and data.get("receipt_status") == "true":
            print("✅ 交易已确认!")
            if "receipt_block" in data:
                print(f"   区块: {data['receipt_block']}")
            return data
        if error:
            print(f"⚠️ 查询回执失败: {error}")
        time.sleep(poll_interval)
    print("⏱️ 超时未确认，请用区块浏览器查看")
    return None


def main():
    print("=" * 80)
    print("🚀 完整的 BSC Testnet Swap 测试 (0.01 BNB → BUSD)")
    print("=" * 80)

    WBNB = "0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd"
    BUSD = "0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee"

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
        # Initialize
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

        # Get wallet address
        print("\n📍 Step 1: 获取钱包地址")
        print("-" * 80)
        data, error = call_tool(proc, "wallet_status", {})
        if error:
            print(f"❌ 错误: {error}")
            return
        if not data:
            print("❌ 未返回钱包信息")
            return

        local_address = data["wallets"]["ethereum"]["local"]["address"]
        print(f"✅ 本地地址: {local_address}")

        # Check initial balances
        print(f"\n💰 Step 2: 检查初始余额")
        print("-" * 80)

        # BNB balance
        data, error = call_tool(
            proc,
            "get_balance",
            {"chain": "bsc", "address": local_address, "network": "testnet"},
        )
        if data:
            bnb_before = float(data.get("balance_eth", "0"))
            print(f"✅ BNB 余额: {bnb_before} BNB")
            if bnb_before < 0.01:
                print(f"❌ BNB 余额不足")
                return
        else:
            print(f"❌ 查询失败")
            return

        # BUSD balance before
        data, error = call_tool(
            proc,
            "token_balance",
            {
                "chain": "bsc",
                "owner": local_address,
                "token_address": BUSD,
                "network": "testnet",
            },
        )
        busd_before = 0
        if data:
            busd_before = float(data.get("balance_wei", "0")) / (10**18)
            print(f"✅ BUSD 余额: {busd_before:.6f} BUSD")

        # Prepare swap parameters
        print(f"\n🔧 Step 3: 准备 Swap 参数")
        print("-" * 80)

        amount_in = "10000000000000000"  # 0.01 BNB
        amount_out_min = "0"  # Accept any amount for testing
        path = [WBNB, BUSD]
        to = local_address
        deadline = str(int(time.time()) + 1200)  # 20 minutes from now

        print(f"   合约: pancake_testnet")
        print(f"   函数: swapExactETHForTokens")
        print(f"   输入: 0.01 BNB")
        print(f"   路径: WBNB → BUSD")
        print(f"   接收地址: {to}")
        print(f"   截止时间: {deadline}")

        # Execute swap
        print(f"\n🚀 Step 4: 执行 Swap 交易")
        print("-" * 80)
        print(f"⏳ 发送交易中...")

        data, error = call_tool(
            proc,
            "call_contract",
            {
                "chain": "bsc",
                "contract": "pancake_testnet",
                "function": "swapExactETHForTokens",
                "args": [amount_out_min, path, to, deadline],
                "value": amount_in,
                "send_transaction": True,
                "network": "testnet",
                "tx_type": "legacy",
                "confirmations": 0,
            },
        )

        if error:
            print(f"❌ Swap 失败: {error}")
            return
        else:
            print(f"✅ Swap 成功!")
            if data:
                print(f"\n📋 交易详情:")
                print(json.dumps(data, indent=2))

                if "tx_hash" in data:
                    tx_hash = data["tx_hash"]
                    print(f"\n🔗 交易哈希: {tx_hash}")
                    print(f"📊 区块链浏览器:")
                    print(f"   https://testnet.bscscan.com/tx/{tx_hash}")

                if "tx_hash" in data:
                    wait_for_receipt(proc, data["tx_hash"])

        # Check final balances
        print(f"\n💰 Step 5: 检查最终余额")
        print("-" * 80)

        # BNB balance after
        data, error = call_tool(
            proc,
            "get_balance",
            {"chain": "bsc", "address": local_address, "network": "testnet"},
        )
        if data:
            bnb_after = float(data.get("balance_eth", "0"))
            bnb_used = bnb_before - bnb_after
            print(f"✅ BNB 余额: {bnb_after} BNB")
            print(f"   使用了: {bnb_used:.6f} BNB (包含 gas)")

        # BUSD balance after
        time.sleep(2)  # Wait a bit for state to update
        data, error = call_tool(
            proc,
            "token_balance",
            {
                "chain": "bsc",
                "owner": local_address,
                "token_address": BUSD,
                "network": "testnet",
            },
        )
        if data:
            busd_after = float(data.get("balance_wei", "0")) / (10**18)
            busd_received = busd_after - busd_before
            print(f"✅ BUSD 余额: {busd_after:.6f} BUSD")
            if busd_received > 0:
                print(f"   获得了: {busd_received:.6f} BUSD 🎉")

        print(f"\n{'=' * 80}")
        print("🎉 Swap 测试完成!")
        print(f"{'=' * 80}")

    finally:
        proc.terminate()
        proc.wait(timeout=5)


if __name__ == "__main__":
    main()
