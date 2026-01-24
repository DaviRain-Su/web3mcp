const std = @import("std");
const mcp = @import("mcp");
const wallet_provider = @import("../../../../core/wallet_provider.zig");

pub fn resolveUserPublicKey(allocator: std.mem.Allocator, args: ?std.json.Value) ![]const u8 {
    if (mcp.tools.getString(args, "user_public_key")) |user| {
        return allocator.dupe(u8, user);
    }

    const wallet_id = mcp.tools.getString(args, "wallet_id");
    const keypair_path = mcp.tools.getString(args, "keypair_path");
    const network = mcp.tools.getString(args, "network") orelse "mainnet";

    const wallet_type = if (mcp.tools.getString(args, "wallet_type")) |wallet_type_str| blk: {
        break :blk wallet_provider.WalletType.fromString(wallet_type_str) orelse {
            return error.InvalidWalletType;
        };
    } else if (wallet_id != null) blk: {
        break :blk wallet_provider.WalletType.privy;
    } else {
        return error.MissingUserPublicKey;
    };

    if (wallet_type == .privy) {
        if (wallet_id == null) return error.MissingWalletId;
        if (!wallet_provider.isPrivyConfigured()) return error.PrivyNotConfigured;
    }

    const config = wallet_provider.WalletConfig{
        .wallet_type = wallet_type,
        .chain = .solana,
        .keypair_path = keypair_path,
        .wallet_id = wallet_id,
        .network = network,
    };

    return wallet_provider.getWalletAddress(allocator, config);
}

pub fn resolveOptionalUserPublicKey(allocator: std.mem.Allocator, args: ?std.json.Value) !?[]const u8 {
    if (mcp.tools.getString(args, "user_public_key")) |user| {
        const duped = try allocator.dupe(u8, user);
        return @as([]const u8, duped);
    }

    if (mcp.tools.getString(args, "wallet_type") == null and mcp.tools.getString(args, "wallet_id") == null) {
        return null;
    }

    return try resolveUserPublicKey(allocator, args);
}

pub fn userResolveErrorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.MissingUserPublicKey => "Missing required parameter: user_public_key (or wallet_type/wallet_id)",
        error.InvalidWalletType => "Invalid wallet_type. Use 'local' or 'privy'",
        error.MissingWalletId => "wallet_id is required when wallet_type='privy'",
        error.PrivyNotConfigured => "Privy not configured. Set PRIVY_APP_ID and PRIVY_APP_SECRET env vars.",
        else => "Failed to resolve user wallet address",
    };
}
