#!/usr/bin/env python3
import json
import os
import subprocess

TARGET_ADDRESS = "0x082a0acDe14881b38963c732E00604A587083937"
RPC_ENDPOINT = "http://127.0.0.1:8545"

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


def send(msg):
    server.stdin.write(json.dumps(msg) + "\n")
    server.stdin.flush()
    return server.stdout.readline().strip()


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
    print(send(init))

    server.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
    server.stdin.flush()

    balance = {
        "jsonrpc": "2.0",
        "id": 2,
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
    print(send(balance))

    transfer = {
        "jsonrpc": "2.0",
        "id": 3,
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
                "confirmations": 1,
            },
        },
    }
    print(send(transfer))

    balance2 = {
        "jsonrpc": "2.0",
        "id": 4,
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
    print(send(balance2))
finally:
    server.terminate()
