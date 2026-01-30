const std = @import("std");
const bcs = @import("../types/bcs.zig");
const checkpoint = @import("../types/checkpoint.zig");
const bls = @import("bls12381.zig");

const ffi = struct {
    extern fn sui_bls_verify_validator_signature(
        committee_ptr: [*]const u8,
        committee_len: usize,
        signature_ptr: [*]const u8,
        signature_len: usize,
        message_ptr: [*]const u8,
        message_len: usize,
    ) std.c.int;
    extern fn sui_bls_verify_validator_aggregated_signature(
        committee_ptr: [*]const u8,
        committee_len: usize,
        signature_ptr: [*]const u8,
        signature_len: usize,
        message_ptr: [*]const u8,
        message_len: usize,
    ) std.c.int;
    extern fn sui_zklogin_last_error_message(buf: ?[*]u8, buf_len: usize) usize;
    extern fn sui_zklogin_clear_error() void;
};

pub const ValidatorCommittee = struct {
    epoch: checkpoint.EpochId,
    members: []ValidatorCommitteeMember,

    pub fn deinit(self: *ValidatorCommittee, allocator: std.mem.Allocator) void {
        allocator.free(self.members);
        self.* = undefined;
    }

    pub fn encodeBcs(self: ValidatorCommittee, writer: *bcs.Writer) !void {
        try writer.writeU64(self.epoch);
        try writer.writeUleb128(self.members.len);
        for (self.members) |member| {
            try member.encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ValidatorCommittee {
        const epoch = try reader.readU64();
        const len = try reader.readUleb128();
        var members = try allocator.alloc(ValidatorCommitteeMember, len);
        errdefer allocator.free(members);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            members[i] = try ValidatorCommitteeMember.decodeBcs(reader);
        }
        return .{ .epoch = epoch, .members = members };
    }
};

pub const ValidatorCommitteeMember = struct {
    public_key: bls.Bls12381PublicKey,
    stake: checkpoint.StakeUnit,

    pub fn encodeBcs(self: ValidatorCommitteeMember, writer: *bcs.Writer) !void {
        try self.public_key.encodeBcs(writer);
        try writer.writeU64(self.stake);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !ValidatorCommitteeMember {
        const public_key = try bls.Bls12381PublicKey.decodeBcs(reader);
        const stake = try reader.readU64();
        return .{ .public_key = public_key, .stake = stake };
    }
};

pub const ValidatorSignature = struct {
    epoch: checkpoint.EpochId,
    public_key: bls.Bls12381PublicKey,
    signature: bls.Bls12381Signature,

    pub fn encodeBcs(self: ValidatorSignature, writer: *bcs.Writer) !void {
        try writer.writeU64(self.epoch);
        try self.public_key.encodeBcs(writer);
        try self.signature.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !ValidatorSignature {
        const epoch = try reader.readU64();
        const public_key = try bls.Bls12381PublicKey.decodeBcs(reader);
        const signature = try bls.Bls12381Signature.decodeBcs(reader);
        return .{ .epoch = epoch, .public_key = public_key, .signature = signature };
    }
};

pub const ValidatorAggregatedSignature = struct {
    epoch: checkpoint.EpochId,
    signature: bls.Bls12381Signature,
    bitmap: []u8,

    pub fn deinit(self: *ValidatorAggregatedSignature, allocator: std.mem.Allocator) void {
        allocator.free(self.bitmap);
        self.* = undefined;
    }

    pub fn encodeBcs(self: ValidatorAggregatedSignature, writer: *bcs.Writer) !void {
        try writer.writeU64(self.epoch);
        try self.signature.encodeBcs(writer);
        try writer.writeBytes(self.bitmap);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ValidatorAggregatedSignature {
        const epoch = try reader.readU64();
        const signature = try bls.Bls12381Signature.decodeBcs(reader);
        const bitmap = try reader.readBytes();
        const bitmap_copy = try allocator.alloc(u8, bitmap.len);
        std.mem.copyForwards(u8, bitmap_copy, bitmap);
        return .{ .epoch = epoch, .signature = signature, .bitmap = bitmap_copy };
    }
};

pub fn verifyValidatorSignature(
    allocator: std.mem.Allocator,
    committee: ValidatorCommittee,
    signature: ValidatorSignature,
    message: []const u8,
) !void {
    var committee_writer = try bcs.Writer.init(allocator);
    defer committee_writer.deinit();
    try committee.encodeBcs(&committee_writer);
    const committee_bytes = try committee_writer.toOwnedSlice();
    defer allocator.free(committee_bytes);

    var signature_writer = try bcs.Writer.init(allocator);
    defer signature_writer.deinit();
    try signature.encodeBcs(&signature_writer);
    const signature_bytes = try signature_writer.toOwnedSlice();
    defer allocator.free(signature_bytes);

    ffi.sui_zklogin_clear_error();
    const result = ffi.sui_bls_verify_validator_signature(
        committee_bytes.ptr,
        committee_bytes.len,
        signature_bytes.ptr,
        signature_bytes.len,
        message.ptr,
        message.len,
    );
    if (result != 0) return error.InvalidSignature;
}

pub fn verifyValidatorAggregatedSignature(
    allocator: std.mem.Allocator,
    committee: ValidatorCommittee,
    signature: ValidatorAggregatedSignature,
    message: []const u8,
) !void {
    var committee_writer = try bcs.Writer.init(allocator);
    defer committee_writer.deinit();
    try committee.encodeBcs(&committee_writer);
    const committee_bytes = try committee_writer.toOwnedSlice();
    defer allocator.free(committee_bytes);

    var signature_writer = try bcs.Writer.init(allocator);
    defer signature_writer.deinit();
    try signature.encodeBcs(&signature_writer);
    const signature_bytes = try signature_writer.toOwnedSlice();
    defer allocator.free(signature_bytes);

    ffi.sui_zklogin_clear_error();
    const result = ffi.sui_bls_verify_validator_aggregated_signature(
        committee_bytes.ptr,
        committee_bytes.len,
        signature_bytes.ptr,
        signature_bytes.len,
        message.ptr,
        message.len,
    );
    if (result != 0) return error.InvalidSignature;
}

pub fn lastErrorMessage(allocator: std.mem.Allocator) !?[]u8 {
    const needed = ffi.sui_zklogin_last_error_message(null, 0);
    if (needed == 0) return null;
    const buf = try allocator.alloc(u8, needed);
    errdefer allocator.free(buf);
    _ = ffi.sui_zklogin_last_error_message(buf.ptr, buf.len);
    return buf;
}
