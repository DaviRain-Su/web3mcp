const std = @import("std");
const chain_provider = @import("../../core/chain_provider.zig");
const ContractMeta = chain_provider.ContractMeta;

/// IDL Resolver - fetches and parses Solana program IDLs
pub const IdlResolver = struct {
    allocator: std.mem.Allocator,
    rpc_url: []const u8,

    pub fn init(allocator: std.mem.Allocator, rpc_url: []const u8) !IdlResolver {
        return .{
            .allocator = allocator,
            .rpc_url = rpc_url,
        };
    }

    pub fn deinit(self: *IdlResolver) void {
        _ = self;
    }

    /// Resolve IDL for a program
    /// Tries multiple strategies in order:
    /// 1. On-chain IDL account
    /// 2. Solana FM API
    /// 3. Local registry
    pub fn resolve(
        self: *IdlResolver,
        allocator: std.mem.Allocator,
        program_id: []const u8,
    ) !ContractMeta {
        _ = self;
        _ = allocator;
        _ = program_id;

        // TODO: Implement IDL resolution
        return error.NotImplemented;
    }
};
