const std = @import("std");
const bcs = @import("../types/bcs.zig");
const ed25519 = @import("ed25519.zig");
const secp256k1 = @import("secp256k1.zig");
const secp256r1 = @import("secp256r1.zig");
const multisig = @import("multisig.zig");
const zklogin = @import("zklogin.zig");
const passkey = @import("passkey.zig");

pub const Ed25519PublicKey = ed25519.Ed25519PublicKey;
pub const Ed25519Signature = ed25519.Ed25519Signature;
pub const Secp256k1PublicKey = secp256k1.Secp256k1PublicKey;
pub const Secp256k1Signature = secp256k1.Secp256k1Signature;
pub const Secp256r1PublicKey = secp256r1.Secp256r1PublicKey;
pub const Secp256r1Signature = secp256r1.Secp256r1Signature;

pub const SignatureScheme = enum(u8) {
    ed25519 = 0x00,
    secp256k1 = 0x01,
    secp256r1 = 0x02,
    multisig = 0x03,
    bls12381 = 0x04,
    zklogin = 0x05,
    passkey = 0x06,

    pub fn name(self: SignatureScheme) []const u8 {
        return switch (self) {
            .ed25519 => "ed25519",
            .secp256k1 => "secp256k1",
            .secp256r1 => "secp256r1",
            .multisig => "multisig",
            .bls12381 => "bls12381",
            .zklogin => "zklogin",
            .passkey => "passkey",
        };
    }

    pub fn fromByte(flag: u8) !SignatureScheme {
        return switch (flag) {
            0x00 => .ed25519,
            0x01 => .secp256k1,
            0x02 => .secp256r1,
            0x03 => .multisig,
            0x04 => .bls12381,
            0x05 => .zklogin,
            0x06 => .passkey,
            else => error.InvalidSignatureScheme,
        };
    }
};

