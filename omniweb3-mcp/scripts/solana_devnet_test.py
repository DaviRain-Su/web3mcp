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
    encoding="utf-8",
    errors="ignore",
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


def extract_tool_payload(line):
    if not line or line == "timeout":
        return None
    try:
        payload = json.loads(line)
    except json.JSONDecodeError:
        return None
    result = payload.get("result") if isinstance(payload, dict) else None
    if not isinstance(result, dict):
        return None
    content = result.get("content")
    if not content:
        return None
    text = content[0].get("text") if isinstance(content, list) and content else None
    if not text:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


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

    if os.environ.get("SOLANA_RUN_AIRDROP") == "1":
        airdrop = {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {
                "name": "request_airdrop",
                "arguments": {
                    "chain": "solana",
                    "amount": 10000000,
                    "network": "devnet",
                    "endpoint": RPC_ENDPOINT,
                    "address": address,
                },
            },
        }
        airdrop_line = send(airdrop, timeout_s=12)
        print(airdrop_line)
        airdrop_payload = extract_tool_payload(airdrop_line)
        if airdrop_payload and airdrop_payload.get("signature"):
            parse_airdrop = {
                "jsonrpc": "2.0",
                "id": 4,
                "method": "tools/call",
                "params": {
                    "name": "parse_transaction",
                    "arguments": {
                        "chain": "solana",
                        "signature": airdrop_payload["signature"],
                        "network": "devnet",
                        "endpoint": RPC_ENDPOINT,
                    },
                },
            }
            print(send(parse_airdrop, timeout_s=12))

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
        "id": 5,
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
    transfer_line = send(transfer, timeout_s=12)
    print(transfer_line)
    transfer_payload = extract_tool_payload(transfer_line)
    if transfer_payload and transfer_payload.get("signature"):
        parse_tx = {
            "jsonrpc": "2.0",
            "id": 6,
            "method": "tools/call",
            "params": {
                "name": "parse_transaction",
                "arguments": {
                    "chain": "solana",
                    "signature": transfer_payload["signature"],
                    "network": "devnet",
                    "endpoint": RPC_ENDPOINT,
                },
            },
        }
        print(send(parse_tx, timeout_s=12))

    epoch_info = {
        "jsonrpc": "2.0",
        "id": 7,
        "method": "tools/call",
        "params": {
            "name": "get_epoch_info",
            "arguments": {
                "chain": "solana",
                "network": "devnet",
                "endpoint": RPC_ENDPOINT,
            },
        },
    }
    print(send(epoch_info, timeout_s=8))

    version = {
        "jsonrpc": "2.0",
        "id": 8,
        "method": "tools/call",
        "params": {
            "name": "get_version",
            "arguments": {
                "chain": "solana",
                "network": "devnet",
                "endpoint": RPC_ENDPOINT,
            },
        },
    }
    print(send(version, timeout_s=8))

    supply = {
        "jsonrpc": "2.0",
        "id": 9,
        "method": "tools/call",
        "params": {
            "name": "get_supply",
            "arguments": {
                "chain": "solana",
                "network": "devnet",
                "endpoint": RPC_ENDPOINT,
            },
        },
    }
    print(send(supply, timeout_s=8))

    signatures = {
        "jsonrpc": "2.0",
        "id": 10,
        "method": "tools/call",
        "params": {
            "name": "get_signatures_for_address",
            "arguments": {
                "chain": "solana",
                "network": "devnet",
                "endpoint": RPC_ENDPOINT,
                "address": address,
                "limit": 5,
            },
        },
    }
    print(send(signatures, timeout_s=8))

    slot_line = send({
        "jsonrpc": "2.0",
        "id": 11,
        "method": "tools/call",
        "params": {
            "name": "get_slot",
            "arguments": {
                "chain": "solana",
                "network": "devnet",
                "endpoint": RPC_ENDPOINT,
            },
        },
    }, timeout_s=8)
    print(slot_line)
    slot_payload = extract_tool_payload(slot_line)
    slot_value = slot_payload.get("slot") if slot_payload else None

    if slot_value is not None:
        block_time = {
            "jsonrpc": "2.0",
            "id": 12,
            "method": "tools/call",
            "params": {
                "name": "get_block_time",
                "arguments": {
                    "chain": "solana",
                    "slot": slot_value,
                    "network": "devnet",
                    "endpoint": RPC_ENDPOINT,
                },
            },
        }
        print(send(block_time, timeout_s=8))
finally:
    server.terminate()
