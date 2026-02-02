const std = @import("std");
const mcp = @import("mcp");
const wallet_provider = @import("../../../../core/wallet_provider.zig");

pub fn resolveAddress(allocator: std.mem.Allocator, args: ?std.json.Value, key_name: []const u8) ![]const u8 {
    if (mcp.tools.getString(args, key_name)) |value| {
        return allocator.dupe(u8, value);
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
        return error.MissingUser;
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

pub fn resolveOptionalAddress(allocator: std.mem.Allocator, args: ?std.json.Value, key_name: []const u8) !?[]const u8 {
    if (mcp.tools.getString(args, key_name)) |value| {
        const duped = try allocator.dupe(u8, value);
        return @as([]const u8, duped);
    }

    if (mcp.tools.getString(args, "wallet_type") == null and mcp.tools.getString(args, "wallet_id") == null) {
        return null;
    }

    return try resolveAddress(allocator, args, key_name);
}

pub fn signAndSendIfRequested(allocator: std.mem.Allocator, args: ?std.json.Value, unsigned_tx: []const u8) !?[]const u8 {
    const wallet_id = mcp.tools.getString(args, "wallet_id");
    const keypair_path = mcp.tools.getString(args, "keypair_path");
    const network = mcp.tools.getString(args, "network") orelse "mainnet";
    const sponsor = mcp.tools.getBoolean(args, "sponsor") orelse false;

    const wallet_type = if (mcp.tools.getString(args, "wallet_type")) |wallet_type_str| blk: {
        break :blk wallet_provider.WalletType.fromString(wallet_type_str) orelse return error.InvalidWalletType;
    } else if (wallet_id != null) blk: {
        break :blk wallet_provider.WalletType.privy;
    } else {
        return null;
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
        .sponsor = sponsor,
    };

    const result = wallet_provider.signAndSendSolanaTransaction(allocator, config, unsigned_tx) catch |err| {
        return err;
    };

    return result.signature;
}

pub fn signIfRequested(allocator: std.mem.Allocator, args: ?std.json.Value, unsigned_tx: []const u8) !?[]const u8 {
    const wallet_id = mcp.tools.getString(args, "wallet_id");
    const keypair_path = mcp.tools.getString(args, "keypair_path");
    const network = mcp.tools.getString(args, "network") orelse "mainnet";

    const wallet_type = if (mcp.tools.getString(args, "wallet_type")) |wallet_type_str| blk: {
        break :blk wallet_provider.WalletType.fromString(wallet_type_str) orelse return error.InvalidWalletType;
    } else if (wallet_id != null) blk: {
        break :blk wallet_provider.WalletType.privy;
    } else {
        return null;
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

    const result = wallet_provider.signSolanaTransaction(allocator, config, unsigned_tx) catch |err| {
        return err;
    };

    return result.signed_transaction;
}

pub fn extractTransactionBase64(value: std.json.Value) ?[]const u8 {
    if (value != .object) return null;

    const obj = value.object;
    if (obj.get("swapTransaction")) |tx| if (tx == .string) return tx.string;
    if (obj.get("transaction")) |tx| {
        switch (tx) {
            .string => return tx.string,
            .object => {
                if (tx.object.get("transaction")) |inner| if (inner == .string) return inner.string;
                if (tx.object.get("serializedTransaction")) |inner| if (inner == .string) return inner.string;
            },
            else => {},
        }
    }
    if (obj.get("serializedTransaction")) |tx| if (tx == .string) return tx.string;
    if (obj.get("data")) |data| {
        if (data == .object) {
            if (data.object.get("transaction")) |tx| if (tx == .string) return tx.string;
            if (data.object.get("serializedTransaction")) |tx| if (tx == .string) return tx.string;
        }
    }
    return null;
}

pub fn userResolveErrorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.MissingUser => "Missing required parameter: user (or wallet_type/wallet_id)",
        error.InvalidWalletType => "Invalid wallet_type. Use 'local' or 'privy'",
        error.MissingWalletId => "wallet_id is required when wallet_type='privy'",
        error.PrivyNotConfigured => "Privy not configured. Set PRIVY_APP_ID and PRIVY_APP_SECRET env vars.",
        else => "Failed to resolve user wallet address",
    };
}

pub fn signErrorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.InvalidWalletType => "Invalid wallet_type. Use 'local' or 'privy'",
        error.MissingWalletId => "wallet_id is required when wallet_type='privy'",
        error.PrivyNotConfigured => "Privy not configured. Set PRIVY_APP_ID and PRIVY_APP_SECRET env vars.",
        error.LocalSignAndSendNotImplemented => "Local wallet sign+send not yet implemented. Use wallet_type='privy'.",
        error.LocalSigningNotImplemented => "Local wallet signing not yet implemented. Use wallet_type='privy'.",
        else => "Failed to sign transaction",
    };
}
