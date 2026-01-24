const std = @import("std");
const mcp = @import("mcp");
const zabi = @import("zabi");
const evm_helpers = @import("../core/evm_helpers.zig");
const evm_runtime = @import("../core/evm_runtime.zig");
const chain = @import("../core/chain.zig");
const wallet = @import("../core/wallet.zig");

const TransactionTypes = zabi.types.transactions.TransactionTypes;
const Wei = zabi.types.ethereum.Wei;
const Address = zabi.types.ethereum.Address;

/// Transfer native token on EVM chains.
///
/// Parameters:
/// - to_address: Hex address (required)
/// - amount: Amount in wei (required, string or integer)
/// - chain: "ethereum" | "avalanche" | "bnb" (optional, default: ethereum)
/// - network: "mainnet" | "sepolia" | "goerli" | "fuji" | "testnet" (optional, default: mainnet)
/// - endpoint: Override RPC endpoint (optional)
/// - private_key: Private key hex (optional)
/// - keypair_path: Path to keyfile.json (optional)
/// - tx_type: "eip1559" | "legacy" (optional, default: eip1559)
/// - confirmations: Wait for receipt confirmations (optional, default: 0)
///
/// Returns JSON with transaction hash and optional receipt info
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const to_address_str = mcp.tools.getString(args, "to_address") orelse {
        return mcp.tools.errorResult(allocator, "Missing required parameter: to_address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const amount_str = mcp.tools.getString(args, "amount");
    const amount_int = mcp.tools.getInteger(args, "amount");
    if (amount_str == null and amount_int == null) {
        return mcp.tools.errorResult(allocator, "Missing required parameter: amount") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    }

    const chain_name = mcp.tools.getString(args, "chain") orelse "ethereum";
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const endpoint_override = mcp.tools.getString(args, "endpoint");
    const private_key_override = mcp.tools.getString(args, "private_key");
    const keypair_path = mcp.tools.getString(args, "keypair_path");
    const tx_type_str = mcp.tools.getString(args, "tx_type") orelse "eip1559";
    const confirmations_raw = mcp.tools.getInteger(args, "confirmations") orelse 0;
    const confirmations = if (confirmations_raw < 0) 0 else confirmations_raw;

    const to_address = evm_helpers.parseAddress(to_address_str) catch {
        return mcp.tools.errorResult(allocator, "Invalid EVM address") catch {
            return mcp.tools.ToolError.InvalidArguments;
        };
    };

    const amount_wei = if (amount_str) |value| blk: {
        break :blk evm_helpers.parseWeiAmount(value) catch {
            return mcp.tools.errorResult(allocator, "Invalid amount (expected integer wei)") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        };
    } else blk: {
        const value = amount_int.?;
        if (value <= 0) {
            return mcp.tools.errorResult(allocator, "Amount must be positive") catch {
                return mcp.tools.ToolError.InvalidArguments;
            };
        }
        break :blk @as(Wei, @intCast(value));
    };

    var adapter = chain.initEvmAdapter(allocator, evm_runtime.io(), chain_name, network, endpoint_override) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to init EVM adapter: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };
    defer adapter.deinit();

    const private_key = wallet.loadEvmPrivateKey(allocator, private_key_override, keypair_path) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to resolve private key: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    const from_address = wallet.deriveEvmAddress(private_key) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to derive EVM address: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    const use_legacy = std.ascii.eqlIgnoreCase(tx_type_str, "legacy");
    const tx_type = if (use_legacy) TransactionTypes.legacy else TransactionTypes.london;

    const confirmations_u8: u8 = if (confirmations > std.math.maxInt(u8))
        std.math.maxInt(u8)
    else
        @intCast(confirmations);

    const transfer_result = adapter.sendTransfer(
        private_key,
        from_address,
        to_address,
        amount_wei,
        tx_type,
        confirmations_u8,
    ) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "Failed to send transaction: {s}", .{@errorName(err)}) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
        return mcp.tools.errorResult(allocator, msg) catch {
            return mcp.tools.ToolError.OutOfMemory;
        };
    };

    const hash_hex = std.fmt.bytesToHex(transfer_result.tx_hash, .lower);

    const receipt_info = if (transfer_result.receipt) |receipt| blk: {
        const status = receiptStatus(receipt);
        const block_number = receiptBlockNumber(receipt);

        const status_str = if (status) |value| if (value) "true" else "false" else "null";
        const block_str = if (block_number) |value|
            std.fmt.allocPrint(allocator, "{d}", .{value}) catch {
                return mcp.tools.ToolError.OutOfMemory;
            }
        else
            try allocator.dupe(u8, "null");
        defer allocator.free(block_str);

        break :blk try std.fmt.allocPrint(
            allocator,
            ",\"receipt_status\":{s},\"receipt_block\":{s}",
            .{ status_str, block_str },
        );
    } else blk: {
        break :blk try allocator.dupe(u8, "");
    };
    defer allocator.free(receipt_info);

    const amount_wei_str = evm_helpers.formatU256(allocator, amount_wei) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
    defer allocator.free(amount_wei_str);

    const response = std.fmt.allocPrint(
        allocator,
        "{{\"tx_hash\":\"0x{s}\",\"chain\":\"{s}\",\"network\":\"{s}\",\"to_address\":\"{s}\",\"amount_wei\":\"{s}\",\"tx_type\":\"{s}\",\"endpoint\":\"{s}\"{s}}}",
        .{ hash_hex, chain_name, network, to_address_str, amount_wei_str, tx_type_str, adapter.endpoint, receipt_info },
    ) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };

    return mcp.tools.textResult(allocator, response) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}

fn receiptStatus(receipt: zabi.types.transactions.TransactionReceipt) ?bool {
    return switch (receipt) {
        .legacy => |value| value.status,
        .cancun => |value| value.status,
        .op_receipt => |value| value.status,
        .arbitrum_receipt => |value| value.status,
        .deposit_receipt => |value| value.status,
    };
}

fn receiptBlockNumber(receipt: zabi.types.transactions.TransactionReceipt) ?u64 {
    return switch (receipt) {
        .legacy => |value| value.blockNumber,
        .cancun => |value| value.blockNumber,
        .op_receipt => |value| value.blockNumber,
        .arbitrum_receipt => |value| value.blockNumber,
        .deposit_receipt => |value| value.blockNumber,
    };
}