pub const SimpleSignature = union(enum) {
    ed25519: struct { signature: Ed25519Signature, public_key: Ed25519PublicKey },
    secp256k1: struct { signature: Secp256k1Signature, public_key: Secp256k1PublicKey },
    secp256r1: struct { signature: Secp256r1Signature, public_key: Secp256r1PublicKey },

    pub fn scheme(self: SimpleSignature) SignatureScheme {
        return switch (self) {
            .ed25519 => .ed25519,
            .secp256k1 => .secp256k1,
            .secp256r1 => .secp256r1,
        };
    }

    pub fn toBytes(self: SimpleSignature, buffer: []u8) ![]const u8 {
        return switch (self) {
            .ed25519 => |value| {
                const needed = 1 + Ed25519Signature.LENGTH + Ed25519PublicKey.LENGTH;
                if (buffer.len < needed) return error.NoSpaceLeft;
                buffer[0] = @intFromEnum(SignatureScheme.ed25519);
                std.mem.copyForwards(u8, buffer[1..(1 + Ed25519Signature.LENGTH)], &value.signature.asBytes());
                std.mem.copyForwards(u8, buffer[(1 + Ed25519Signature.LENGTH)..needed], &value.public_key.asBytes());
                return buffer[0..needed];
            },
            .secp256k1 => |value| {
                const needed = 1 + Secp256k1Signature.LENGTH + Secp256k1PublicKey.LENGTH;
                if (buffer.len < needed) return error.NoSpaceLeft;
                buffer[0] = @intFromEnum(SignatureScheme.secp256k1);
                std.mem.copyForwards(u8, buffer[1..(1 + Secp256k1Signature.LENGTH)], &value.signature.asBytes());
                std.mem.copyForwards(u8, buffer[(1 + Secp256k1Signature.LENGTH)..needed], &value.public_key.asBytes());
                return buffer[0..needed];
            },
            .secp256r1 => |value| {
                const needed = 1 + Secp256r1Signature.LENGTH + Secp256r1PublicKey.LENGTH;
                if (buffer.len < needed) return error.NoSpaceLeft;
                buffer[0] = @intFromEnum(SignatureScheme.secp256r1);
                std.mem.copyForwards(u8, buffer[1..(1 + Secp256r1Signature.LENGTH)], &value.signature.asBytes());
                std.mem.copyForwards(u8, buffer[(1 + Secp256r1Signature.LENGTH)..needed], &value.public_key.asBytes());
                return buffer[0..needed];
            },
        };
    }

    pub fn fromSerializedBytes(bytes: []const u8) !SimpleSignature {
        if (bytes.len == 0) return error.InvalidSignature;
        const scheme_value = try SignatureScheme.fromByte(bytes[0]);
        return switch (scheme_value) {
            .ed25519 => {
                const expected = 1 + Ed25519Signature.LENGTH + Ed25519PublicKey.LENGTH;
                if (bytes.len != expected) return error.InvalidSignature;
                var sig: [Ed25519Signature.LENGTH]u8 = undefined;
                std.mem.copyForwards(u8, &sig, bytes[1..(1 + Ed25519Signature.LENGTH)]);
                var pk: [Ed25519PublicKey.LENGTH]u8 = undefined;
                std.mem.copyForwards(u8, &pk, bytes[(1 + Ed25519Signature.LENGTH)..]);
                return .{ .ed25519 = .{ .signature = Ed25519Signature.init(sig), .public_key = Ed25519PublicKey.init(pk) } };
            },
            .secp256k1 => {
                const expected = 1 + Secp256k1Signature.LENGTH + Secp256k1PublicKey.LENGTH;
                if (bytes.len != expected) return error.InvalidSignature;
                var sig: [Secp256k1Signature.LENGTH]u8 = undefined;
                std.mem.copyForwards(u8, &sig, bytes[1..(1 + Secp256k1Signature.LENGTH)]);
                var pk: [Secp256k1PublicKey.LENGTH]u8 = undefined;
                std.mem.copyForwards(u8, &pk, bytes[(1 + Secp256k1Signature.LENGTH)..]);
                return .{ .secp256k1 = .{ .signature = Secp256k1Signature.init(sig), .public_key = Secp256k1PublicKey.init(pk) } };
            },
            .secp256r1 => {
                const expected = 1 + Secp256r1Signature.LENGTH + Secp256r1PublicKey.LENGTH;
                if (bytes.len != expected) return error.InvalidSignature;
                var sig: [Secp256r1Signature.LENGTH]u8 = undefined;
                std.mem.copyForwards(u8, &sig, bytes[1..(1 + Secp256r1Signature.LENGTH)]);
                var pk: [Secp256r1PublicKey.LENGTH]u8 = undefined;
                std.mem.copyForwards(u8, &pk, bytes[(1 + Secp256r1Signature.LENGTH)..]);
                return .{ .secp256r1 = .{ .signature = Secp256r1Signature.init(sig), .public_key = Secp256r1PublicKey.init(pk) } };
            },
            else => return error.InvalidSignature,
        };
    }

    pub fn encodeBcs(self: SimpleSignature, writer: *bcs.Writer) !void {
        var buffer: [1 + Secp256k1Signature.LENGTH + Secp256k1PublicKey.LENGTH]u8 = undefined;
        const serialized = try self.toBytes(&buffer);
        try writer.writeBytes(serialized);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !SimpleSignature {
        const bytes = try reader.readBytes();
        return try SimpleSignature.fromSerializedBytes(bytes);
    }

    pub fn verify(self: SimpleSignature, message: []const u8) !void {
        return switch (self) {
            .ed25519 => |value| ed25519.verify(value.signature, message, value.public_key),
            .secp256k1 => |value| secp256k1.verify(value.signature, message, value.public_key),
            .secp256r1 => |value| secp256r1.verify(value.signature, message, value.public_key),
        };
    }
};

pub const MultisigAggregatedSignature = multisig.MultisigAggregatedSignature;
pub const MultisigMemberSignature = multisig.MultisigMemberSignature;
pub const MultisigCommittee = multisig.MultisigCommittee;
pub const MultisigMember = multisig.MultisigMember;
pub const MultisigMemberPublicKey = multisig.MultisigMemberPublicKey;
pub const ZkLoginAuthenticator = zklogin.ZkLoginAuthenticator;
pub const PasskeyAuthenticator = passkey.PasskeyAuthenticator;

pub const UserSignature = union(enum) {
    simple: SimpleSignature,
    multisig: MultisigAggregatedSignature,
    zklogin: ZkLoginAuthenticator,
    passkey: PasskeyAuthenticator,

    pub fn scheme(self: UserSignature) SignatureScheme {
        return switch (self) {
            .simple => |value| value.scheme(),
            .multisig => .multisig,
            .zklogin => .zklogin,
            .passkey => .passkey,
        };
    }

    pub fn deinit(self: *UserSignature, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .simple => {},
            .multisig => |*value| value.deinit(allocator),
            .zklogin => |*value| value.deinit(allocator),
            .passkey => |*value| value.deinit(allocator),
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: UserSignature, writer: *bcs.Writer) !void {
        const bytes = try self.toBytes(writer.allocator);
        defer writer.allocator.free(bytes);
        try writer.writeBytes(bytes);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !UserSignature {
        const bytes = try reader.readBytes();
        return try UserSignature.fromSerializedBytes(bytes, allocator);
    }

    pub fn toBytes(self: UserSignature, allocator: std.mem.Allocator) ![]u8 {
        return switch (self) {
            .simple => |value| {
                var buffer: [1 + Secp256k1Signature.LENGTH + Secp256k1PublicKey.LENGTH]u8 = undefined;
                const serialized = try value.toBytes(&buffer);
                const out = try allocator.alloc(u8, serialized.len);
                std.mem.copyForwards(u8, out, serialized);
                return out;
            },
            .multisig => |value| try value.toBytes(allocator),
            .zklogin => |value| try value.toBytes(allocator),
            .passkey => |value| try value.toBytes(allocator),
        };
    }

    pub fn fromSerializedBytes(bytes: []const u8, allocator: std.mem.Allocator) !UserSignature {
        if (bytes.len == 0) return error.InvalidSignature;
        const scheme_value = try SignatureScheme.fromByte(bytes[0]);
        return switch (scheme_value) {
            .ed25519, .secp256k1, .secp256r1 => .{ .simple = try SimpleSignature.fromSerializedBytes(bytes) },
            .multisig => .{ .multisig = try MultisigAggregatedSignature.fromSerializedBytes(bytes, allocator) },
            .zklogin => .{ .zklogin = try ZkLoginAuthenticator.fromSerializedBytes(bytes, allocator) },
            .passkey => .{ .passkey = try PasskeyAuthenticator.fromSerializedBytes(bytes, allocator) },
            .bls12381 => return error.InvalidSignature,
        };
    }

    pub fn verify(self: UserSignature, message: []const u8) !void {
        switch (self) {
            .simple => |value| try value.verify(message),
            .multisig => |value| try value.verify(message),
            .zklogin => |value| try value.verify(message),
            .passkey => |value| try value.verify(message),
            else => return error.UnsupportedSignatureScheme,
        }
    }
};

pub fn userSignatureToBase64(allocator: std.mem.Allocator, signature: UserSignature) ![]u8 {
    const bytes = try signature.toBytes(allocator);
    defer allocator.free(bytes);
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const out = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(out, bytes);
    return out;
}

pub fn userSignatureFromBase64(allocator: std.mem.Allocator, input: []const u8) !UserSignature {
    const decoded = try decodeBase64Std(allocator, input);
    defer allocator.free(decoded);
    return try UserSignature.fromSerializedBytes(decoded, allocator);
}

pub fn userSignatureFromJson(allocator: std.mem.Allocator, input: []const u8) !UserSignature {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
    defer parsed.deinit();

    switch (parsed.value) {
        .string => |value| return userSignatureFromBase64(allocator, value),
        .object => {},
        else => return error.InvalidSignature,
    }

    const obj = parsed.value.object;
    const scheme_value = obj.get("scheme") orelse return error.InvalidSignature;
    if (scheme_value.* != .string) return error.InvalidSignature;
    const scheme = scheme_value.string;

    if (std.mem.eql(u8, scheme, "multisig")) {
        const aggregated = try parseMultisigAggregatedSignatureJson(allocator, parsed.value);
        return .{ .multisig = aggregated };
    }
    if (std.mem.eql(u8, scheme, "passkey")) {
        const passkey_value = try parsePasskeyAuthenticatorJson(allocator, parsed.value);
        return .{ .passkey = passkey_value };
    }
    if (std.mem.eql(u8, scheme, "zklogin")) {
        const zklogin_value = try parseZkloginAuthenticatorJson(allocator, parsed.value);
        return .{ .zklogin = zklogin_value };
    }

    const signature_value = obj.get("signature") orelse return error.InvalidSignature;
    const public_key_value = obj.get("public_key") orelse return error.InvalidSignature;
    if (signature_value.* != .string or public_key_value.* != .string) return error.InvalidSignature;

    const sig_b64 = signature_value.string;
    const pk_b64 = public_key_value.string;

    if (std.mem.eql(u8, scheme, "ed25519")) {
        return .{ .simple = .{ .ed25519 = .{ .signature = try decodeEd25519Signature(allocator, sig_b64), .public_key = try decodeEd25519PublicKey(allocator, pk_b64) } } };
    }
    if (std.mem.eql(u8, scheme, "secp256k1")) {
        return .{ .simple = .{ .secp256k1 = .{ .signature = try decodeSecp256k1Signature(allocator, sig_b64), .public_key = try decodeSecp256k1PublicKey(allocator, pk_b64) } } };
    }
    if (std.mem.eql(u8, scheme, "secp256r1")) {
        return .{ .simple = .{ .secp256r1 = .{ .signature = try decodeSecp256r1Signature(allocator, sig_b64), .public_key = try decodeSecp256r1PublicKey(allocator, pk_b64) } } };
    }
    return error.UnsupportedSignatureScheme;
}

fn parseMultisigAggregatedSignatureJson(allocator: std.mem.Allocator, value: std.json.Value) !MultisigAggregatedSignature {
    if (value != .object) return error.InvalidSignature;
    const obj = value.object;

    const signatures_value = obj.get("signatures") orelse return error.InvalidSignature;
    const bitmap_value = obj.get("bitmap") orelse return error.InvalidSignature;
    const committee_value = obj.get("committee") orelse return error.InvalidSignature;

    if (signatures_value.* != .array or bitmap_value.* != .integer or committee_value.* != .object) {
        return error.InvalidSignature;
    }

    const signatures_array = signatures_value.array;
    var signatures = try allocator.alloc(MultisigMemberSignature, signatures_array.items.len);
    errdefer {
        for (signatures) |*sig| sig.deinit(allocator);
        allocator.free(signatures);
    }
    var i: usize = 0;
    while (i < signatures_array.items.len) : (i += 1) {
        signatures[i] = try parseMultisigMemberSignatureJson(allocator, signatures_array.items[i]);
    }

    const bitmap = try parseU16(bitmap_value.*);
    var committee = try parseMultisigCommitteeJson(allocator, committee_value.*);
    errdefer committee.deinit(allocator);

    var legacy_bitmap: ?[]u8 = null;
    if (obj.get("legacy_bitmap")) |legacy_value| {
        if (legacy_value.* == .string) {
            const decoded = try decodeBase64Std(allocator, legacy_value.string);
            legacy_bitmap = decoded;
        } else {
            return error.InvalidSignature;
        }
    }

    return .{ .signatures = signatures, .bitmap = bitmap, .legacy_bitmap = legacy_bitmap, .committee = committee };
}

fn parseMultisigCommitteeJson(allocator: std.mem.Allocator, value: std.json.Value) !MultisigCommittee {
    if (value != .object) return error.InvalidSignature;
    const obj = value.object;
    const members_value = obj.get("members") orelse return error.InvalidSignature;
    const threshold_value = obj.get("threshold") orelse return error.InvalidSignature;
    if (members_value.* != .array or threshold_value.* != .integer) return error.InvalidSignature;

    const members_array = members_value.array;
    var members = try allocator.alloc(MultisigMember, members_array.items.len);
    errdefer {
        for (members) |*member| member.deinit(allocator);
        allocator.free(members);
    }
    var i: usize = 0;
    while (i < members_array.items.len) : (i += 1) {
        members[i] = try parseMultisigMemberJson(allocator, members_array.items[i]);
    }

    const threshold = try parseU16(threshold_value.*);
    return .{ .members = members, .threshold = threshold };
}

fn parseMultisigMemberJson(allocator: std.mem.Allocator, value: std.json.Value) !MultisigMember {
    if (value != .object) return error.InvalidSignature;
    const obj = value.object;
    const public_key_value = obj.get("public_key") orelse return error.InvalidSignature;
    const weight_value = obj.get("weight") orelse return error.InvalidSignature;
    if (public_key_value.* != .object or weight_value.* != .integer) return error.InvalidSignature;
    const public_key = try parseMultisigMemberPublicKeyJson(allocator, public_key_value.*);
    const weight = try parseU8(weight_value.*);
    return .{ .public_key = public_key, .weight = weight };
}

fn parseMultisigMemberPublicKeyJson(allocator: std.mem.Allocator, value: std.json.Value) !MultisigMemberPublicKey {
    if (value != .object) return error.InvalidSignature;
    const obj = value.object;
    const scheme_value = obj.get("scheme") orelse return error.InvalidSignature;
    if (scheme_value.* != .string) return error.InvalidSignature;
    const scheme = scheme_value.string;

    if (std.mem.eql(u8, scheme, "zklogin")) {
        return .{ .zklogin = try parseZkloginPublicIdentifierJson(allocator, value) };
    }

    const pk_value = obj.get("public_key") orelse return error.InvalidSignature;
    if (pk_value.* != .string) return error.InvalidSignature;
    const pk_b64 = pk_value.string;

    if (std.mem.eql(u8, scheme, "ed25519")) {
        return .{ .ed25519 = try decodeEd25519PublicKey(allocator, pk_b64) };
    }
    if (std.mem.eql(u8, scheme, "secp256k1")) {
        return .{ .secp256k1 = try decodeSecp256k1PublicKey(allocator, pk_b64) };
    }
    if (std.mem.eql(u8, scheme, "secp256r1")) {
        return .{ .secp256r1 = try decodeSecp256r1PublicKey(allocator, pk_b64) };
    }
    if (std.mem.eql(u8, scheme, "passkey")) {
        return .{ .passkey = .{ .public_key = try decodeSecp256r1PublicKey(allocator, pk_b64) } };
    }
    return error.InvalidSignature;
}

fn parseMultisigMemberSignatureJson(allocator: std.mem.Allocator, value: std.json.Value) !MultisigMemberSignature {
    if (value != .object) return error.InvalidSignature;
    const obj = value.object;
    const scheme_value = obj.get("scheme") orelse return error.InvalidSignature;
    if (scheme_value.* != .string) return error.InvalidSignature;
    const scheme = scheme_value.string;

    if (std.mem.eql(u8, scheme, "passkey")) {
        return .{ .passkey = try parsePasskeyAuthenticatorJson(allocator, value) };
    }
    if (std.mem.eql(u8, scheme, "zklogin")) {
        return .{ .zklogin = try parseZkloginAuthenticatorJson(allocator, value) };
    }

    const signature_value = obj.get("signature") orelse return error.InvalidSignature;
    if (signature_value.* != .string) return error.InvalidSignature;
    const sig_b64 = signature_value.string;

    if (std.mem.eql(u8, scheme, "ed25519")) {
        return .{ .ed25519 = try decodeEd25519Signature(allocator, sig_b64) };
    }
    if (std.mem.eql(u8, scheme, "secp256k1")) {
        return .{ .secp256k1 = try decodeSecp256k1Signature(allocator, sig_b64) };
    }
    if (std.mem.eql(u8, scheme, "secp256r1")) {
        return .{ .secp256r1 = try decodeSecp256r1Signature(allocator, sig_b64) };
    }
    return error.InvalidSignature;
}

fn parsePasskeyAuthenticatorJson(allocator: std.mem.Allocator, value: std.json.Value) !PasskeyAuthenticator {
    if (value != .object) return error.InvalidSignature;
    const obj = value.object;

    const auth_data_value = obj.get("authenticator_data") orelse return error.InvalidSignature;
    const client_data_value = obj.get("client_data_json") orelse return error.InvalidSignature;
    const signature_value = obj.get("signature") orelse return error.InvalidSignature;

    if (client_data_value.* != .string or signature_value.* != .object) return error.InvalidSignature;

    const authenticator_data = try parseJsonBytes(allocator, auth_data_value.*);
    errdefer allocator.free(authenticator_data);
    const client_data_json = try dupBytes(allocator, client_data_value.string);
    errdefer allocator.free(client_data_json);

    const simple_sig = try parseSimpleSignatureJson(allocator, signature_value.*);
    if (simple_sig != .secp256r1) return error.InvalidSignature;

    const authenticator = try passkey.PasskeyAuthenticator.initFromRaw(
        allocator,
        authenticator_data,
        client_data_json,
        simple_sig,
    );
    return authenticator;
}

fn parseZkloginAuthenticatorJson(allocator: std.mem.Allocator, value: std.json.Value) !ZkLoginAuthenticator {
    if (value != .object) return error.InvalidSignature;
    const obj = value.object;

    const inputs_value = obj.get("inputs") orelse return error.InvalidSignature;
    const max_epoch_value = obj.get("max_epoch") orelse return error.InvalidSignature;
    const signature_value = obj.get("signature") orelse return error.InvalidSignature;

    if (inputs_value.* != .object or signature_value.* != .object) return error.InvalidSignature;
    const max_epoch = try parseU64(max_epoch_value.*);

    var inputs = try parseZkloginInputsJson(allocator, inputs_value.*);
    errdefer inputs.deinit(allocator);
    const simple_sig = try parseSimpleSignatureJson(allocator, signature_value.*);

    return .{ .inputs = inputs, .max_epoch = max_epoch, .signature = simple_sig };
}

fn parseZkloginInputsJson(allocator: std.mem.Allocator, value: std.json.Value) !zklogin.ZkLoginInputs {
    if (value != .object) return error.InvalidSignature;
    const obj = value.object;

    const proof_value = obj.get("proof_points") orelse return error.InvalidSignature;
    const claim_value = obj.get("iss_base64_details") orelse return error.InvalidSignature;
    const header_value = obj.get("header_base64") orelse return error.InvalidSignature;
    const seed_value = obj.get("address_seed") orelse return error.InvalidSignature;

    if (proof_value.* != .object or claim_value.* != .object or header_value.* != .string or seed_value.* != .string) {
        return error.InvalidSignature;
    }

    var proof = try parseZkloginProofJson(allocator, proof_value.*);
    errdefer proof.deinit(allocator);
    var claim = try parseZkloginClaimJson(allocator, claim_value.*);
    errdefer claim.deinit(allocator);

    const header = try dupBytes(allocator, header_value.string);
    errdefer allocator.free(header);
    const address_seed = try zklogin.Bn254FieldElement.fromDecimalString(allocator, seed_value.string);

    return .{ .proof_points = proof, .iss_base64_details = claim, .header_base64 = header, .address_seed = address_seed };
}

fn parseZkloginProofJson(allocator: std.mem.Allocator, value: std.json.Value) !zklogin.ZkLoginProof {
    if (value != .object) return error.InvalidSignature;
    const obj = value.object;
    const a_value = obj.get("a") orelse return error.InvalidSignature;
    const b_value = obj.get("b") orelse return error.InvalidSignature;
    const c_value = obj.get("c") orelse return error.InvalidSignature;
    if (a_value.* != .array or b_value.* != .array or c_value.* != .array) return error.InvalidSignature;

    const a = try parseCircomG1Json(allocator, a_value.*);
    const b = try parseCircomG2Json(allocator, b_value.*);
    const c = try parseCircomG1Json(allocator, c_value.*);
    return .{ .a = a, .b = b, .c = c };
}

fn parseCircomG1Json(allocator: std.mem.Allocator, value: std.json.Value) !zklogin.CircomG1 {
    if (value != .array or value.array.items.len != 3) return error.InvalidSignature;
    var points: [3]zklogin.Bn254FieldElement = undefined;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const item = value.array.items[i];
        if (item != .string) return error.InvalidSignature;
        points[i] = try zklogin.Bn254FieldElement.fromDecimalString(allocator, item.string);
    }
    return .{ .points = points };
}

fn parseCircomG2Json(allocator: std.mem.Allocator, value: std.json.Value) !zklogin.CircomG2 {
    if (value != .array or value.array.items.len != 3) return error.InvalidSignature;
    var points: [3][2]zklogin.Bn254FieldElement = undefined;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const inner = value.array.items[i];
        if (inner != .array or inner.array.items.len != 2) return error.InvalidSignature;
        const first = inner.array.items[0];
        const second = inner.array.items[1];
        if (first != .string or second != .string) return error.InvalidSignature;
        points[i][0] = try zklogin.Bn254FieldElement.fromDecimalString(allocator, first.string);
        points[i][1] = try zklogin.Bn254FieldElement.fromDecimalString(allocator, second.string);
    }
    return .{ .points = points };
}

