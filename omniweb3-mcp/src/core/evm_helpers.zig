const std = @import("std");
const zabi = @import("zabi");

const Network = zabi.clients.network;
const NetworkConfig = Network.NetworkConfig;
const Chains = zabi.types.ethereum.PublicChains;
const Address = zabi.types.ethereum.Address;
const Hash = zabi.types.ethereum.Hash;
const Wei = zabi.types.ethereum.Wei;
const utils = zabi.utils.utils;

// C interop for getenv
const c = @cImport({
    @cInclude("stdlib.h");
});

pub const NetworkConfigResult = struct {
    config: NetworkConfig,
    endpoint: []const u8,
};

pub fn resolveNetworkConfig(
    allocator: std.mem.Allocator,
    chain: []const u8,
    network: []const u8,
    endpoint_override: ?[]const u8,
) !NetworkConfigResult {
    const network_name = if (network.len == 0) "mainnet" else network;

    const endpoint = if (endpoint_override) |override|
        try allocator.dupe(u8, override)
    else
        try allocator.dupe(u8, defaultEndpoint(chain, network_name));

    const uri = std.Uri.parse(endpoint) catch |err| {
        allocator.free(endpoint);
        return err;
    };

    const chain_id = chainIdFor(chain, network_name);

    return .{
        .config = .{
            .endpoint = .{ .uri = uri },
            .chain_id = chain_id,
        },
        .endpoint = endpoint,
    };
}

pub fn parseAddress(address: []const u8) !Address {
    return utils.addressToBytes(address);
}

pub fn parsePrivateKey(private_key_hex: []const u8) !Hash {
    return utils.hashToBytes(private_key_hex);
}

pub fn parseHash(hash_hex: []const u8) !Hash {
    return utils.hashToBytes(hash_hex);
}

pub fn parseHexDataAlloc(allocator: std.mem.Allocator, hex_str: []const u8) ![]u8 {
    const trimmed = if (std.mem.startsWith(u8, hex_str, "0x")) hex_str[2..] else hex_str;
    if (trimmed.len == 0) return allocator.alloc(u8, 0);
    if (trimmed.len % 2 != 0) return error.InvalidHexLength;

    const out_len = trimmed.len / 2;
    const buffer = try allocator.alloc(u8, out_len);
    errdefer allocator.free(buffer);

    _ = std.fmt.hexToBytes(buffer, trimmed) catch return error.InvalidHexData;
    return buffer;
}

pub fn jsonStringifyAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);

    var stringify: std.json.Stringify = .{
        .writer = &out.writer,
        .options = .{ .emit_null_optional_fields = false },
    };

    try stringify.write(value);
    return out.toOwnedSlice();
}

pub fn resolvePrivateKey(
    allocator: std.mem.Allocator,
    private_key_override: ?[]const u8,
    keypair_path_override: ?[]const u8,
) !Hash {
    if (private_key_override) |value| {
        return parsePrivateKey(value);
    }

    if (c.getenv("EVM_PRIVATE_KEY")) |env_key| {
        const key = std.mem.span(env_key);
        return parsePrivateKey(key);
    }

    const keypair_path = if (keypair_path_override) |p|
        try allocator.dupe(u8, p)
    else
        try getDefaultKeypairPath(allocator);
    defer allocator.free(keypair_path);

    return loadPrivateKeyFromFile(allocator, keypair_path);
}

pub fn formatWeiToEthString(allocator: std.mem.Allocator, wei: u256) ![]u8 {
    const wei_str = try formatU256(allocator, wei);
    defer allocator.free(wei_str);

    if (wei_str.len <= 18) {
        const zeros_count = 18 - wei_str.len;
        const zeros = try allocator.alloc(u8, zeros_count);
        defer allocator.free(zeros);
        @memset(zeros, '0');

        return std.fmt.allocPrint(allocator, "0.{s}{s}", .{ zeros, wei_str });
    }

    const int_part = wei_str[0 .. wei_str.len - 18];
    const frac_part = wei_str[wei_str.len - 18 ..];
    return std.fmt.allocPrint(allocator, "{s}.{s}", .{ int_part, frac_part });
}

pub fn formatU256(allocator: std.mem.Allocator, value: u256) ![]u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{value});
}

fn getDefaultKeypairPath(allocator: std.mem.Allocator) ![]const u8 {
    const home_c = c.getenv("HOME") orelse return error.HomeNotFound;
    const home = std.mem.span(home_c);
    return std.fmt.allocPrint(allocator, "{s}/.config/evm/keyfile.json", .{home});
}

fn loadPrivateKeyFromFile(allocator: std.mem.Allocator, path: []const u8) !Hash {
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

    return parsePrivateKey(key_str);
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

fn chainIdFor(chain: []const u8, network: []const u8) Chains {
    const chain_id_value: usize = if (std.ascii.eqlIgnoreCase(chain, "ethereum") or std.ascii.eqlIgnoreCase(chain, "eth")) blk: {
        if (std.ascii.eqlIgnoreCase(network, "sepolia")) break :blk 11_155_111;
        if (std.ascii.eqlIgnoreCase(network, "goerli")) break :blk 5;
        break :blk 1;
    } else if (std.ascii.eqlIgnoreCase(chain, "avalanche") or std.ascii.eqlIgnoreCase(chain, "avax")) blk: {
        if (std.ascii.eqlIgnoreCase(network, "fuji")) break :blk 43_113;
        break :blk 43_114;
    } else if (std.ascii.eqlIgnoreCase(chain, "bnb") or std.ascii.eqlIgnoreCase(chain, "bsc")) blk: {
        if (std.ascii.eqlIgnoreCase(network, "testnet")) break :blk 97;
        break :blk 56;
    } else blk: {
        break :blk 1;
    };

    return @enumFromInt(chain_id_value);
}

fn defaultEndpoint(chain: []const u8, network: []const u8) []const u8 {
    if (std.ascii.eqlIgnoreCase(chain, "ethereum") or std.ascii.eqlIgnoreCase(chain, "eth")) {
        if (std.ascii.eqlIgnoreCase(network, "sepolia")) return "https://rpc.sepolia.org";
        if (std.ascii.eqlIgnoreCase(network, "goerli")) return "https://rpc.ankr.com/eth_goerli";
        return "https://eth.llamarpc.com";
    }

    if (std.ascii.eqlIgnoreCase(chain, "avalanche") or std.ascii.eqlIgnoreCase(chain, "avax")) {
        if (std.ascii.eqlIgnoreCase(network, "fuji")) return "https://api.avax-test.network/ext/bc/C/rpc";
        return "https://api.avax.network/ext/bc/C/rpc";
    }

    if (std.ascii.eqlIgnoreCase(chain, "bnb") or std.ascii.eqlIgnoreCase(chain, "bsc")) {
        if (std.ascii.eqlIgnoreCase(network, "testnet")) return "https://data-seed-prebsc-1-s1.binance.org:8545";
        return "https://bsc-dataseed.binance.org";
    }

    return "https://eth.llamarpc.com";
}

pub fn parseWeiAmount(amount_str: []const u8) !Wei {
    return std.fmt.parseInt(Wei, amount_str, 10);
}
