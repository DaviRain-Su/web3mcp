const std = @import("std");
const solana_sdk = @import("solana_sdk");
const zabi = @import("zabi");
const evm_helpers = @import("evm_helpers.zig");

const Keypair = solana_sdk.Keypair;
const Hash = zabi.types.ethereum.Hash;
const Address = zabi.types.ethereum.Address;
const Signer = zabi.crypto.Signer;

// C interop for getenv
const c = @cImport({
    @cInclude("stdlib.h");
});

pub fn loadSolanaKeypair(
    allocator: std.mem.Allocator,
    keypair_path_override: ?[]const u8,
) !Keypair {
    const keypair_path = if (keypair_path_override) |p|
        try allocator.dupe(u8, p)
    else
        try getDefaultSolanaKeypairPath(allocator);
    defer allocator.free(keypair_path);

    return loadKeypairFromFile(allocator, keypair_path);
}

pub fn loadEvmPrivateKey(
    allocator: std.mem.Allocator,
    private_key_override: ?[]const u8,
    keypair_path_override: ?[]const u8,
) !Hash {
    if (private_key_override) |value| {
        return evm_helpers.parsePrivateKey(value);
    }

    if (c.getenv("EVM_PRIVATE_KEY")) |env_key| {
        const key = std.mem.span(env_key);
        return evm_helpers.parsePrivateKey(key);
    }

    const keypair_path = if (keypair_path_override) |p|
        try allocator.dupe(u8, p)
    else
        try getDefaultEvmKeypairPath(allocator);
    defer allocator.free(keypair_path);

    return loadEvmPrivateKeyFromFile(allocator, keypair_path);
}

pub fn deriveEvmAddress(private_key: Hash) !Address {
    const signer = try Signer.init(private_key);
    return signer.address_bytes;
}

fn getDefaultSolanaKeypairPath(allocator: std.mem.Allocator) ![]const u8 {
    if (c.getenv("SOLANA_KEYPAIR")) |env_path_c| {
        const env_path = std.mem.span(env_path_c);
        return allocator.dupe(u8, env_path);
    }

    const home_c = c.getenv("HOME") orelse return error.HomeNotFound;
    const home = std.mem.span(home_c);
    return std.fmt.allocPrint(allocator, "{s}/.config/solana/id.json", .{home});
}

fn getDefaultEvmKeypairPath(allocator: std.mem.Allocator) ![]const u8 {
    const home_c = c.getenv("HOME") orelse return error.HomeNotFound;
    const home = std.mem.span(home_c);
    return std.fmt.allocPrint(allocator, "{s}/.config/evm/keyfile.json", .{home});
}

fn loadKeypairFromFile(allocator: std.mem.Allocator, path: []const u8) !Keypair {
    const content = try readFile(allocator, path, 4096);
    defer allocator.free(content);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch {
        return error.KeypairParseError;
    };
    defer parsed.deinit();

    if (parsed.value != .array) {
        return error.KeypairInvalidFormat;
    }

    const arr = parsed.value.array;
    if (arr.items.len != 64) {
        return error.KeypairInvalidLength;
    }

    var keypair_bytes: [64]u8 = undefined;
    for (arr.items, 0..) |item, i| {
        if (item != .integer) {
            return error.KeypairInvalidFormat;
        }
        keypair_bytes[i] = @intCast(item.integer);
    }

    return Keypair.fromBytes(&keypair_bytes) catch {
        return error.KeypairInvalid;
    };
}

fn loadEvmPrivateKeyFromFile(allocator: std.mem.Allocator, path: []const u8) !Hash {
    const content = try readFile(allocator, path, 4096);
    defer allocator.free(content);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch {
        return error.KeypairParseError;
    };
    defer parsed.deinit();

    const key_str = switch (parsed.value) {
        .string => |value| value,
        .object => |obj| blk: {
            if (obj.get("private_key")) |entry| {
                if (entry == .string) break :blk entry.string;
            }
            return error.KeypairInvalidFormat;
        },
        else => return error.KeypairInvalidFormat,
    };

    return evm_helpers.parsePrivateKey(key_str);
}

fn readFile(allocator: std.mem.Allocator, path: []const u8, max_len: usize) ![]u8 {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const flags: std.os.linux.O = .{ .ACCMODE = .RDONLY };
    const fd = std.os.linux.open(path_z.ptr, flags, 0);
    if (fd < 0) return error.KeypairFileNotFound;
    defer _ = std.os.linux.close(@intCast(fd));

    const buffer = try allocator.alloc(u8, max_len);
    errdefer allocator.free(buffer);

    const bytes_read = std.os.linux.read(@intCast(fd), buffer[0..].ptr, buffer.len);
    if (bytes_read < 0) return error.KeypairReadFailed;

    const trimmed = try allocator.realloc(buffer, @intCast(bytes_read));
    return trimmed;
}
