#!/usr/bin/env python3
import json
import os
import subprocess
import time
import select
import urllib.request


def load_dotenv(path):
    if not os.path.exists(path):
        return
    with open(path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip("\"").strip("'")
            if key and key not in os.environ:
                os.environ[key] = value


ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
load_dotenv(os.path.join(ROOT_DIR, ".env"))

RPC_ENDPOINT = os.environ.get("SOLANA_RPC_ENDPOINT", "https://api.devnet.solana.com")
NETWORK = os.environ.get("SOLANA_NETWORK", "devnet")
TARGET_ADDRESS = os.environ.get("SOLANA_TO_ADDRESS")
AUTO_RECIPIENT_PATH = "/tmp/solana-test-recipient.json"
TOKEN_PROGRAM_ID = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
SOL_MINT = "So11111111111111111111111111111111111111112"
USDC_MINT = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
RUN_JUPITER = os.environ.get("SOLANA_RUN_JUPITER") == "1"
JUPITER_API_KEY = os.environ.get("JUPITER_API_KEY")
JUPITER_API_ENDPOINT = os.environ.get("JUPITER_API_ENDPOINT")
JUPITER_PRICE_ENDPOINT = os.environ.get("JUPITER_PRICE_ENDPOINT")
JUPITER_PRICE_MINT = os.environ.get("JUPITER_PRICE_MINT", SOL_MINT)
JUPITER_INSECURE = os.environ.get("JUPITER_INSECURE") == "1"

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


def rpc_call(method, params=None):
    body = {"jsonrpc": "2.0", "id": 1, "method": method}
    if params is not None:
        body["params"] = params
    req = urllib.request.Request(
        RPC_ENDPOINT,
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=8) as resp:
        data = resp.read().decode("utf-8")
        return json.loads(data)


def parse_message_from_output(output: str):
    for line in output.splitlines():
        if "Transaction Message:" in line:
            return line.split("Transaction Message:", 1)[-1].strip()
    return None


def parse_token_from_output(output: str):
    for line in output.splitlines():
        if "Address:" in line:
            return line.split("Address:", 1)[-1].strip()
        if "Creating token" in line:
            return line.split("Creating token", 1)[-1].split("under program", 1)[0].strip()
        if "Token:" in line:
            return line.split("Token:", 1)[-1].strip()
        if "token:" in line:
            return line.split("token:", 1)[-1].strip()
    return None


def parse_account_from_output(output: str):
    for line in output.splitlines():
        if "Creating account" in line:
            return line.split("Creating account", 1)[-1].strip()
        if "Account:" in line:
            return line.split("Account:", 1)[-1].strip()
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
                "network": NETWORK,
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
                    "network": NETWORK,
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
                        "network": NETWORK,
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
                "network": NETWORK,
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
                    "network": NETWORK,
                    "endpoint": RPC_ENDPOINT,
                },
            },
        }
        print(send(parse_tx, timeout_s=12))

    run_mint = os.environ.get("SOLANA_RUN_MINT") == "1"
    mint = os.environ.get("SOLANA_MINT")
    if run_mint:
        create_token = subprocess.run(
            ["spl-token", "create-token", "--url", RPC_ENDPOINT],
            check=True,
            capture_output=True,
            text=True,
        )
        mint = parse_token_from_output(create_token.stdout + "\n" + create_token.stderr)
        if not mint:
            raise SystemExit("Failed to parse mint address from spl-token output")
        create_account = subprocess.run(
            ["spl-token", "create-account", mint, "--url", RPC_ENDPOINT],
            check=True,
            capture_output=True,
            text=True,
        )
        token_account = parse_account_from_output(create_account.stdout + "\n" + create_account.stderr)
        if not token_account:
            raise SystemExit("Failed to parse token account address from spl-token output")
        subprocess.run(
            ["spl-token", "mint", mint, "1", token_account, "--url", RPC_ENDPOINT],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        print(f"Created mint: {mint} account: {token_account}")

    if mint:
        print(f"Using mint: {mint}")

    epoch_info = {
        "jsonrpc": "2.0",
        "id": 7,
        "method": "tools/call",
        "params": {
            "name": "get_epoch_info",
            "arguments": {
                "chain": "solana",
                "network": NETWORK,
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
                "network": NETWORK,
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
                "network": NETWORK,
                "endpoint": RPC_ENDPOINT,
            },
        },
    }
    print(send(supply, timeout_s=8))

    if mint:
        token_supply = {
            "jsonrpc": "2.0",
            "id": 10,
            "method": "tools/call",
            "params": {
                "name": "get_token_supply",
                "arguments": {
                    "chain": "solana",
                    "mint": mint,
                    "network": NETWORK,
                    "endpoint": RPC_ENDPOINT,
                },
            },
        }
        print(send(token_supply, timeout_s=12))

        token_largest = {
            "jsonrpc": "2.0",
            "id": 11,
            "method": "tools/call",
            "params": {
                "name": "get_token_largest_accounts",
                "arguments": {
                    "chain": "solana",
                    "mint": mint,
                    "network": NETWORK,
                    "endpoint": RPC_ENDPOINT,
                },
            },
        }
        print(send(token_largest, timeout_s=60))

    signatures = {
        "jsonrpc": "2.0",
        "id": 12,
        "method": "tools/call",
        "params": {
            "name": "get_signatures_for_address",
            "arguments": {
                "chain": "solana",
                "network": NETWORK,
                "endpoint": RPC_ENDPOINT,
                "address": address,
                "limit": 5,
            },
        },
    }
    print(send(signatures, timeout_s=12))

    slot_line = send({
        "jsonrpc": "2.0",
        "id": 13,
        "method": "tools/call",
        "params": {
            "name": "get_slot",
            "arguments": {
                "chain": "solana",
                "network": NETWORK,
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
            "id": 14,
            "method": "tools/call",
            "params": {
                "name": "get_block_time",
                "arguments": {
                    "chain": "solana",
                    "slot": slot_value,
                    "network": NETWORK,
                    "endpoint": RPC_ENDPOINT,
                },
            },
        }
        print(send(block_time, timeout_s=8))

    latest_blockhash = {
        "jsonrpc": "2.0",
        "id": 15,
        "method": "tools/call",
        "params": {
            "name": "get_latest_blockhash",
            "arguments": {
                "chain": "solana",
                "network": NETWORK,
                "endpoint": RPC_ENDPOINT,
            },
        },
    }
    print(send(latest_blockhash, timeout_s=8))

    min_rent = {
        "jsonrpc": "2.0",
        "id": 16,
        "method": "tools/call",
        "params": {
            "name": "get_minimum_balance_for_rent_exemption",
            "arguments": {
                "chain": "solana",
                "data_len": 165,
                "network": NETWORK,
                "endpoint": RPC_ENDPOINT,
            },
        },
    }
    print(send(min_rent, timeout_s=8))

    program_accounts = {
        "jsonrpc": "2.0",
        "id": 17,
        "method": "tools/call",
        "params": {
            "name": "get_program_accounts",
            "arguments": {
                "chain": "solana",
                "program_id": TOKEN_PROGRAM_ID,
                "network": NETWORK,
                "endpoint": RPC_ENDPOINT,
            },
        },
    }
    print(send(program_accounts, timeout_s=12))

    vote_accounts = {
        "jsonrpc": "2.0",
        "id": 18,
        "method": "tools/call",
        "params": {
            "name": "get_vote_accounts",
            "arguments": {
                "chain": "solana",
                "network": NETWORK,
                "endpoint": RPC_ENDPOINT,
            },
        },
    }
    print(send(vote_accounts, timeout_s=12))

    try:
        latest = rpc_call("getLatestBlockhash")
        blockhash = latest["result"]["value"]["blockhash"]
        msg_output = subprocess.run(
            [
                "solana",
                "transfer",
                "--sign-only",
                "--dump-transaction-message",
                "--url",
                RPC_ENDPOINT,
                "--blockhash",
                blockhash,
                recipient,
                "0.000001",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        message_b64 = parse_message_from_output(msg_output.stdout + "\n" + msg_output.stderr)
    except Exception:
        message_b64 = None

    if message_b64:
        fee_for_message = {
            "jsonrpc": "2.0",
            "id": 19,
            "method": "tools/call",
            "params": {
                "name": "get_fee_for_message",
                "arguments": {
                    "chain": "solana",
                    "message": message_b64,
                    "network": NETWORK,
                    "endpoint": RPC_ENDPOINT,
                },
            },
        }
        print(send(fee_for_message, timeout_s=8))

    if RUN_JUPITER:
        print(
            "Jupiter config:",
            {
                "quote_endpoint": JUPITER_API_ENDPOINT,
                "price_endpoint": JUPITER_PRICE_ENDPOINT,
                "price_mint": JUPITER_PRICE_MINT,
                "api_key_set": bool(JUPITER_API_KEY),
            },
        )
        jupiter_quote = {
            "jsonrpc": "2.0",
            "id": 20,
            "method": "tools/call",
            "params": {
                "name": "get_jupiter_quote",
                "arguments": {
                "chain": "solana",
                "input_mint": SOL_MINT,
                "output_mint": USDC_MINT,
                "amount": "1000000",
                "swap_mode": "ExactIn",
                **({"api_key": JUPITER_API_KEY} if JUPITER_API_KEY else {}),
                **({"endpoint": JUPITER_API_ENDPOINT} if JUPITER_API_ENDPOINT else {}),
                **({"insecure": True} if JUPITER_INSECURE else {}),
            },
            },
        }
        print(send(jupiter_quote, timeout_s=12))

        jupiter_price = {
            "jsonrpc": "2.0",
            "id": 21,
            "method": "tools/call",
            "params": {
                "name": "get_jupiter_price",
                "arguments": {
                "chain": "solana",
                "mint": JUPITER_PRICE_MINT,
                **({"api_key": JUPITER_API_KEY} if JUPITER_API_KEY else {}),
                **({"endpoint": JUPITER_PRICE_ENDPOINT} if JUPITER_PRICE_ENDPOINT else {}),
                **({"insecure": True} if JUPITER_INSECURE else {}),
            },
            },
        }
        print(send(jupiter_price, timeout_s=12))
finally:
    server.terminate()
