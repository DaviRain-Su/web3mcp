# zkLogin Google Connection (Example)

This is a minimal Vite app that mirrors a “Connect Google” flow and helps you assemble the zkLogin fields required by the MCP tools.

## Quick Start

```bash
npm install
npm run dev
```

Then open `http://localhost:5173`.

### All-in-one (UI + MCP bridge + MCP server)

```bash
npm run dev:all
```

This starts the Vite UI and a `/mcp` endpoint on the same port.

Use environment variables when launching if your MCP binary is not at the default path:

```bash
MCP_COMMAND=../../target/release/web3mcp SUI_RPC_URL=https://fullnode.mainnet.sui.io:443 npm run dev:all
```

## Env Vars

Copy `.env.example` to `.env` and fill in your Google client ID.

```
VITE_GOOGLE_CLIENT_ID=
VITE_PROVER_URL=http://localhost:8080/v1
VITE_MAX_EPOCH=
VITE_NETWORK=mainnet
VITE_RPC_URL=https://fullnode.mainnet.sui.io:443
VITE_BRIDGE_URL=/mcp
VITE_SALT_URL=https://salt.api.mystenlabs.com/get_salt
```

## Notes

- The app initializes Google Identity Services and captures `id_token`.
- The app can generate an ephemeral keypair, nonce, and `user_signature` using the Sui JS SDK.
- The app can build `tx_bytes` for a simple SUI transfer (sender + recipient + amount).
- Amounts support up to 9 decimal places (SUI precision).
- The prover payload is editable because different SDKs/wallets may require additional fields.
- The MCP payload is assembled as JSON for `execute_zklogin_transaction`.
- For mainnet, you need access to a zkLogin prover (Enoki) or run a local prover.

For a local prover, see `examples/zklogin-prover-local`.

### Testnet

You can switch the app to testnet by setting:

```
VITE_NETWORK=testnet
VITE_RPC_URL=https://fullnode.testnet.sui.io:443
```

Use the testnet zkey when running the local prover:

```bash
wget -O - https://raw.githubusercontent.com/sui-foundation/zklogin-ceremony-contributions/main/download-test-zkey.sh | bash
```

## HTTP Bridge

If you want the “Call MCP” button to work, run the local HTTP bridge:

(Skip this if you are using `npm run dev:all`.)

```bash
cd ../mcp-http-bridge
npm install
npm run start
```
