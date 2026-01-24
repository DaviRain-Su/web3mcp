#!/usr/bin/env python3
import json
import os
import subprocess
import time
import select

TARGET_ADDRESS = "0x082a0acDe14881b38963c732E00604A587083937"
RPC_ENDPOINT = "http://127.0.0.1:8545"
TOKEN_ADDRESS = os.environ.get("EVM_TOKEN_ADDRESS")
TOKEN_OWNER = os.environ.get("EVM_TOKEN_OWNER")

server = subprocess.Popen(
    ["./zig-out/bin/omniweb3-mcp"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    text=True,
    env=dict(
        os.environ,
        EVM_PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
    ),
)


def send(msg, timeout_s=8):
    server.stdin.write(json.dumps(msg) + "\n")
    server.stdin.flush()
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        ready, _, _ = select.select([server.stdout], [], [], 0.2)
        if not ready:
            continue
        line = server.stdout.readline()
        if not line:
            return ""
        line = line.strip()
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict) and payload.get("jsonrpc") == "2.0":
            return line
    return "timeout"


try:
    init = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2025-11-25",
            "capabilities": {},
            "clientInfo": {"name": "local-test", "version": "0.0.1"},
        },
    }
    print(send(init, timeout_s=8))

    server.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
    server.stdin.flush()

    block_number = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "get_block_number",
            "arguments": {
                "chain": "ethereum",
                "network": "mainnet",
                "endpoint": RPC_ENDPOINT,
            },
        },
    }
    print(send(block_number, timeout_s=8))

    gas_price = {
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "get_gas_price",
            "arguments": {
                "chain": "ethereum",
                "network": "mainnet",
                "endpoint": RPC_ENDPOINT,
            },
        },
    }
    print(send(gas_price, timeout_s=8))

    nonce = {
        "jsonrpc": "2.0",
        "id": 4,
        "method": "tools/call",
        "params": {
            "name": "get_nonce",
            "arguments": {
                "chain": "ethereum",
                "network": "mainnet",
                "endpoint": RPC_ENDPOINT,
                "address": TARGET_ADDRESS,
            },
        },
    }
    print(send(nonce, timeout_s=8))

    balance = {
        "jsonrpc": "2.0",
        "id": 5,
        "method": "tools/call",
        "params": {
            "name": "get_balance",
            "arguments": {
                "chain": "ethereum",
                "network": "mainnet",
                "endpoint": RPC_ENDPOINT,
                "address": TARGET_ADDRESS,
            },
        },
    }
    print(send(balance, timeout_s=8))

    if TOKEN_ADDRESS and TOKEN_OWNER:
        token_balance = {
            "jsonrpc": "2.0",
            "id": 6,
            "method": "tools/call",
            "params": {
                "name": "token_balance",
                "arguments": {
                    "chain": "ethereum",
                    "network": "mainnet",
                    "endpoint": RPC_ENDPOINT,
                    "token_address": TOKEN_ADDRESS,
                    "owner": TOKEN_OWNER,
                },
            },
        }
        print(send(token_balance, timeout_s=8))

    transfer = {
        "jsonrpc": "2.0",
        "id": 7,
        "method": "tools/call",
        "params": {
            "name": "transfer",
            "arguments": {
                "to_address": TARGET_ADDRESS,
                "amount": "1000000000000000",
                "chain": "ethereum",
                "network": "mainnet",
                "endpoint": RPC_ENDPOINT,
                "tx_type": "eip1559",
                "confirmations": 0,
            },
        },
    }
    print(send(transfer, timeout_s=15))

    balance2 = {
        "jsonrpc": "2.0",
        "id": 8,
        "method": "tools/call",
        "params": {
            "name": "get_balance",
            "arguments": {
                "chain": "ethereum",
                "network": "mainnet",
                "endpoint": RPC_ENDPOINT,
                "address": TARGET_ADDRESS,
            },
        },
    }
    print(send(balance2, timeout_s=8))
finally:
    server.terminate()