fn parseZkloginClaimJson(allocator: std.mem.Allocator, value: std.json.Value) !zklogin.ZkLoginClaim {
    if (value != .object) return error.InvalidSignature;
    const obj = value.object;
    const claim_value = obj.get("value") orelse return error.InvalidSignature;
    const index_value = obj.get("index_mod_4") orelse return error.InvalidSignature;
    if (claim_value.* != .string or index_value.* != .integer) return error.InvalidSignature;
    const claim = try dupBytes(allocator, claim_value.string);
    const index = try parseU8(index_value.*);
    return .{ .value = claim, .index_mod_4 = index };
}

fn parseZkloginPublicIdentifierJson(allocator: std.mem.Allocator, value: std.json.Value) !zklogin.ZkLoginPublicIdentifier {
    if (value != .object) return error.InvalidSignature;
    const obj = value.object;
    const iss_value = obj.get("iss") orelse return error.InvalidSignature;
    const seed_value = obj.get("address_seed") orelse return error.InvalidSignature;
    if (iss_value.* != .string or seed_value.* != .string) return error.InvalidSignature;
    const iss = try dupBytes(allocator, iss_value.string);
    const seed = try zklogin.Bn254FieldElement.fromDecimalString(allocator, seed_value.string);
    return .{ .iss = iss, .address_seed = seed };
}

