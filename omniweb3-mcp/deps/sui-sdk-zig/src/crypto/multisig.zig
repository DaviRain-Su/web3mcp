const std = @import("std");
const bcs = @import("../types/bcs.zig");
const signature = @import("signature.zig");
const ed25519 = @import("ed25519.zig");
const secp256k1 = @import("secp256k1.zig");
const secp256r1 = @import("secp256r1.zig");
const zklogin = @import("zklogin.zig");
const passkey = @import("passkey.zig");

pub const WeightUnit = u8;
pub const ThresholdUnit = u16;
pub const BitmapUnit = u16;

pub const MultisigMemberPublicKey = union(enum) {
    ed25519: signature.Ed25519PublicKey,
    secp256k1: signature.Secp256k1PublicKey,
    secp256r1: signature.Secp256r1PublicKey,
    zklogin: zklogin.ZkLoginPublicIdentifier,
    passkey: passkey.PasskeyPublicKey,

    pub fn deinit(self: *MultisigMemberPublicKey, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .zklogin => |*value| value.deinit(allocator),
            .passkey => |*value| value.deinit(allocator),
            else => {},
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: MultisigMemberPublicKey, writer: *bcs.Writer) !void {
        switch (self) {
            .ed25519 => |value| {
                try writer.writeUleb128(0);
                try value.encodeBcs(writer);
            },
            .secp256k1 => |value| {
                try writer.writeUleb128(1);
                try value.encodeBcs(writer);
            },
            .secp256r1 => |value| {
                try writer.writeUleb128(2);
                try value.encodeBcs(writer);
            },
            .zklogin => |value| {
                try writer.writeUleb128(3);
                try value.encodeBcs(writer);
            },
            .passkey => |value| {
                try writer.writeUleb128(4);
                try value.encodeBcs(writer);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !MultisigMemberPublicKey {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .{ .ed25519 = try signature.Ed25519PublicKey.decodeBcs(reader) },
            1 => .{ .secp256k1 = try signature.Secp256k1PublicKey.decodeBcs(reader) },
            2 => .{ .secp256r1 = try signature.Secp256r1PublicKey.decodeBcs(reader) },
            3 => .{ .zklogin = try zklogin.ZkLoginPublicIdentifier.decodeBcs(reader, allocator) },
            4 => .{ .passkey = try passkey.PasskeyPublicKey.decodeBcs(reader, allocator) },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const MultisigMember = struct {
    public_key: MultisigMemberPublicKey,
    weight: WeightUnit,

    pub fn deinit(self: *MultisigMember, allocator: std.mem.Allocator) void {
        self.public_key.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: MultisigMember, writer: *bcs.Writer) !void {
        try self.public_key.encodeBcs(writer);
        try writer.writeU8(self.weight);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !MultisigMember {
        var public_key = try MultisigMemberPublicKey.decodeBcs(reader, allocator);
        errdefer public_key.deinit(allocator);
        const weight = try reader.readU8();
        return .{ .public_key = public_key, .weight = weight };
    }
};

pub const MultisigCommittee = struct {
    members: []MultisigMember,
    threshold: ThresholdUnit,

    pub fn deinit(self: *MultisigCommittee, allocator: std.mem.Allocator) void {
        for (self.members) |*member| member.deinit(allocator);
        allocator.free(self.members);
        self.* = undefined;
    }

    pub fn encodeBcs(self: MultisigCommittee, writer: *bcs.Writer) !void {
        try writer.writeUleb128(self.members.len);
        for (self.members) |member| {
            try member.encodeBcs(writer);
        }
        try writer.writeU16(self.threshold);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !MultisigCommittee {
        const len = try reader.readUleb128();
        var members = try allocator.alloc(MultisigMember, len);
        errdefer {
            for (members) |*member| member.deinit(allocator);
            allocator.free(members);
        }
        var i: usize = 0;
        while (i < len) : (i += 1) {
            members[i] = try MultisigMember.decodeBcs(reader, allocator);
        }
        const threshold = try reader.readU16();
        return .{ .members = members, .threshold = threshold };
    }
};

pub const MultisigMemberSignature = union(enum) {
    ed25519: signature.Ed25519Signature,
    secp256k1: signature.Secp256k1Signature,
    secp256r1: signature.Secp256r1Signature,
    zklogin: zklogin.ZkLoginAuthenticator,
    passkey: passkey.PasskeyAuthenticator,

    pub fn deinit(self: *MultisigMemberSignature, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .zklogin => |*value| value.deinit(allocator),
            .passkey => |*value| value.deinit(allocator),
            else => {},
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: MultisigMemberSignature, writer: *bcs.Writer) !void {
        switch (self) {
            .ed25519 => |value| {
                try writer.writeUleb128(0);
                try value.encodeBcs(writer);
            },
            .secp256k1 => |value| {
                try writer.writeUleb128(1);
                try value.encodeBcs(writer);
            },
            .secp256r1 => |value| {
                try writer.writeUleb128(2);
                try value.encodeBcs(writer);
            },
            .zklogin => |value| {
                try writer.writeUleb128(3);
                try value.encodeBcs(writer);
            },
            .passkey => |value| {
                try writer.writeUleb128(4);
                try value.encodeBcs(writer);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !MultisigMemberSignature {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .{ .ed25519 = try signature.Ed25519Signature.decodeBcs(reader) },
            1 => .{ .secp256k1 = try signature.Secp256k1Signature.decodeBcs(reader) },
            2 => .{ .secp256r1 = try signature.Secp256r1Signature.decodeBcs(reader) },
            3 => .{ .zklogin = try zklogin.ZkLoginAuthenticator.decodeBcs(reader, allocator) },
            4 => .{ .passkey = try passkey.PasskeyAuthenticator.decodeBcs(reader, allocator) },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const MultisigAggregatedSignature = struct {
    signatures: []MultisigMemberSignature,
    bitmap: BitmapUnit,
    legacy_bitmap: ?[]u8 = null,
    committee: MultisigCommittee,

    pub fn deinit(self: *MultisigAggregatedSignature, allocator: std.mem.Allocator) void {
        for (self.signatures) |*sig| sig.deinit(allocator);
        allocator.free(self.signatures);
        if (self.legacy_bitmap) |bitmap| allocator.free(bitmap);
        self.committee.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: MultisigAggregatedSignature, writer: *bcs.Writer) !void {
        const bytes = try self.toBytes(writer.allocator);
        defer writer.allocator.free(bytes);
        try writer.writeBytes(bytes);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !MultisigAggregatedSignature {
        const bytes = try reader.readBytes();
        return try MultisigAggregatedSignature.fromSerializedBytes(bytes, allocator);
    }

    pub fn toBytes(self: MultisigAggregatedSignature, allocator: std.mem.Allocator) ![]u8 {
        var inner = try bcs.Writer.init(allocator);
        defer inner.deinit();
        if (self.legacy_bitmap) |legacy_bitmap| {
            try encodeLegacyMultisig(&inner, self, legacy_bitmap);
        } else {
            try encodeMultisig(&inner, self);
        }

        const inner_bytes = try inner.toOwnedSlice();
        defer allocator.free(inner_bytes);

        const out = try allocator.alloc(u8, inner_bytes.len + 1);
        out[0] = @intFromEnum(signature.SignatureScheme.multisig);
        std.mem.copyForwards(u8, out[1..], inner_bytes);
        return out;
    }

    pub fn fromSerializedBytes(bytes: []const u8, allocator: std.mem.Allocator) !MultisigAggregatedSignature {
        if (bytes.len == 0) return error.InvalidSignature;
        if (bytes[0] != @intFromEnum(signature.SignatureScheme.multisig)) return error.InvalidSignature;
        const bcs_bytes = bytes[1..];

        if (try decodeMultisigNew(bcs_bytes, allocator)) |value| {
            return value;
        }
        if (try decodeMultisigLegacy(bcs_bytes, allocator)) |value| {
            return value;
        }
        return error.InvalidSignature;
    }

    pub fn verify(self: MultisigAggregatedSignature, message: []const u8) !void {
        if (self.committee.members.len == 0) return error.InvalidMultisig;
        if ((self.bitmap >> @intCast(self.committee.members.len)) != 0) return error.InvalidBitmap;

        var sig_index: usize = 0;
        var weight: u16 = 0;
        var i: usize = 0;
        while (i < self.committee.members.len) : (i += 1) {
            if (((self.bitmap >> @intCast(i)) & 1) == 0) continue;
            if (sig_index >= self.signatures.len) return error.SignatureCountMismatch;
            const member = self.committee.members[i];
            const member_signature = self.signatures[sig_index];
            try verifyMemberSignature(member.public_key, member_signature, message);
            weight +%= member.weight;
            sig_index += 1;
        }

        if (sig_index != self.signatures.len) return error.SignatureCountMismatch;
        if (weight < self.committee.threshold) return error.InsufficientWeight;
    }
};

fn encodeMultisig(writer: *bcs.Writer, multisig: MultisigAggregatedSignature) !void {
    try writer.writeUleb128(multisig.signatures.len);
    for (multisig.signatures) |sig| {
        try sig.encodeBcs(writer);
    }
    try writer.writeU16(multisig.bitmap);
    try multisig.committee.encodeBcs(writer);
}

fn encodeLegacyMultisig(writer: *bcs.Writer, multisig: MultisigAggregatedSignature, legacy_bitmap: []const u8) !void {
    try writer.writeUleb128(multisig.signatures.len);
    for (multisig.signatures) |sig| {
        try sig.encodeBcs(writer);
    }
    try writer.writeBytes(legacy_bitmap);
    try encodeLegacyCommittee(writer, multisig.committee);
}

fn encodeLegacyCommittee(writer: *bcs.Writer, committee: MultisigCommittee) !void {
    try writer.writeUleb128(committee.members.len);
    for (committee.members) |member| {
        try encodeLegacyMember(writer, member);
    }
    try writer.writeU16(committee.threshold);
}

fn encodeLegacyMember(writer: *bcs.Writer, member: MultisigMember) !void {
    const base64 = try encodeLegacyMemberPublicKey(writer.allocator, member.public_key);
    defer writer.allocator.free(base64);
    try writer.writeString(base64);
    try writer.writeU8(member.weight);
}

fn encodeLegacyMemberPublicKey(allocator: std.mem.Allocator, public_key: MultisigMemberPublicKey) ![]u8 {
    var raw: [1 + signature.Secp256k1PublicKey.LENGTH]u8 = undefined;
    const bytes = switch (public_key) {
        .ed25519 => |value| blk: {
            raw[0] = @intFromEnum(signature.SignatureScheme.ed25519);
            std.mem.copyForwards(u8, raw[1..(1 + signature.Ed25519PublicKey.LENGTH)], &value.asBytes());
            break :blk raw[0..(1 + signature.Ed25519PublicKey.LENGTH)];
        },
        .secp256k1 => |value| blk: {
            raw[0] = @intFromEnum(signature.SignatureScheme.secp256k1);
            std.mem.copyForwards(u8, raw[1..(1 + signature.Secp256k1PublicKey.LENGTH)], &value.asBytes());
            break :blk raw[0..(1 + signature.Secp256k1PublicKey.LENGTH)];
        },
        .secp256r1 => |value| blk: {
            raw[0] = @intFromEnum(signature.SignatureScheme.secp256r1);
            std.mem.copyForwards(u8, raw[1..(1 + signature.Secp256r1PublicKey.LENGTH)], &value.asBytes());
            break :blk raw[0..(1 + signature.Secp256r1PublicKey.LENGTH)];
        },
        else => return error.InvalidSignature,
    };

    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const out = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(out, bytes);
    return out;
}

fn decodeMultisigNew(bytes: []const u8, allocator: std.mem.Allocator) !?MultisigAggregatedSignature {
    var reader = bcs.Reader.init(bytes);
    return decodeMultisigNewFromReader(&reader, allocator) catch null;
}

fn decodeMultisigNewFromReader(reader: *bcs.Reader, allocator: std.mem.Allocator) !MultisigAggregatedSignature {
    const len = try reader.readUleb128();
    var signatures = try allocator.alloc(MultisigMemberSignature, len);
    errdefer {
        for (signatures) |*sig| sig.deinit(allocator);
        allocator.free(signatures);
    }
    var i: usize = 0;
    while (i < len) : (i += 1) {
        signatures[i] = try MultisigMemberSignature.decodeBcs(reader, allocator);
    }
    const bitmap = try reader.readU16();
    const committee = try MultisigCommittee.decodeBcs(reader, allocator);
    return .{ .signatures = signatures, .bitmap = bitmap, .committee = committee };
}

fn decodeMultisigLegacy(bytes: []const u8, allocator: std.mem.Allocator) !?MultisigAggregatedSignature {
    var reader = bcs.Reader.init(bytes);
    return decodeMultisigLegacyFromReader(&reader, allocator) catch null;
}

fn decodeMultisigLegacyFromReader(reader: *bcs.Reader, allocator: std.mem.Allocator) !MultisigAggregatedSignature {
    const len = try reader.readUleb128();
    var signatures = try allocator.alloc(MultisigMemberSignature, len);
    errdefer {
        for (signatures) |*sig| sig.deinit(allocator);
        allocator.free(signatures);
    }
    var i: usize = 0;
    while (i < len) : (i += 1) {
        signatures[i] = try MultisigMemberSignature.decodeBcs(reader, allocator);
    }

    const legacy_bitmap_bytes = try reader.readBytes();
    const bitmap = try roaringBitmapToU16(legacy_bitmap_bytes);

    var committee = try decodeLegacyCommittee(reader, allocator);
    errdefer committee.deinit(allocator);

    const bitmap_copy = try allocator.alloc(u8, legacy_bitmap_bytes.len);
    std.mem.copyForwards(u8, bitmap_copy, legacy_bitmap_bytes);
    return .{
        .signatures = signatures,
        .bitmap = bitmap,
        .legacy_bitmap = bitmap_copy,
        .committee = committee,
    };
}

fn decodeLegacyCommittee(reader: *bcs.Reader, allocator: std.mem.Allocator) !MultisigCommittee {
    const len = try reader.readUleb128();
    var members = try allocator.alloc(MultisigMember, len);
    errdefer {
        for (members) |*member| member.deinit(allocator);
        allocator.free(members);
    }
    var i: usize = 0;
    while (i < len) : (i += 1) {
        members[i] = try decodeLegacyMember(reader, allocator);
    }
    const threshold = try reader.readU16();
    return .{ .members = members, .threshold = threshold };
}

fn decodeLegacyMember(reader: *bcs.Reader, allocator: std.mem.Allocator) !MultisigMember {
    const key_b64 = try reader.readString();
    const public_key = try decodeLegacyMemberPublicKey(allocator, key_b64);
    const weight = try reader.readU8();
    return .{ .public_key = public_key, .weight = weight };
}

fn decodeLegacyMemberPublicKey(allocator: std.mem.Allocator, b64: []const u8) !MultisigMemberPublicKey {
    const decoded = try decodeBase64Std(allocator, b64);
    defer allocator.free(decoded);
    if (decoded.len == 0) return error.InvalidSignature;
    const scheme = try signature.SignatureScheme.fromByte(decoded[0]);
    const key_bytes = decoded[1..];
    return switch (scheme) {
        .ed25519 => {
            if (key_bytes.len != signature.Ed25519PublicKey.LENGTH) return error.InvalidSignature;
            var key: [signature.Ed25519PublicKey.LENGTH]u8 = undefined;
            std.mem.copyForwards(u8, &key, key_bytes);
            return .{ .ed25519 = signature.Ed25519PublicKey.init(key) };
        },
        .secp256k1 => {
            if (key_bytes.len != signature.Secp256k1PublicKey.LENGTH) return error.InvalidSignature;
            var key: [signature.Secp256k1PublicKey.LENGTH]u8 = undefined;
            std.mem.copyForwards(u8, &key, key_bytes);
            return .{ .secp256k1 = signature.Secp256k1PublicKey.init(key) };
        },
        .secp256r1 => {
            if (key_bytes.len != signature.Secp256r1PublicKey.LENGTH) return error.InvalidSignature;
            var key: [signature.Secp256r1PublicKey.LENGTH]u8 = undefined;
            std.mem.copyForwards(u8, &key, key_bytes);
            return .{ .secp256r1 = signature.Secp256r1PublicKey.init(key) };
        },
        else => return error.InvalidSignature,
    };
}

fn roaringBitmapToU16(bytes: []const u8) !u16 {
    var index: usize = 0;
    if (bytes.len < 4) return error.InvalidSignature;
    const cookie = readU32(bytes, &index);
    const SERIAL_COOKIE_NO_RUNCONTAINER: u32 = 12346;
    const SERIAL_COOKIE: u16 = 12347;
    const NO_OFFSET_THRESHOLD: u32 = 4;

    var size: u32 = 0;
    var run_bitmap: ?[]const u8 = null;
    if (cookie == SERIAL_COOKIE_NO_RUNCONTAINER) {
        if (bytes.len < index + 4) return error.InvalidSignature;
        size = readU32(bytes, &index);
    } else if (@as(u16, @truncate(cookie)) == SERIAL_COOKIE) {
        size = (@as(u32, cookie) >> 16) + 1;
        const run_bytes = (size + 7) / 8;
        if (bytes.len < index + run_bytes) return error.InvalidSignature;
        run_bitmap = bytes[index..(index + run_bytes)];
        index += run_bytes;
    } else {
        return error.InvalidSignature;
    }

    if (size == 0) return 0;
    if (bytes.len < index + size * 4) return error.InvalidSignature;

    const container_count = size;
    var keys = try std.heap.page_allocator.alloc(u16, container_count);
    defer std.heap.page_allocator.free(keys);
    var cards = try std.heap.page_allocator.alloc(u16, container_count);
    defer std.heap.page_allocator.free(cards);
    var types = try std.heap.page_allocator.alloc(u8, container_count);
    defer std.heap.page_allocator.free(types);

    var i: usize = 0;
    while (i < container_count) : (i += 1) {
        const key = readU16(bytes, &index);
        const card_minus_1 = readU16(bytes, &index);
        const card = card_minus_1 + 1;
        keys[i] = key;
        cards[i] = card;
        const is_run = if (run_bitmap) |rb| ((rb[i / 8] >> @intCast(i % 8)) & 1) == 1 else false;
        if (is_run) {
            types[i] = 2;
        } else if (card <= 4096) {
            types[i] = 0;
        } else {
            types[i] = 1;
        }
    }

    if (cookie == SERIAL_COOKIE_NO_RUNCONTAINER or (run_bitmap != null and container_count >= NO_OFFSET_THRESHOLD)) {
        if (bytes.len < index + container_count * 4) return error.InvalidSignature;
        index += container_count * 4;
    }

    var bitmap: u16 = 0;
    i = 0;
    while (i < container_count) : (i += 1) {
        const key = keys[i];
        const card = cards[i];
        const container_type = types[i];
        if (container_type == 0) {
            const bytes_len = card * 2;
            if (bytes.len < index + bytes_len) return error.InvalidSignature;
            if (key == 0) {
                var j: usize = 0;
                while (j < card) : (j += 1) {
                    const value = readU16(bytes, &index);
                    if (value < 16) bitmap |= @as(u16, 1) << @intCast(value);
                }
            } else {
                index += bytes_len;
            }
        } else if (container_type == 1) {
            if (bytes.len < index + 8192) return error.InvalidSignature;
            if (key == 0) {
                const slice = bytes[index..(index + 8192)];
                var bit: u8 = 0;
                while (bit < 16) : (bit += 1) {
                    const byte_index = bit / 8;
                    const bit_index: u3 = @intCast(bit % 8);
                    if (((slice[byte_index] >> bit_index) & 1) == 1) bitmap |= @as(u16, 1) << bit;
                }
            }
            index += 8192;
        } else {
            if (bytes.len < index + 2) return error.InvalidSignature;
            const run_count = readU16(bytes, &index);
            var run_index: usize = 0;
            while (run_index < run_count) : (run_index += 1) {
                if (bytes.len < index + 4) return error.InvalidSignature;
                const start = readU16(bytes, &index);
                const length = readU16(bytes, &index);
                if (key == 0) {
                    const run_end = start + length;
                    var value: u16 = start;
                    while (value <= run_end and value < 16) : (value += 1) {
                        bitmap |= @as(u16, 1) << @intCast(value);
                    }
                }
            }
        }
    }

    return bitmap;
}

fn readU16(bytes: []const u8, index: *usize) u16 {
    const value = std.mem.readInt(u16, bytes[*index .. *index + 2], .little);
    index.* += 2;
    return value;
}

fn readU32(bytes: []const u8, index: *usize) u32 {
    const value = std.mem.readInt(u32, bytes[*index .. *index + 4], .little);
    index.* += 4;
    return value;
}

fn decodeBase64Std(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(input) catch return error.InvalidBase64;
    const out = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(out);
    _ = try std.base64.standard.Decoder.decode(out, input);
    return out;
}

test "multisig fixture" {
    const allocator = std.testing.allocator;
    const fixture_path = "fixtures/multisig_fixture.json";

    var file = std.fs.cwd().openFile(fixture_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(contents);

    const Raw = struct {
        message_base64: []const u8,
        signature_bcs_base64: []const u8,
    };
    var parsed = try std.json.parseFromSlice(Raw, allocator, contents, .{});
    defer parsed.deinit();

    const message = try decodeBase64Std(allocator, parsed.value.message_base64);
    defer allocator.free(message);
    const signature_bytes = try decodeBase64Std(allocator, parsed.value.signature_bcs_base64);
    defer allocator.free(signature_bytes);

    var reader = bcs.Reader.init(signature_bytes);
    var aggregated_signature = try MultisigAggregatedSignature.decodeBcs(&reader, allocator);
    defer aggregated_signature.deinit(allocator);
    try aggregated_signature.verify(message);
}

fn verifyMemberSignature(
    public_key: MultisigMemberPublicKey,
    member_signature: MultisigMemberSignature,
    message: []const u8,
) !void {
    switch (public_key) {
        .ed25519 => |pk| switch (member_signature) {
            .ed25519 => |sig| try ed25519.verify(sig, message, pk),
            else => return error.InvalidSignature,
        },
        .secp256k1 => |pk| switch (member_signature) {
            .secp256k1 => |sig| try secp256k1.verify(sig, message, pk),
            else => return error.InvalidSignature,
        },
        .secp256r1 => |pk| switch (member_signature) {
            .secp256r1 => |sig| try secp256r1.verify(sig, message, pk),
            else => return error.InvalidSignature,
        },
        .zklogin => switch (member_signature) {
            .zklogin => |sig| try sig.verify(message),
            else => return error.InvalidSignature,
        },
        .passkey => |pk| switch (member_signature) {
            .passkey => |sig| {
                if (pk.public_key.asBytes() != sig.public_key.asBytes()) return error.InvalidSignature;
                try sig.verify(message);
            },
            else => return error.InvalidSignature,
        },
    }
}
