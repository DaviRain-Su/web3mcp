const std = @import("std");

pub const SolanaAdapter = @import("adapters/solana.zig").SolanaAdapter;
pub const EvmAdapter = @import("adapters/evm.zig").EvmAdapter;

pub fn initSolanaAdapter(
    allocator: std.mem.Allocator,
    network: []const u8,
    endpoint_override: ?[]const u8,
) !SolanaAdapter {
    return SolanaAdapter.init(allocator, network, endpoint_override);
}

pub fn initEvmAdapter(
    allocator: std.mem.Allocator,
    io: std.Io,
    chain: []const u8,
    network: []const u8,
    endpoint_override: ?[]const u8,
) !EvmAdapter {
    return EvmAdapter.init(allocator, io, chain, network, endpoint_override);
}