fn parseSimpleSignatureJson(allocator: std.mem.Allocator, value: std.json.Value) !SimpleSignature {
    if (value != .object) return error.InvalidSignature;
    const obj = value.object;
    const scheme_value = obj.get("scheme") orelse return error.InvalidSignature;
    const signature_value = obj.get("signature") orelse return error.InvalidSignature;
    const public_key_value = obj.get("public_key") orelse return error.InvalidSignature;
    if (scheme_value.* != .string or signature_value.* != .string or public_key_value.* != .string) return error.InvalidSignature;

    const scheme = scheme_value.string;
    const sig_b64 = signature_value.string;
    const pk_b64 = public_key_value.string;

    if (std.mem.eql(u8, scheme, "ed25519")) {
        return .{ .ed25519 = .{ .signature = try decodeEd25519Signature(allocator, sig_b64), .public_key = try decodeEd25519PublicKey(allocator, pk_b64) } };
    }
    if (std.mem.eql(u8, scheme, "secp256k1")) {
        return .{ .secp256k1 = .{ .signature = try decodeSecp256k1Signature(allocator, sig_b64), .public_key = try decodeSecp256k1PublicKey(allocator, pk_b64) } };
    }
    if (std.mem.eql(u8, scheme, "secp256r1")) {
        return .{ .secp256r1 = .{ .signature = try decodeSecp256r1Signature(allocator, sig_b64), .public_key = try decodeSecp256r1PublicKey(allocator, pk_b64) } };
    }
    return error.InvalidSignature;
}

