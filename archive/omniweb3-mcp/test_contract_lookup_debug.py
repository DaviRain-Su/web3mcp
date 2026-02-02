#!/usr/bin/env python3
"""Test contract name resolution with debug output"""
import json
import subprocess
import time
import os

def main():
    print(f"Current directory: {os.getcwd()}")
    print(f"Checking files:")
    print(f"  abi_registry/contracts.json exists: {os.path.exists('abi_registry/contracts.json')}")
    print(f"  abi_registry/bsc/pancake_testnet.json exists: {os.path.exists('abi_registry/bsc/pancake_testnet.json')}")

    # Read contracts.json to verify pancake_testnet is there
    with open('abi_registry/contracts.json') as f:
        contracts = json.load(f)
        pancake_testnet = [c for c in contracts['evm_contracts'] if c['name'] == 'pancake_testnet']
        print(f"\nFound pancake_testnet in contracts.json: {len(pancake_testnet) > 0}")
        if pancake_testnet:
            print(f"  Entry: {json.dumps(pancake_testnet[0], indent=2)}")

    print("\nStarting MCP server...")
    proc = subprocess.Popen(
        ['./zig-out/bin/omniweb3-mcp'],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
        cwd=os.getcwd()  # Explicitly set working directory
    )

    try:
        time.sleep(1)  # Let it start
        # Read stderr to see any error messages
        import select
        if select.select([proc.stderr], [], [], 0)[0]:
            stderr_output = proc.stderr.read()
            if stderr_output:
                print(f"\nServer stderr:\n{stderr_output}")
    finally:
        proc.terminate()
        proc.wait(timeout=5)

if __name__ == '__main__':
    main()
