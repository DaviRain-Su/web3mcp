# NEAR Integration - Chain Abstraction via MPC

> **How NEAR Chain Signatures transforms web3mcp into a truly universal gateway**

## Table of Contents
- [The Vision](#the-vision)
- [NEAR as the Universal Account Gateway](#near-as-the-universal-account-gateway)
- [Why NEAR Chain Abstraction?](#why-near-chain-abstraction)
- [How Chain Signatures Work](#how-chain-signatures-work)
- [AI + MCP + NEAR Architecture](#ai--mcp--near-architecture)
- [Advantages for AI Agents](#advantages-for-ai-agents)
- [Technical Integration](#technical-integration)
- [Intent-Based Execution Flow](#intent-based-execution-flow)
- [Implementation Roadmap](#implementation-roadmap)
- [Use Cases Unlocked](#use-cases-unlocked)

---

## The Vision

**Problem**: AI agents operating across multiple blockchains face an impossible challenge:
- Must securely manage private keys for Bitcoin, Ethereum, Solana, etc.
- Each chain has different signature algorithms (ECDSA, Ed25519, Schnorr)
- Losing one key means losing access to assets on that chain
- Key management complexity grows exponentially with each new chain

**NEAR's Solution**: **One NEAR account = Universal access to all chains**

Through **Chain Signatures (Multi-Party Computation)**, a single NEAR account can:
- Sign Bitcoin transactions
- Sign Ethereum transactions
- Sign Solana transactions
- Sign on ANY blockchain that uses ECDSA or Ed25519

**web3mcp's Role**: Be the **Intent Layer** that sits on top of NEAR's Account Abstraction

```
[User/AI speaks natural language]
         ↓
[web3mcp translates to Intent]
         ↓
[NEAR executes via Chain Signatures]
         ↓
[All blockchains respond]
```

---

## NEAR as the Universal Account Gateway

### Traditional Multi-Chain Model (Broken)

```
User wants to operate on 5 chains:

┌─────────────┐
│   Bitcoin   │ ← Needs BTC private key (Schnorr)
└─────────────┘

┌─────────────┐
│  Ethereum   │ ← Needs ETH private key (ECDSA secp256k1)
└─────────────┘

┌─────────────┐
│   Solana    │ ← Needs SOL private key (Ed25519)
└─────────────┘

┌─────────────┐
│   Cosmos    │ ← Needs ATOM private key (secp256k1)
└─────────────┘

┌─────────────┐
│  Arbitrum   │ ← Needs ARB private key (ECDSA secp256k1)
└─────────────┘

Total: 5 private keys to manage (NIGHTMARE for AI)
```

### NEAR Chain Abstraction Model (Elegant)

```
User has ONE NEAR account:

┌─────────────────────────────────────────┐
│          NEAR Account (alice.near)      │
│                                         │
│  Holds: ONE NEAR private key (Ed25519) │
└─────────────────────────────────────────┘
                    ↓
          (MPC Network Signs)
                    ↓
    ┌───────────────┼───────────────┐
    ↓               ↓               ↓
┌─────────┐   ┌─────────┐   ┌─────────┐
│ Bitcoin │   │Ethereum │   │ Solana  │  ... (all chains)
└─────────┘   └─────────┘   └─────────┘

Result: AI only needs to manage ONE key
```

### Analogy

**Traditional approach**: Like needing a different passport for every country
**NEAR approach**: Like having a **"Universal Passport"** that's recognized everywhere

---

## Why NEAR Chain Abstraction?

### For AI Agents: Massive Simplification

#### Without NEAR

```zig
// AI Agent needs to manage keys for every chain
pub const AIAgent = struct {
    bitcoin_key: BitcoinPrivateKey,
    ethereum_key: EthereumPrivateKey,
    solana_key: SolanaPrivateKey,
    cosmos_key: CosmosPrivateKey,
    // ... 50 more chains ...

    // Different signing logic for each
    pub fn signBitcoin(self: *Self, tx: BitcoinTx) !Signature {
        return schnorr.sign(self.bitcoin_key, tx);
    }

    pub fn signEthereum(self: *Self, tx: EthTx) !Signature {
        return ecdsa.sign(self.ethereum_key, tx);
    }

    // Security nightmare: 50+ private keys to protect
};
```

#### With NEAR

```zig
// AI Agent only manages ONE NEAR account
pub const AIAgent = struct {
    near_account: NEARAccount,  // Single account

    // Universal signing via MPC
    pub fn signForChain(
        self: *Self,
        chain: ChainType,
        payload: []const u8,
    ) !Signature {
        // Request signature from NEAR MPC network
        return near.requestChainSignature(.{
            .account = self.near_account,
            .chain = chain,
            .payload = payload,
        });
    }

    // ONE key protects access to ALL chains
};
```

**Security benefit**:
- ONE key to backup
- ONE key to rotate
- ONE key to lose (vs. 50 keys to lose)

---

## How Chain Signatures Work

### Multi-Party Computation (MPC) Primer

**Traditional signing**:
```
Private Key + Message → Signature
```

If private key is stolen, all funds are lost.

**MPC signing**:
```
Key Shard 1 (Node A) ┐
Key Shard 2 (Node B) ├─→ Signature
Key Shard 3 (Node C) ┘
```

No single node has the full private key. They collectively compute the signature without ever combining shards.

### NEAR's Implementation

1. **Account Derivation**: For each chain, NEAR derives a unique address
   ```
   Bitcoin Address  = derive(NEAR account, "bitcoin", path)
   Ethereum Address = derive(NEAR account, "ethereum", path)
   Solana Address   = derive(NEAR account, "solana", path)
   ```

2. **Signature Request**: User calls NEAR smart contract
   ```rust
   // NEAR Smart Contract (Rust)
   pub fn sign_bitcoin_tx(
       &mut self,
       tx_data: Vec<u8>,
       path: String,
   ) -> Promise {
       // Request signature from MPC network
       mpc::sign(SignRequest {
           payload: tx_data,
           path,
           key_version: 0,
       })
   }
   ```

3. **MPC Nodes Execute**:
   - 8+ validator nodes participate
   - Each has a shard of the master key
   - They run secure multi-party computation protocol
   - Output: Valid signature for the target chain

4. **Signature Returned**: Contract receives signature, user broadcasts to target chain

### Security Guarantees

- **No Single Point of Failure**: Need to compromise 5+ out of 8 nodes
- **Trustless**: No node knows your full private key
- **Non-custodial**: You control via your NEAR account
- **Audited**: Protocol reviewed by Trail of Bits, Kudelski

---

## AI + MCP + NEAR Architecture

### System Diagram

```
┌──────────────────────────────────────────────────────────────┐
│                    User / AI Brain                           │
│         "Swap my USDC for BTC and send to my wallet"        │
└────────────────────────┬─────────────────────────────────────┘
                         │ Natural Language
                         ▼
┌──────────────────────────────────────────────────────────────┐
│                   web3mcp (Intent Layer)                     │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Intent Parser & Planner                               │ │
│  │  - Understands: "Swap USDC → BTC"                      │ │
│  │  - Plans: Get quote, approve, swap, bridge             │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  NEAR Provider (ChainProvider interface)               │ │
│  │  - Builds intent payload                               │ │
│  │  - Requests chain signatures                           │ │
│  └────────────────────────────────────────────────────────┘ │
└────────────────────────┬─────────────────────────────────────┘
                         │ Intent + Signature Request
                         ▼
┌──────────────────────────────────────────────────────────────┐
│              NEAR Protocol (Settlement Layer)                │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  Intent Smart Contract                                 │ │
│  │  - Receives intent: "Swap 1000 USDC → BTC"            │ │
│  │  - Publishes to Solvers                                │ │
│  └────────────────────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────────────────────┐ │
│  │  MPC Signature Service                                 │ │
│  │  - Signs Ethereum tx (approve USDC)                    │ │
│  │  - Signs Bitcoin tx (receive BTC)                      │ │
│  └────────────────────────────────────────────────────────┘ │
└────────────────────────┬─────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ↓                ↓                ↓
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│   Ethereum   │  │   Bitcoin    │  │   Solana     │
│  (Execute)   │  │  (Execute)   │  │  (Execute)   │
└──────────────┘  └──────────────┘  └──────────────┘
```

### Key Components

1. **Intent Layer (web3mcp)**:
   - Translates natural language to structured intent
   - Interfaces with NEAR via NEAR Provider
   - Manages user session and preferences

2. **Settlement Layer (NEAR)**:
   - Stores user's universal account
   - Manages MPC signature generation
   - Coordinates Solvers for intent fulfillment

3. **Execution Layer (All Chains)**:
   - Receives signed transactions
   - Executes on-chain actions
   - Reports outcomes back to NEAR

---

## Advantages for AI Agents

### 1. Single Account Management

**Before NEAR**:
```javascript
// AI needs wallets for every chain
const agent = {
  ethereumWallet: new Wallet(ETHEREUM_KEY),
  solanaWallet: new Wallet(SOLANA_KEY),
  bitcoinWallet: new Wallet(BITCOIN_KEY),
  // ... 20 more wallets
};

// Risk: If AI server is hacked, ALL keys are compromised
```

**With NEAR**:
```javascript
// AI only needs ONE NEAR account
const agent = {
  nearAccount: new Account(NEAR_KEY),
};

// Risk: Only ONE key to protect
// Benefit: Can add 2FA, hardware security, session keys to this ONE account
```

### 2. Intent-Based Execution (Not Transaction-Based)

**Traditional (Transaction-Based)**:
```
AI must know:
- Exact contract addresses
- Exact function signatures
- Exact parameter encoding
- Gas estimation
- Nonce management

Result: Fragile, complex, error-prone
```

**NEAR Intent-Based**:
```
AI only specifies:
- What they want to achieve (intent)
- Constraints (max price, deadline)

Solvers figure out HOW to execute

Result: Robust, simple, adaptable
```

### 3. Gas Abstraction

**Traditional**:
```
AI needs to:
- Hold native tokens (ETH, SOL, BTC) for gas
- Estimate gas prices
- Handle failed transactions (out of gas)
- Manage gas tokens across 50 chains
```

**NEAR**:
```
AI pays gas in:
- NEAR tokens (universal)
- OR let Solver pay gas (gasless transactions)

Solver handles all chain-specific gas logic
```

### 4. Instant Multi-Chain Support

**Traditional**:
```
New chain launches (e.g., Monad)

To add support:
- Study Monad docs (1 week)
- Implement Monad RPC client (2 weeks)
- Add Monad transaction builder (1 week)
- Test on Monad testnet (1 week)

Total: 5 weeks to add ONE chain
```

**NEAR**:
```
New chain launches (e.g., Monad)

If NEAR MPC adds Monad support:
- AI gets instant access (0 weeks)

If NEAR doesn't support yet:
- Only NEAR team needs to add it (not every AI developer)
```

---

## Technical Integration

### Step 1: Setup NEAR Account for AI Agent

```zig
// Initialize NEAR account
pub fn setupNearAccount(allocator: std.mem.Allocator) !NEARAccount {
    const account_id = "ai-agent.near";
    const private_key = try loadFromSecureStorage("NEAR_PRIVATE_KEY");

    return NEARAccount.init(allocator, .{
        .account_id = account_id,
        .private_key = private_key,
        .network = .mainnet,
    });
}
```

### Step 2: Derive Chain-Specific Addresses

```zig
// Derive addresses for all chains from ONE NEAR account
pub fn deriveAddresses(near_account: *NEARAccount) !AddressSet {
    return .{
        .ethereum = try near_account.deriveAddress(.ethereum, "m/44'/60'/0'/0/0"),
        .bitcoin = try near_account.deriveAddress(.bitcoin, "m/44'/0'/0'/0/0"),
        .solana = try near_account.deriveAddress(.solana, "m/44'/501'/0'/0'"),
        // ... all chains
    };
}
```

### Step 3: Request Chain Signature

```zig
// Sign transaction for any chain
pub fn signTransaction(
    near_account: *NEARAccount,
    chain: ChainType,
    tx_data: []const u8,
) !Signature {
    // Call NEAR MPC contract
    const payload = try std.json.stringifyAlloc(allocator, .{
        .transaction = tx_data,
        .path = getDerivationPath(chain),
        .key_version = 0,
    }, .{});

    const result = try near_account.callContract(.{
        .contract_id = "v1.signer.near",
        .method_name = "sign",
        .args = payload,
        .gas = 300_000_000_000_000,  // 300 TGas
        .deposit = 0,
    });

    return parseSignature(result);
}
```

### Step 4: Execute Cross-Chain Transaction

```zig
// Complete flow: Intent → Signature → Execution
pub fn executeIntent(
    allocator: std.mem.Allocator,
    intent: Intent,
) !TransactionResult {
    // 1. Build transaction for target chain
    const tx = switch (intent.target_chain) {
        .ethereum => try buildEthereumTx(allocator, intent),
        .bitcoin => try buildBitcoinTx(allocator, intent),
        .solana => try buildSolanaTx(allocator, intent),
        else => return error.UnsupportedChain,
    };

    // 2. Request signature from NEAR MPC
    const signature = try signTransaction(
        near_account,
        intent.target_chain,
        tx.serialize(),
    );

    // 3. Attach signature to transaction
    tx.setSignature(signature);

    // 4. Broadcast to target chain
    const tx_hash = try broadcastToChain(intent.target_chain, tx);

    // 5. Monitor and return result
    return waitForConfirmation(intent.target_chain, tx_hash);
}
```

---

## Intent-Based Execution Flow

### Example: "Swap 1000 USDC to BTC"

#### Step 1: User Intent (Natural Language)

```
User → AI: "I want to swap 1000 USDC for Bitcoin"
```

#### Step 2: AI Parses Intent (via web3mcp)

```zig
const intent = Intent{
    .action = .swap,
    .from_asset = .{ .chain = .ethereum, .token = "USDC", .amount = 1000 },
    .to_asset = .{ .chain = .bitcoin, .token = "BTC" },
    .constraints = .{
        .max_slippage = 0.01,  // 1%
        .deadline = now() + 600,  // 10 minutes
    },
};
```

#### Step 3: web3mcp Submits Intent to NEAR

```zig
// Submit intent to NEAR contract
const intent_id = try near_account.callContract(.{
    .contract_id = "intents.near",
    .method_name = "submit_intent",
    .args = try std.json.stringifyAlloc(allocator, intent, .{}),
    .deposit = attachedNEAR(0.1),  // Solver incentive
});
```

#### Step 4: NEAR Publishes Intent, Solvers Compete

```rust
// NEAR Smart Contract (Rust)
#[near_bindgen]
impl IntentContract {
    pub fn submit_intent(&mut self, intent: Intent) -> IntentId {
        let intent_id = self.next_intent_id;
        self.intents.insert(intent_id, intent);

        // Emit event for Solvers to see
        env::log_str(&format!("NEW_INTENT: {}", intent_id));

        intent_id
    }
}
```

Off-chain, Solvers see the intent and compete:
```
Solver A: "I can do this for 0.0245 BTC (1inch → Wormhole)"
Solver B: "I can do this for 0.0248 BTC (Uniswap → Native bridge)"
Solver C: "I can do this for 0.0250 BTC (Curve → Li.Fi)"
```

Best Solver (C) is selected.

#### Step 5: NEAR Signs Required Transactions

Solver C needs:
1. Ethereum tx: `approve(USDC, Curve)`
2. Ethereum tx: `swap(USDC, wrapped BTC, Curve)`
3. Bitcoin tx: `receive(BTC, user_bitcoin_address)`

NEAR MPC signs all three:

```zig
// Sign Ethereum approval
const eth_approval_sig = try signTransaction(
    near_account,
    .ethereum,
    buildApprovalTx(USDC, Curve, 1000),
);

// Sign Ethereum swap
const eth_swap_sig = try signTransaction(
    near_account,
    .ethereum,
    buildSwapTx(Curve, USDC, 1000),
);

// Bitcoin address to receive
const btc_address = try near_account.deriveAddress(.bitcoin, "m/44'/0'/0'/0/0");
```

#### Step 6: Solver Executes

```
1. Broadcasts eth_approval_sig to Ethereum
   ✅ Confirmed

2. Broadcasts eth_swap_sig to Ethereum
   ✅ Confirmed → Receives 0.0250 wrapped BTC

3. Unwraps to native BTC

4. Sends BTC to user's btc_address
   ✅ Confirmed
```

#### Step 7: Settlement & Confirmation

```zig
// Solver reports completion to NEAR
solver.reportCompletion(.{
    .intent_id = intent_id,
    .proof = btc_tx_hash,
});

// NEAR verifies via Bitcoin light client
if (verify_btc_tx(btc_tx_hash, expected_amount, user_address)) {
    // Release payment to Solver
    transfer(solver, intent.deposit);

    // Notify user
    emit_event("INTENT_FULFILLED", intent_id);
}
```

---

## Implementation Roadmap

### Phase 1: NEAR Account Integration (4 weeks)

**Goals**:
- AI can create and manage NEAR accounts
- Derive addresses for Ethereum and Bitcoin

**Tasks**:
- [ ] Implement NEAR RPC client in Zig
- [ ] Add NEAR account creation flow
- [ ] Implement address derivation (Ethereum, Bitcoin)
- [ ] Test signature requests on NEAR testnet

**Deliverable**: web3mcp can sign Ethereum transactions via NEAR MPC

### Phase 2: Intent Contract (4 weeks)

**Goals**:
- Deploy intent settlement contract on NEAR
- Support basic swap intents

**Tasks**:
- [ ] Write NEAR smart contract (Rust) for intent matching
- [ ] Implement Solver registration system
- [ ] Add intent submission API to web3mcp
- [ ] Build simple Solver bot (for testing)

**Deliverable**: End-to-end flow works for ETH → BTC swaps

### Phase 3: Multi-Chain Expansion (6 weeks)

**Goals**:
- Support Solana, Arbitrum, Base, Optimism

**Tasks**:
- [ ] Add derivation paths for new chains
- [ ] Implement chain-specific transaction builders
- [ ] Test MPC signatures for each chain
- [ ] Add multi-chain intents (e.g., "Best yield across 5 chains")

**Deliverable**: Universal gateway supporting 6+ chains via ONE NEAR account

### Phase 4: Advanced Features (6 weeks)

**Goals**:
- Session keys, gasless transactions, Solver marketplace

**Tasks**:
- [ ] Implement session keys (limited-scope signing)
- [ ] Add gasless transaction support (Solver pays gas)
- [ ] Build Solver reputation system
- [ ] Create Solver marketplace UI

**Deliverable**: Production-ready intent settlement layer

---

## Use Cases Unlocked

### 1. True One-Click Cross-Chain Swaps

```
User: "Swap my Ethereum USDC for Solana SOL"

Traditional:
- Bridge USDC to Solana (Wormhole UI)
- Wait 10 minutes
- Swap USDC to SOL (Jupiter UI)
- Total: 2 UIs, 15 minutes, 2 approvals

With NEAR + web3mcp:
- AI submits intent to NEAR
- Solver handles bridging + swapping
- Total: 1 command, 3 minutes, 1 approval
```

### 2. Unified Portfolio Management

```
User: "Show me all my assets across all chains"

AI (via web3mcp + NEAR):
- Derives your addresses for 20 chains from ONE NEAR account
- Queries balances on all chains in parallel
- Presents unified view

Ethereum: 2.5 ETH, 5000 USDC
Bitcoin:  0.1 BTC
Solana:   100 SOL, 1000 USDC
...
Total Value: $125,340
```

### 3. Automated Cross-Chain Yield Farming

```
User: "Put my stablecoins wherever the yield is highest,
       rebalance daily"

AI (via web3mcp + NEAR):
- Checks yields on Aave (Ethereum), Kamino (Solana), Morpho (Base)
- Submits intent: "Deposit to highest yield"
- Solver executes deposits across chains
- Daily: AI checks if better opportunities exist
- If yes: Submits rebalance intent automatically
```

No manual bridging, swapping, or approvals needed.

### 4. Social Recovery for AI Agents

```
Problem: AI's NEAR key is compromised

Solution:
- NEAR account has social recovery configured
- 3-of-5 multisig (e.g., user's hardware wallet + 2 trusted friends)
- Rotate compromised key without losing access to ANY chain

Result: Much safer than managing 50 separate keys
```

---

## Comparison: With vs Without NEAR

| Aspect | Without NEAR | With NEAR |
|--------|--------------|-----------|
| **Keys to Manage** | 50+ private keys | 1 NEAR account |
| **New Chain Support** | Manual integration (weeks) | Automatic (if NEAR supports) |
| **Transaction Model** | Build exact transactions | Specify intent (goal) |
| **Gas Payment** | Need native token on each chain | Pay in NEAR or gasless |
| **Cross-Chain Ops** | Manual coordination | Solver handles |
| **Security Risk** | Lose one key = lose one chain | Lose NEAR key = recoverable |
| **AI Complexity** | Very high | Very low |

---

## Conclusion

### NEAR is the Missing Piece

**Without NEAR**: web3mcp is a powerful multi-chain tool, but still requires managing many keys

**With NEAR**: web3mcp becomes a **truly universal gateway** where:
- AI manages ONE account
- Users speak ONE language (intent)
- All chains are accessed seamlessly

### Next Steps

1. **Prototype**: Build proof-of-concept NEAR integration (Ethereum + Bitcoin)
2. **Partner**: Reach out to NEAR Foundation for grant/collaboration
3. **Expand**: Add more chains as NEAR MPC supports them
4. **Scale**: Launch intent marketplace and Solver network

**This is the endgame architecture for AI x Web3.**

---

## Resources

- [NEAR Chain Signatures Docs](https://docs.near.org/concepts/abstraction/chain-signatures)
- [NEAR MPC GitHub](https://github.com/near/mpc-recovery)
- [Intent-Based Architectures (Research)](https://www.paradigm.xyz/2023/06/intents)
- [web3mcp Architecture](./ARCHITECTURE.md)
- [web3mcp Use Cases](./USE_CASES.md)
- [web3mcp Business Model](./BUSINESS_MODEL.md)