fn parseJsonBytes(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    return switch (value) {
        .string => |str| decodeBase64Std(allocator, str),
        .array => |array| blk: {
            const out = try allocator.alloc(u8, array.items.len);
            var i: usize = 0;
            while (i < array.items.len) : (i += 1) {
                const item = array.items[i];
                if (item != .integer) return error.InvalidSignature;
                const value_int = item.integer;
                if (value_int < 0 or value_int > 255) return error.InvalidSignature;
                out[i] = @intCast(value_int);
            }
            break :blk out;
        },
        else => error.InvalidSignature,
    };
}

fn dupBytes(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, input.len);
    std.mem.copyForwards(u8, out, input);
    return out;
}

fn parseU8(value: std.json.Value) !u8 {
    if (value != .integer) return error.InvalidSignature;
    if (value.integer < 0 or value.integer > 255) return error.InvalidSignature;
    return @intCast(value.integer);
}

fn parseU16(value: std.json.Value) !u16 {
    if (value != .integer) return error.InvalidSignature;
    if (value.integer < 0 or value.integer > std.math.maxInt(u16)) return error.InvalidSignature;
    return @intCast(value.integer);
}

fn parseU64(value: std.json.Value) !u64 {
    if (value != .integer) return error.InvalidSignature;
    if (value.integer < 0) return error.InvalidSignature;
    return @intCast(value.integer);
}

