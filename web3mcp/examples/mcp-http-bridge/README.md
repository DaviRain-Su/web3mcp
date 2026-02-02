# MCP HTTP Bridge

This is a small HTTP bridge that forwards `POST /mcp` calls to the local MCP binary over stdio (built from `web3mcp/`; binary name may be `sui-mcp`).

## Quick Start

```bash
npm install
npm run start
```

## Env Vars

```
MCP_COMMAND=../../target/release/sui-mcp
MCP_ARGS=
SUI_RPC_URL=https://fullnode.mainnet.sui.io:443
PORT=3000
```

## Request Format

```json
{
  "tool": "execute_zklogin_transaction",
  "params": {
    "tx_bytes": "...",
    "zk_login_inputs_json": "...",
    "address_seed": "...",
    "max_epoch": 12345,
    "user_signature": "..."
  }
}
```
