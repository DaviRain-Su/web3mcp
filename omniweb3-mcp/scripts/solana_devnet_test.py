#!/usr/bin/env python3
import json
import os
import subprocess
import time
import select

RPC_ENDPOINT = os.environ.get("SOLANA_RPC_ENDPOINT", "https://api.devnet.solana.com")
TARGET_ADDRESS = os.environ.get("SOLANA_TO_ADDRESS")
AUTO_RECIPIENT_PATH = "/tmp/solana-test-recipient.json"

server = subprocess.Popen(
    ["./zig-out/bin/omniweb3-mcp"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    text=True,
    env=dict(os.environ),
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

    address = os.environ.get("SOLANA_ADDRESS")
    if not address:
        raise SystemExit("Missing SOLANA_ADDRESS env for balance check")

    balance = {
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "get_balance",
            "arguments": {
                "chain": "solana",
                "network": "devnet",
                "endpoint": RPC_ENDPOINT,
                "address": address,
            },
        },
    }
    print(send(balance, timeout_s=8))

    recipient = TARGET_ADDRESS
    if not recipient:
        subprocess.run(
            [
                "solana-keygen",
                "new",
                "--no-bip39-passphrase",
                "--force",
                "-o",
                AUTO_RECIPIENT_PATH,
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        result = subprocess.run(
            ["solana-keygen", "pubkey", AUTO_RECIPIENT_PATH],
            check=True,
            capture_output=True,
            text=True,
        )
        recipient = result.stdout.strip()
        print(f"Generated recipient: {recipient}")

    transfer = {
        "jsonrpc": "2.0",
        "id": 3,
        "method": "tools/call",
        "params": {
            "name": "transfer",
            "arguments": {
                "chain": "solana",
                "to_address": recipient,
                "amount": 10000,
                "network": "devnet",
                "endpoint": RPC_ENDPOINT,
            },
        },
    }
    print(send(transfer, timeout_s=12))
finally:
    server.terminate()