fn decodeEd25519Signature(allocator: std.mem.Allocator, input: []const u8) !Ed25519Signature {
    const decoded = try decodeBase64Std(allocator, input);
    defer allocator.free(decoded);
    if (decoded.len != Ed25519Signature.LENGTH) return error.InvalidSignature;
    var sig: [Ed25519Signature.LENGTH]u8 = undefined;
    std.mem.copyForwards(u8, &sig, decoded);
    return Ed25519Signature.init(sig);
}

fn decodeEd25519PublicKey(allocator: std.mem.Allocator, input: []const u8) !Ed25519PublicKey {
    const decoded = try decodeBase64Std(allocator, input);
    defer allocator.free(decoded);
    if (decoded.len != Ed25519PublicKey.LENGTH) return error.InvalidSignature;
    var pk: [Ed25519PublicKey.LENGTH]u8 = undefined;
    std.mem.copyForwards(u8, &pk, decoded);
    return Ed25519PublicKey.init(pk);
}

fn decodeSecp256k1Signature(allocator: std.mem.Allocator, input: []const u8) !Secp256k1Signature {
    const decoded = try decodeBase64Std(allocator, input);
    defer allocator.free(decoded);
    if (decoded.len != Secp256k1Signature.LENGTH) return error.InvalidSignature;
    var sig: [Secp256k1Signature.LENGTH]u8 = undefined;
    std.mem.copyForwards(u8, &sig, decoded);
    return Secp256k1Signature.init(sig);
}

