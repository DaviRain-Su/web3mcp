//! Meteora Vault Get Info Tool

const std = @import("std");
const mcp = @import("mcp");
const constants = @import("../constants.zig");
const helpers = @import("../helpers.zig");

pub fn handle(allocator: std.mem.Allocator, args: ?std.json.Value) mcp.tools.ToolError!mcp.tools.ToolResult {
    const token_mint_str = mcp.tools.getString(args, "token_mint") orelse {
        return helpers.errorResult(allocator, "Missing required parameter: token_mint");
    };

    _ = helpers.parsePublicKey(token_mint_str) orelse {
        return helpers.errorResult(allocator, "Invalid token_mint");
    };

    const network = mcp.tools.getString(args, "network") orelse "mainnet";

    // Note: Vault PDA derivation requires on-chain lookup or known vault addresses
    // For now, return info about how to find vaults
    const Response = struct {
        token_mint: []const u8,
        program_id: []const u8,
        network: []const u8,
        status: []const u8,
        note: []const u8,
    };

    const response = Response{
        .token_mint = token_mint_str,
        .program_id = constants.PROGRAM_IDS.VAULT,
        .network = network,
        .status = "lookup_required",
        .note = "Meteora Vaults provide yield optimization. Use getProgramAccounts with VAULT program to find vaults for this token.",
    };

    return helpers.jsonResult(allocator, response);
}
