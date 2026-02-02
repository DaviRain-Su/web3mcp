//! Unified Wallet Status Tool
//!
//! Shows available wallet configurations and their status.
//! Helps users understand which wallets are configured and ready for use.

const std = @import("std");
const mcp = @import("mcp");
const wallet_provider = @import("../../core/wallet_provider.zig");
const wallet = @import("../../core/wallet.zig");
const privy_client = @import("../auth/privy/client.zig");

/// Get wallet configuration status
///
/// Parameters:
/// - chain: "solana" or "ethereum" (optional, shows all if not specified)
///
/// Returns JSON with available wallet types and their configuration status
pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const chain_filter = mcp.tools.getString(args, "chain");

    var response_buf: [2048]u8 = undefined;
    var response_len: usize = 0;

    // Start JSON object
    const header = "{\"wallets\":{";
    @memcpy(response_buf[response_len..][0..header.len], header);
    response_len += header.len;

    var first_chain = true;

    // Check Solana
    if (chain_filter == null or std.mem.eql(u8, chain_filter.?, "solana")) {
        if (!first_chain) {
            response_buf[response_len] = ',';
            response_len += 1;
        }
        first_chain = false;

        const solana_header = "\"solana\":{";
        @memcpy(response_buf[response_len..][0..solana_header.len], solana_header);
        response_len += solana_header.len;

        // Check local Solana wallet
        var local_available = false;
        var local_address: ?[]const u8 = null;
        if (wallet.loadSolanaKeypair(allocator, null)) |keypair| {
            local_available = true;
            var buf: [44]u8 = undefined;
            const addr = keypair.pubkey().toBase58(&buf);
            local_address = allocator.dupe(u8, addr) catch null;
        } else |_| {}
        defer if (local_address) |a| allocator.free(a);

        const local_str = if (local_available)
            std.fmt.bufPrint(
                response_buf[response_len..],
                "\"local\":{{\"available\":true,\"address\":\"{s}\"}}",
                .{local_address orelse "unknown"},
            )
        else
            std.fmt.bufPrint(
                response_buf[response_len..],
                "\"local\":{{\"available\":false,\"hint\":\"Set SOLANA_KEYPAIR env var or create ~/.config/solana/id.json\"}}",
                .{},
            );

        if (local_str) |s| {
            response_len += s.len;
        } else |_| {}

        // Check Privy
        response_buf[response_len] = ',';
        response_len += 1;

        const privy_configured = privy_client.isConfigured();
        const privy_str = if (privy_configured)
            std.fmt.bufPrint(
                response_buf[response_len..],
                "\"privy\":{{\"available\":true,\"hint\":\"Use privy_list_wallets to see available wallets\"}}",
                .{},
            )
        else
            std.fmt.bufPrint(
                response_buf[response_len..],
                "\"privy\":{{\"available\":false,\"hint\":\"Set PRIVY_APP_ID and PRIVY_APP_SECRET env vars\"}}",
                .{},
            );

        if (privy_str) |s| {
            response_len += s.len;
        } else |_| {}

        response_buf[response_len] = '}';
        response_len += 1;
    }

    // Check Ethereum
    if (chain_filter == null or std.mem.eql(u8, chain_filter.?, "ethereum") or std.mem.eql(u8, chain_filter.?, "evm")) {
        if (!first_chain) {
            response_buf[response_len] = ',';
            response_len += 1;
        }

        const evm_header = "\"ethereum\":{";
        @memcpy(response_buf[response_len..][0..evm_header.len], evm_header);
        response_len += evm_header.len;

        // Check local EVM wallet
        var local_evm_available = false;
        var local_evm_address: ?[]const u8 = null;
        if (wallet.loadEvmPrivateKey(allocator, null, null)) |pk| {
            if (wallet.deriveEvmAddress(pk)) |addr| {
                local_evm_available = true;
                var hex_buf: [42]u8 = undefined;
                hex_buf[0] = '0';
                hex_buf[1] = 'x';
                for (addr, 0..) |b, i| {
                    _ = std.fmt.bufPrint(hex_buf[2 + i * 2 ..][0..2], "{x:0>2}", .{b}) catch {};
                }
                local_evm_address = allocator.dupe(u8, &hex_buf) catch null;
            } else |_| {}
        } else |_| {}
        defer if (local_evm_address) |a| allocator.free(a);

        const local_evm_str = if (local_evm_available)
            std.fmt.bufPrint(
                response_buf[response_len..],
                "\"local\":{{\"available\":true,\"address\":\"{s}\"}}",
                .{local_evm_address orelse "unknown"},
            )
        else
            std.fmt.bufPrint(
                response_buf[response_len..],
                "\"local\":{{\"available\":false,\"hint\":\"Set EVM_PRIVATE_KEY env var or create ~/.config/evm/keyfile.json\"}}",
                .{},
            );

        if (local_evm_str) |s| {
            response_len += s.len;
        } else |_| {}

        // Check Privy for EVM
        response_buf[response_len] = ',';
        response_len += 1;

        const privy_configured = privy_client.isConfigured();
        const privy_evm_str = if (privy_configured)
            std.fmt.bufPrint(
                response_buf[response_len..],
                "\"privy\":{{\"available\":true,\"hint\":\"Use privy_list_wallets with chain_type=ethereum\"}}",
                .{},
            )
        else
            std.fmt.bufPrint(
                response_buf[response_len..],
                "\"privy\":{{\"available\":false,\"hint\":\"Set PRIVY_APP_ID and PRIVY_APP_SECRET env vars\"}}",
                .{},
            );

        if (privy_evm_str) |s| {
            response_len += s.len;
        } else |_| {}

        response_buf[response_len] = '}';
        response_len += 1;
    }

    // Close JSON
    const footer = "},\"usage\":{\"sign_and_send\":\"Use sign_and_send tool with wallet_type='local' or 'privy'\",\"privy_direct\":\"Use privy_sign_and_send_transaction for Privy wallets directly\"}}";
    @memcpy(response_buf[response_len..][0..footer.len], footer);
    response_len += footer.len;

    return mcp.tools.textResult(allocator, response_buf[0..response_len]) catch {
        return mcp.tools.ToolError.OutOfMemory;
    };
}