fn decodeSecp256k1PublicKey(allocator: std.mem.Allocator, input: []const u8) !Secp256k1PublicKey {
    const decoded = try decodeBase64Std(allocator, input);
    defer allocator.free(decoded);
    if (decoded.len != Secp256k1PublicKey.LENGTH) return error.InvalidSignature;
    var pk: [Secp256k1PublicKey.LENGTH]u8 = undefined;
    std.mem.copyForwards(u8, &pk, decoded);
    return Secp256k1PublicKey.init(pk);
}

fn decodeSecp256r1Signature(allocator: std.mem.Allocator, input: []const u8) !Secp256r1Signature {
    const decoded = try decodeBase64Std(allocator, input);
    defer allocator.free(decoded);
    if (decoded.len != Secp256r1Signature.LENGTH) return error.InvalidSignature;
    var sig: [Secp256r1Signature.LENGTH]u8 = undefined;
    std.mem.copyForwards(u8, &sig, decoded);
    return Secp256r1Signature.init(sig);
}

fn decodeSecp256r1PublicKey(allocator: std.mem.Allocator, input: []const u8) !Secp256r1PublicKey {
    const decoded = try decodeBase64Std(allocator, input);
    defer allocator.free(decoded);
    if (decoded.len != Secp256r1PublicKey.LENGTH) return error.InvalidSignature;
    var pk: [Secp256r1PublicKey.LENGTH]u8 = undefined;
    std.mem.copyForwards(u8, &pk, decoded);
    return Secp256r1PublicKey.init(pk);
}

fn decodeBase64Std(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(input) catch return error.InvalidBase64;
    const out = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(out);
    _ = try std.base64.standard.Decoder.decode(out, input);
    return out;
}

test "simple signature fixture" {
    const allocator = std.testing.allocator;
    const fixture_path = "fixtures/simple_signature_fixture.json";

    var file = std.fs.cwd().openFile(fixture_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(contents);

    const Raw = struct {
        message_base64: []const u8,
        ed25519_bcs_base64: []const u8,
        secp256k1_bcs_base64: []const u8,
        secp256r1_bcs_base64: []const u8,
    };
    var parsed = try std.json.parseFromSlice(Raw, allocator, contents, .{});
    defer parsed.deinit();

    const message = try decodeBase64Std(allocator, parsed.value.message_base64);
    defer allocator.free(message);

    const ed_bytes = try decodeBase64Std(allocator, parsed.value.ed25519_bcs_base64);
    defer allocator.free(ed_bytes);
    const k1_bytes = try decodeBase64Std(allocator, parsed.value.secp256k1_bcs_base64);
    defer allocator.free(k1_bytes);
    const r1_bytes = try decodeBase64Std(allocator, parsed.value.secp256r1_bcs_base64);
    defer allocator.free(r1_bytes);

    var ed_reader = bcs.Reader.init(ed_bytes);
    const ed_bcs = try ed_reader.readBytes();
    const ed_sig = try SimpleSignature.fromSerializedBytes(ed_bcs);
    try ed_sig.verify(message);

    var k1_reader = bcs.Reader.init(k1_bytes);
    const k1_bcs = try k1_reader.readBytes();
    const k1_sig = try SimpleSignature.fromSerializedBytes(k1_bcs);
    try k1_sig.verify(message);

    var r1_reader = bcs.Reader.init(r1_bytes);
    const r1_bcs = try r1_reader.readBytes();
    const r1_sig = try SimpleSignature.fromSerializedBytes(r1_bcs);
    try r1_sig.verify(message);
}

test "user signature fixture" {
    const allocator = std.testing.allocator;
    const fixture_path = "fixtures/user_signature_fixture.json";

    var file = std.fs.cwd().openFile(fixture_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(contents);

    const Raw = struct {
        message_base64: []const u8,
        user_signature_base64: []const u8,
    };
    var parsed = try std.json.parseFromSlice(Raw, allocator, contents, .{});
    defer parsed.deinit();

    const message = try decodeBase64Std(allocator, parsed.value.message_base64);
    defer allocator.free(message);
    const signature_bytes = try decodeBase64Std(allocator, parsed.value.user_signature_base64);
    defer allocator.free(signature_bytes);

    var signature = try UserSignature.fromSerializedBytes(signature_bytes, allocator);
    defer signature.deinit(allocator);
    try signature.verify(message);

    const encoded = try userSignatureToBase64(allocator, signature);
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings(parsed.value.user_signature_base64, encoded);
}

test "legacy multisig fixture" {
    const allocator = std.testing.allocator;
    const fixture_path = "fixtures/legacy_multisig_fixture.json";

    var file = std.fs.cwd().openFile(fixture_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(contents);

    const Raw = struct {
        message_base64: []const u8,
        user_signature_base64: []const u8,
    };
    var parsed = try std.json.parseFromSlice(Raw, allocator, contents, .{});
    defer parsed.deinit();

    const message = try decodeBase64Std(allocator, parsed.value.message_base64);
    defer allocator.free(message);

    var signature = try userSignatureFromBase64(allocator, parsed.value.user_signature_base64);
    defer signature.deinit(allocator);
    try signature.verify(message);
}

test "user signature json fixture" {
    const allocator = std.testing.allocator;
    const fixture_path = "fixtures/user_signature_json_fixture.json";

    var file = std.fs.cwd().openFile(fixture_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(contents);

    const Raw = struct {
        message_base64: []const u8,
        user_signature_json: []const u8,
    };
    var parsed = try std.json.parseFromSlice(Raw, allocator, contents, .{});
    defer parsed.deinit();

    const message = try decodeBase64Std(allocator, parsed.value.message_base64);
    defer allocator.free(message);

    var signature = try userSignatureFromJson(allocator, parsed.value.user_signature_json);
    defer signature.deinit(allocator);
    try signature.verify(message);
}

test "user signature json base64 fixture" {
    const allocator = std.testing.allocator;
    const fixture_path = "fixtures/user_signature_json_base64_fixture.json";

    var file = std.fs.cwd().openFile(fixture_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(contents);

    const Raw = struct {
        message_base64: []const u8,
        user_signature_json: []const u8,
    };
    var parsed = try std.json.parseFromSlice(Raw, allocator, contents, .{});
    defer parsed.deinit();

    const message = try decodeBase64Std(allocator, parsed.value.message_base64);
    defer allocator.free(message);

    var signature = try userSignatureFromJson(allocator, parsed.value.user_signature_json);
    defer signature.deinit(allocator);
    try signature.verify(message);
}

test "user signature json multisig fixture" {
    const allocator = std.testing.allocator;
    const fixture_path = "fixtures/user_signature_json_multisig_fixture.json";

    var file = std.fs.cwd().openFile(fixture_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(contents);

    const Raw = struct {
        message_base64: []const u8,
        user_signature_json: []const u8,
    };
    var parsed = try std.json.parseFromSlice(Raw, allocator, contents, .{});
    defer parsed.deinit();

    const message = try decodeBase64Std(allocator, parsed.value.message_base64);
    defer allocator.free(message);

    var signature = try userSignatureFromJson(allocator, parsed.value.user_signature_json);
    defer signature.deinit(allocator);
    try signature.verify(message);
}

test "user signature json passkey fixture" {
    const allocator = std.testing.allocator;
    const fixture_path = "fixtures/user_signature_json_passkey_fixture.json";

    var file = std.fs.cwd().openFile(fixture_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(contents);

    const Raw = struct {
        message_base64: []const u8,
        user_signature_json: []const u8,
    };
    var parsed = try std.json.parseFromSlice(Raw, allocator, contents, .{});
    defer parsed.deinit();

    const message = try decodeBase64Std(allocator, parsed.value.message_base64);
    defer allocator.free(message);

    var signature = try userSignatureFromJson(allocator, parsed.value.user_signature_json);
    defer signature.deinit(allocator);
    try signature.verify(message);
}

test "user signature json zklogin fixture" {
    const allocator = std.testing.allocator;
    const fixture_path = "fixtures/user_signature_json_zklogin_fixture.json";

    var file = std.fs.cwd().openFile(fixture_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(contents);

    const Raw = struct {
        message_base64: []const u8,
        user_signature_json: []const u8,
    };
    var parsed = try std.json.parseFromSlice(Raw, allocator, contents, .{});
    defer parsed.deinit();

    const message = try decodeBase64Std(allocator, parsed.value.message_base64);
    defer allocator.free(message);

    var signature = try userSignatureFromJson(allocator, parsed.value.user_signature_json);
    defer signature.deinit(allocator);
    try signature.verify(message);
}
