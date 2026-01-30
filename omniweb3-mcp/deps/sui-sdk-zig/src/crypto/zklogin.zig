const std = @import("std");
const bcs = @import("../types/bcs.zig");
const build_options = @import("build_options");
const SimpleSignature = @import("signature.zig").SimpleSignature;
const SignatureScheme = @import("signature.zig").SignatureScheme;
const Address = @import("../types/address.zig").Address;
const base64 = std.base64;
const json = std.json;
const big = std.math.big.int;
const openssl = @cImport({
    @cInclude("openssl/evp.h");
    @cInclude("openssl/rsa.h");
    @cInclude("openssl/bn.h");
});
const Jwk = @import("../types/zklogin.zig").Jwk;

const zklogin_ffi = struct {
    extern fn sui_zklogin_verify_bcs(
        jwk_ptr: [*]const u8,
        jwk_len: usize,
        inputs_ptr: [*]const u8,
        inputs_len: usize,
        signature_ptr: [*]const u8,
        signature_len: usize,
        message_ptr: [*]const u8,
        message_len: usize,
        max_epoch: u64,
        use_dev_vk: bool,
    ) std.c.int;
    extern fn sui_zklogin_verify_json(
        jwk_json_ptr: [*]const u8,
        jwk_json_len: usize,
        inputs_json_ptr: [*]const u8,
        inputs_json_len: usize,
        signature_json_ptr: [*]const u8,
        signature_json_len: usize,
        message_ptr: [*]const u8,
        message_len: usize,
        max_epoch: u64,
        use_dev_vk: bool,
    ) std.c.int;
    extern fn sui_zklogin_last_error_message(buf: ?[*]u8, buf_len: usize) usize;
    extern fn sui_zklogin_clear_error() void;
};

pub const Bn254FieldElement = struct {
    bytes: [32]u8,

    pub fn init(bytes: [32]u8) Bn254FieldElement {
        return .{ .bytes = bytes };
    }

    pub fn fromDecimalString(allocator: std.mem.Allocator, value: []const u8) !Bn254FieldElement {
        var number = try big.Managed.init(allocator);
        defer number.deinit();
        try number.setString(10, value);
        if (!number.toConst().fitsInTwosComp(.unsigned, 256)) return error.ValueTooLarge;
        var out: [32]u8 = undefined;
        number.toConst().writeTwosComplement(&out, .big);
        return .{ .bytes = out };
    }

    pub fn toDecimalString(self: Bn254FieldElement, allocator: std.mem.Allocator) ![]u8 {
        var number = try big.Managed.init(allocator);
        defer number.deinit();
        try number.ensureCapacity(big.calcTwosCompLimbCount(256));
        var mutable = number.toMutable();
        mutable.readTwosComplement(&self.bytes, 256, .big, .unsigned);
        number.setMetadata(true, mutable.len);
        return number.toString(allocator, 10, .lower);
    }

    pub fn padded(self: Bn254FieldElement) []const u8 {
        return &self.bytes;
    }

    pub fn unpadded(self: Bn254FieldElement) []const u8 {
        var slice = self.bytes[0..];
        while (slice.len > 0 and slice[0] == 0) {
            slice = slice[1..];
        }
        if (slice.len == 0) return self.bytes[31..];
        return slice;
    }

    pub fn encodeBcs(self: Bn254FieldElement, writer: *bcs.Writer) !void {
        const decimal = try self.toDecimalString(writer.allocator);
        defer writer.allocator.free(decimal);
        try writer.writeString(decimal);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !Bn254FieldElement {
        const value = try reader.readString();
        return Bn254FieldElement.fromDecimalString(allocator, value);
    }
};

pub const CircomG1 = struct {
    points: [3]Bn254FieldElement,

    pub fn deinit(self: *CircomG1, allocator: std.mem.Allocator) void {
        for (self.points) |*point| point.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: CircomG1, writer: *bcs.Writer) !void {
        try writer.writeUleb128(3);
        for (self.points) |point| {
            try point.encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !CircomG1 {
        const len = try reader.readUleb128();
        if (len != 3) return bcs.BcsError.InvalidOptionTag;
        var points: [3]Bn254FieldElement = undefined;
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            points[i] = try Bn254FieldElement.decodeBcs(reader, allocator);
        }
        return .{ .points = points };
    }
};

pub const CircomG2 = struct {
    points: [3][2]Bn254FieldElement,

    pub fn deinit(self: *CircomG2, allocator: std.mem.Allocator) void {
        for (self.points) |pair| {
            for (pair) |*point| point.deinit(allocator);
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: CircomG2, writer: *bcs.Writer) !void {
        try writer.writeUleb128(3);
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            try writer.writeUleb128(2);
            try self.points[i][0].encodeBcs(writer);
            try self.points[i][1].encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !CircomG2 {
        const outer = try reader.readUleb128();
        if (outer != 3) return bcs.BcsError.InvalidOptionTag;
        var points: [3][2]Bn254FieldElement = undefined;
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            const inner = try reader.readUleb128();
            if (inner != 2) return bcs.BcsError.InvalidOptionTag;
            points[i][0] = try Bn254FieldElement.decodeBcs(reader, allocator);
            points[i][1] = try Bn254FieldElement.decodeBcs(reader, allocator);
        }
        return .{ .points = points };
    }
};

pub const ZkLoginProof = struct {
    a: CircomG1,
    b: CircomG2,
    c: CircomG1,

    pub fn deinit(self: *ZkLoginProof, allocator: std.mem.Allocator) void {
        self.a.deinit(allocator);
        self.b.deinit(allocator);
        self.c.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: ZkLoginProof, writer: *bcs.Writer) !void {
        try self.a.encodeBcs(writer);
        try self.b.encodeBcs(writer);
        try self.c.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ZkLoginProof {
        var a = try CircomG1.decodeBcs(reader, allocator);
        errdefer a.deinit(allocator);
        var b = try CircomG2.decodeBcs(reader, allocator);
        errdefer b.deinit(allocator);
        const c = try CircomG1.decodeBcs(reader, allocator);
        return .{ .a = a, .b = b, .c = c };
    }
};

pub const ZkLoginClaim = struct {
    value: []u8,
    index_mod_4: u8,

    pub fn deinit(self: *ZkLoginClaim, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
        self.* = undefined;
    }

    pub fn encodeBcs(self: ZkLoginClaim, writer: *bcs.Writer) !void {
        try writer.writeString(self.value);
        try writer.writeU8(self.index_mod_4);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ZkLoginClaim {
        const value = try reader.readString();
        const index_mod_4 = try reader.readU8();
        const copy = try allocator.alloc(u8, value.len);
        std.mem.copyForwards(u8, copy, value);
        return .{ .value = copy, .index_mod_4 = index_mod_4 };
    }

    pub fn verifyExtendedClaim(self: ZkLoginClaim, allocator: std.mem.Allocator, expected_key: []const u8) ![]u8 {
        const decoded = try decodeBase64UrlClaim(allocator, self.value, self.index_mod_4);
        errdefer allocator.free(decoded);
        if (!(decoded.len > 0 and (decoded[decoded.len - 1] == '}' or decoded[decoded.len - 1] == ','))) {
            return error.InvalidZkLoginClaim;
        }

        const key_prefix = try std.fmt.allocPrint(allocator, "\"{s}\"", .{expected_key});
        defer allocator.free(key_prefix);
        if (std.mem.indexOf(u8, decoded, key_prefix)) |pos| {
            const slice = decoded[pos + key_prefix.len ..];
            const colon_index = std.mem.indexOfScalar(u8, slice, ':') orelse return error.InvalidZkLoginClaim;
            var rest = std.mem.trimLeft(u8, slice[colon_index + 1 ..], " \n\t\r");
            if (rest.len == 0 or rest[0] != '"') return error.InvalidZkLoginClaim;
            rest = rest[1..];
            const end_quote = std.mem.indexOfScalar(u8, rest, '"') orelse return error.InvalidZkLoginClaim;
            const value = rest[0..end_quote];
            const out = try allocator.alloc(u8, value.len);
            std.mem.copyForwards(u8, out, value);
            allocator.free(decoded);
            return out;
        }

        return error.InvalidZkLoginClaim;
    }
};

pub const ZkLoginInputs = struct {
    proof_points: ZkLoginProof,
    iss_base64_details: ZkLoginClaim,
    header_base64: []u8,
    address_seed: Bn254FieldElement,

    pub fn deinit(self: *ZkLoginInputs, allocator: std.mem.Allocator) void {
        self.proof_points.deinit(allocator);
        self.iss_base64_details.deinit(allocator);
        allocator.free(self.header_base64);
        self.address_seed.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: ZkLoginInputs, writer: *bcs.Writer) !void {
        try self.proof_points.encodeBcs(writer);
        try self.iss_base64_details.encodeBcs(writer);
        try writer.writeString(self.header_base64);
        try self.address_seed.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ZkLoginInputs {
        var proof_points = try ZkLoginProof.decodeBcs(reader, allocator);
        errdefer proof_points.deinit(allocator);
        var claim = try ZkLoginClaim.decodeBcs(reader, allocator);
        errdefer claim.deinit(allocator);
        const header = try reader.readString();
        const header_copy = try allocator.alloc(u8, header.len);
        std.mem.copyForwards(u8, header_copy, header);
        const address_seed = try Bn254FieldElement.decodeBcs(reader, allocator);
        return .{ .proof_points = proof_points, .iss_base64_details = claim, .header_base64 = header_copy, .address_seed = address_seed };
    }

    pub fn jwtHeader(self: ZkLoginInputs, allocator: std.mem.Allocator) !JwtHeader {
        return JwtHeader.decodeBase64Url(self.header_base64, allocator);
    }

    pub fn publicIdentifier(self: ZkLoginInputs, allocator: std.mem.Allocator, iss: []const u8) !ZkLoginPublicIdentifier {
        const iss_copy = try dupBytes(allocator, iss);
        return .{ .iss = iss_copy, .address_seed = self.address_seed };
    }

    pub fn verifyIssuer(self: ZkLoginInputs, allocator: std.mem.Allocator) ![]u8 {
        return self.iss_base64_details.verifyExtendedClaim(allocator, "iss");
    }
};

pub const ZkLoginPublicIdentifier = struct {
    iss: []u8,
    address_seed: Bn254FieldElement,

    pub fn deinit(self: *ZkLoginPublicIdentifier, allocator: std.mem.Allocator) void {
        allocator.free(self.iss);
        self.address_seed.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: ZkLoginPublicIdentifier, writer: *bcs.Writer) !void {
        if (self.iss.len > 255) return bcs.BcsError.Overflow;
        try writer.writeU8(@intCast(self.iss.len));
        try writer.writeFixedBytes(self.iss);
        try writer.writeFixedBytes(&self.address_seed.bytes);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ZkLoginPublicIdentifier {
        const len = try reader.readU8();
        const bytes = try reader.readFixedBytes(len);
        const iss = try allocator.alloc(u8, bytes.len);
        std.mem.copyForwards(u8, iss, bytes);
        const seed_bytes = try reader.readFixedBytes(32);
        var seed: [32]u8 = undefined;
        std.mem.copyForwards(u8, &seed, seed_bytes);
        return .{ .iss = iss, .address_seed = Bn254FieldElement.init(seed) };
    }

    pub fn deriveAddressPadded(self: ZkLoginPublicIdentifier) Address {
        return hashAddress(self.iss, self.address_seed.padded());
    }

    pub fn deriveAddressUnpadded(self: ZkLoginPublicIdentifier) Address {
        return hashAddress(self.iss, self.address_seed.unpadded());
    }

    pub fn deriveAddresses(self: ZkLoginPublicIdentifier) DerivedAddresses {
        const primary = self.deriveAddressPadded();
        var secondary: ?Address = null;
        if (self.address_seed.padded()[0] == 0) {
            secondary = self.deriveAddressUnpadded();
        }
        return .{ .primary = primary, .secondary = secondary };
    }
};

pub const ZkLoginAuthenticator = struct {
    inputs: ZkLoginInputs,
    max_epoch: u64,
    signature: SimpleSignature,

    pub fn deinit(self: *ZkLoginAuthenticator, allocator: std.mem.Allocator) void {
        self.inputs.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: ZkLoginAuthenticator, writer: *bcs.Writer) !void {
        const bytes = try self.toBytes(writer.allocator);
        defer writer.allocator.free(bytes);
        try writer.writeBytes(bytes);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ZkLoginAuthenticator {
        const bytes = try reader.readBytes();
        return try ZkLoginAuthenticator.fromSerializedBytes(bytes, allocator);
    }

    pub fn toBytes(self: ZkLoginAuthenticator, allocator: std.mem.Allocator) ![]u8 {
        var inner = try bcs.Writer.init(allocator);
        defer inner.deinit();
        try self.inputs.encodeBcs(&inner);
        try inner.writeU64(self.max_epoch);
        try self.signature.encodeBcs(&inner);
        const inner_bytes = try inner.toOwnedSlice();
        defer allocator.free(inner_bytes);

        const out = try allocator.alloc(u8, inner_bytes.len + 1);
        out[0] = @intFromEnum(SignatureScheme.zklogin);
        std.mem.copyForwards(u8, out[1..], inner_bytes);
        return out;
    }

    pub fn fromSerializedBytes(bytes: []const u8, allocator: std.mem.Allocator) !ZkLoginAuthenticator {
        if (bytes.len == 0) return error.InvalidSignature;
        if (bytes[0] != @intFromEnum(SignatureScheme.zklogin)) return error.InvalidSignature;
        var inner_reader = bcs.Reader.init(bytes[1..]);
        var inputs = try ZkLoginInputs.decodeBcs(&inner_reader, allocator);
        errdefer inputs.deinit(allocator);
        const max_epoch = try inner_reader.readU64();
        const signature = try SimpleSignature.decodeBcs(&inner_reader);
        return .{ .inputs = inputs, .max_epoch = max_epoch, .signature = signature };
    }

    pub fn verify(self: ZkLoginAuthenticator, message: []const u8) !void {
        try self.signature.verify(message);
    }

    pub fn verifyFull(
        self: ZkLoginAuthenticator,
        allocator: std.mem.Allocator,
        message: []const u8,
        jwt_payload_b64: []const u8,
        jwt_signature_b64: []const u8,
        jwk: Jwk,
    ) !void {
        try self.verifyFullWithKey(allocator, message, jwt_payload_b64, jwt_signature_b64, jwk, false);
    }

    pub fn verifyFullWithKey(
        self: ZkLoginAuthenticator,
        allocator: std.mem.Allocator,
        message: []const u8,
        jwt_payload_b64: []const u8,
        jwt_signature_b64: []const u8,
        jwk: Jwk,
        use_dev_vk: bool,
    ) !void {
        const iss = try self.inputs.verifyIssuer(allocator);
        defer allocator.free(iss);

        const header = try self.inputs.jwtHeader(allocator);
        _ = header;

        const signing_input = try joinJwtParts(allocator, self.inputs.header_base64, jwt_payload_b64);
        defer allocator.free(signing_input);
        try verifyJwtRs256(allocator, jwk, signing_input, jwt_signature_b64);

        try self.signature.verify(message);
        try verifyZkloginProofWithRust(allocator, self.inputs, self.signature, jwk, message, self.max_epoch, use_dev_vk);
    }

    pub fn deriveAddressPadded(self: ZkLoginAuthenticator, allocator: std.mem.Allocator, iss: []const u8) !Address {
        var identifier = try self.inputs.publicIdentifier(allocator, iss);
        defer identifier.deinit(allocator);
        return identifier.deriveAddressPadded();
    }

    pub fn deriveAddressUnpadded(self: ZkLoginAuthenticator, allocator: std.mem.Allocator, iss: []const u8) !Address {
        var identifier = try self.inputs.publicIdentifier(allocator, iss);
        defer identifier.deinit(allocator);
        return identifier.deriveAddressUnpadded();
    }
};

pub const DerivedAddresses = struct {
    primary: Address,
    secondary: ?Address,
};

const JwtHeader = struct {
    alg: []const u8,
    kid: []const u8,
    typ: ?[]const u8,

    pub fn decodeBase64Url(input: []const u8, allocator: std.mem.Allocator) !JwtHeader {
        const decoded_len = base64.url_safe_no_pad.Decoder.calcSizeForSlice(input) catch return error.InvalidJwtHeader;
        const buf = try allocator.alloc(u8, decoded_len);
        defer allocator.free(buf);
        _ = try base64.url_safe_no_pad.Decoder.decode(buf, input);

        const Header = struct { alg: []const u8, kid: []const u8, typ: ?[]const u8 = null };
        var parsed = try json.parseFromSlice(Header, allocator, buf, .{});
        defer parsed.deinit();
        if (!std.mem.eql(u8, parsed.value.alg, "RS256")) return error.InvalidJwtHeader;
        return .{ .alg = parsed.value.alg, .kid = parsed.value.kid, .typ = parsed.value.typ };
    }
};

fn hashAddress(iss: []const u8, address_seed: []const u8) Address {
    var hasher = std.crypto.hash.blake2.Blake2b256.init(.{});
    const flag: u8 = @intFromEnum(SignatureScheme.zklogin);
    hasher.update(&.{flag});
    hasher.update(&.{@intCast(iss.len)});
    hasher.update(iss);
    hasher.update(address_seed);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return Address.fromBytes(digest);
}

pub fn verifyJwtRs256(
    allocator: std.mem.Allocator,
    jwk: Jwk,
    signing_input: []const u8,
    signature_b64: []const u8,
) !void {
    if (!std.mem.eql(u8, jwk.kty, "RSA")) return error.InvalidJwtHeader;
    if (!std.mem.eql(u8, jwk.alg, "RS256")) return error.InvalidJwtHeader;

    const sig = try decodeBase64Url(allocator, signature_b64);
    defer allocator.free(sig);
    const n_bytes = try decodeBase64Url(allocator, jwk.n);
    defer allocator.free(n_bytes);
    const e_bytes = try decodeBase64Url(allocator, jwk.e);
    defer allocator.free(e_bytes);

    const rsa = openssl.RSA_new() orelse return error.OpenSslError;
    var rsa_assigned = false;
    defer if (!rsa_assigned) openssl.RSA_free(rsa);

    const n = openssl.BN_bin2bn(n_bytes.ptr, @intCast(n_bytes.len), null) orelse return error.OpenSslError;
    const e = openssl.BN_bin2bn(e_bytes.ptr, @intCast(e_bytes.len), null) orelse {
        openssl.BN_free(n);
        return error.OpenSslError;
    };
    if (openssl.RSA_set0_key(rsa, n, e, null) != 1) {
        openssl.BN_free(n);
        openssl.BN_free(e);
        return error.OpenSslError;
    }

    const pkey = openssl.EVP_PKEY_new() orelse return error.OpenSslError;
    defer openssl.EVP_PKEY_free(pkey);
    if (openssl.EVP_PKEY_assign_RSA(pkey, rsa) != 1) return error.OpenSslError;
    rsa_assigned = true;

    const ctx = openssl.EVP_MD_CTX_new() orelse return error.OpenSslError;
    defer openssl.EVP_MD_CTX_free(ctx);
    if (openssl.EVP_DigestVerifyInit(ctx, null, openssl.EVP_sha256(), null, pkey) != 1) return error.OpenSslError;
    if (openssl.EVP_DigestVerifyUpdate(ctx, signing_input.ptr, signing_input.len) != 1) return error.OpenSslError;
    const ok = openssl.EVP_DigestVerifyFinal(ctx, sig.ptr, sig.len);
    if (ok != 1) return error.InvalidSignature;
}

fn decodeBase64Url(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const decoded_len = base64.url_safe_no_pad.Decoder.calcSizeForSlice(input) catch return error.InvalidBase64;
    const out = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(out);
    _ = try base64.url_safe_no_pad.Decoder.decode(out, input);
    return out;
}

fn joinJwtParts(allocator: std.mem.Allocator, header_b64: []const u8, payload_b64: []const u8) ![]u8 {
    const total = header_b64.len + 1 + payload_b64.len;
    const out = try allocator.alloc(u8, total);
    std.mem.copyForwards(u8, out[0..header_b64.len], header_b64);
    out[header_b64.len] = '.';
    std.mem.copyForwards(u8, out[header_b64.len + 1 ..], payload_b64);
    return out;
}

fn verifyZkloginProofWithRust(
    allocator: std.mem.Allocator,
    inputs: ZkLoginInputs,
    signature: SimpleSignature,
    jwk: Jwk,
    message: []const u8,
    max_epoch: u64,
    use_dev_vk: bool,
) !void {
    var inputs_writer = try bcs.Writer.init(allocator);
    defer inputs_writer.deinit();
    try inputs.encodeBcs(&inputs_writer);
    const inputs_bytes = try inputs_writer.toOwnedSlice();
    defer allocator.free(inputs_bytes);

    var signature_writer = try bcs.Writer.init(allocator);
    defer signature_writer.deinit();
    try signature.encodeBcs(&signature_writer);
    const signature_bytes = try signature_writer.toOwnedSlice();
    defer allocator.free(signature_bytes);

    var jwk_writer = try bcs.Writer.init(allocator);
    defer jwk_writer.deinit();
    try jwk.encodeBcs(&jwk_writer);
    const jwk_bytes = try jwk_writer.toOwnedSlice();
    defer allocator.free(jwk_bytes);

    zklogin_ffi.sui_zklogin_clear_error();
    const result = zklogin_ffi.sui_zklogin_verify_bcs(
        jwk_bytes.ptr,
        jwk_bytes.len,
        inputs_bytes.ptr,
        inputs_bytes.len,
        signature_bytes.ptr,
        signature_bytes.len,
        message.ptr,
        message.len,
        max_epoch,
        use_dev_vk,
    );
    if (result != 0) {
        return error.ProofVerificationFailed;
    }
}

pub fn verifyZkloginProofWithRustJson(
    allocator: std.mem.Allocator,
    jwk_json: []const u8,
    inputs_json: []const u8,
    signature_json: []const u8,
    message: []const u8,
    max_epoch: u64,
    use_dev_vk: bool,
) !void {
    zklogin_ffi.sui_zklogin_clear_error();
    const result = zklogin_ffi.sui_zklogin_verify_json(
        jwk_json.ptr,
        jwk_json.len,
        inputs_json.ptr,
        inputs_json.len,
        signature_json.ptr,
        signature_json.len,
        message.ptr,
        message.len,
        max_epoch,
        use_dev_vk,
    );
    if (result != 0) {
        _ = allocator;
        return error.ProofVerificationFailed;
    }
}

pub fn verifyFullFromJson(
    allocator: std.mem.Allocator,
    message: []const u8,
    jwt_payload_b64: []const u8,
    jwt_signature_b64: []const u8,
    jwk_json: []const u8,
    inputs_json: []const u8,
    signature_json: []const u8,
    max_epoch: u64,
    use_dev_vk: bool,
) !void {
    const jwk = try parseJwkJson(allocator, jwk_json);
    defer jwk.deinit(allocator);

    const header_b64 = try parseHeaderBase64FromInputsJson(allocator, inputs_json);
    defer allocator.free(header_b64);

    const signing_input = try joinJwtParts(allocator, header_b64, jwt_payload_b64);
    defer allocator.free(signing_input);
    try verifyJwtRs256(allocator, jwk, signing_input, jwt_signature_b64);

    try verifyZkloginProofWithRustJson(
        allocator,
        jwk_json,
        inputs_json,
        signature_json,
        message,
        max_epoch,
        use_dev_vk,
    );
}

fn parseHeaderBase64FromInputsJson(allocator: std.mem.Allocator, inputs_json: []const u8) ![]u8 {
    var parsed = try json.parseFromSlice(json.Value, allocator, inputs_json, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidJson;
    const obj = parsed.value.object;
    const header_value = obj.get("header_base64") orelse return error.InvalidJson;
    if (header_value.* != .string) return error.InvalidJson;
    return dupBytes(allocator, header_value.string);
}

fn parseJwkJson(allocator: std.mem.Allocator, jwk_json: []const u8) !Jwk {
    const RawJwk = struct {
        kty: []const u8,
        e: []const u8,
        n: []const u8,
        alg: []const u8,
    };

    var parsed = try json.parseFromSlice(RawJwk, allocator, jwk_json, .{});
    defer parsed.deinit();

    return .{
        .kty = try dupBytes(allocator, parsed.value.kty),
        .e = try dupBytes(allocator, parsed.value.e),
        .n = try dupBytes(allocator, parsed.value.n),
        .alg = try dupBytes(allocator, parsed.value.alg),
    };
}

pub fn zkloginLastErrorMessage(allocator: std.mem.Allocator) !?[]u8 {
    const needed = zklogin_ffi.sui_zklogin_last_error_message(null, 0);
    if (needed == 0) return null;
    const buf = try allocator.alloc(u8, needed);
    errdefer allocator.free(buf);
    _ = zklogin_ffi.sui_zklogin_last_error_message(buf.ptr, buf.len);
    return buf;
}

pub const ZkLoginJsonFixture = struct {
    jwk_json: []u8,
    inputs_json: []u8,
    signature_json: []u8,
    message: []u8,
    jwt_payload_b64: []u8,
    jwt_signature_b64: []u8,
    max_epoch: u64,
    use_dev_vk: bool,

    pub fn deinit(self: *ZkLoginJsonFixture, allocator: std.mem.Allocator) void {
        allocator.free(self.jwk_json);
        allocator.free(self.inputs_json);
        allocator.free(self.signature_json);
        allocator.free(self.message);
        allocator.free(self.jwt_payload_b64);
        allocator.free(self.jwt_signature_b64);
        self.* = undefined;
    }
};

pub fn loadZkloginFixtureFromFile(allocator: std.mem.Allocator, path: []const u8) !ZkLoginJsonFixture {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(contents);

    const RawFixture = struct {
        jwk_json: []const u8,
        inputs_json: []const u8,
        signature_json: []const u8,
        message_base64: []const u8,
        jwt_payload_b64: []const u8,
        jwt_signature_b64: []const u8,
        max_epoch: u64,
        use_dev_vk: bool = false,
    };

    var parsed = try json.parseFromSlice(RawFixture, allocator, contents, .{});
    defer parsed.deinit();

    const message = try decodeBase64Std(allocator, parsed.value.message_base64);

    return .{
        .jwk_json = try dupBytes(allocator, parsed.value.jwk_json),
        .inputs_json = try dupBytes(allocator, parsed.value.inputs_json),
        .signature_json = try dupBytes(allocator, parsed.value.signature_json),
        .message = message,
        .jwt_payload_b64 = try dupBytes(allocator, parsed.value.jwt_payload_b64),
        .jwt_signature_b64 = try dupBytes(allocator, parsed.value.jwt_signature_b64),
        .max_epoch = parsed.value.max_epoch,
        .use_dev_vk = parsed.value.use_dev_vk,
    };
}

fn decodeBase64Std(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(input) catch return error.InvalidBase64;
    const out = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(out);
    _ = try std.base64.standard.Decoder.decode(out, input);
    return out;
}

test "verifyFullFromJson fixture" {
    const allocator = std.testing.allocator;
    const fixture_path = "fixtures/zklogin_fixture.json";
    var fixture = loadZkloginFixtureFromFile(allocator, fixture_path) catch |err| {
        switch (err) {
            error.FileNotFound => return,
            else => return err,
        }
    };
    defer fixture.deinit(allocator);

    if (fixture.jwt_payload_b64.len == 0 or fixture.jwt_signature_b64.len == 0) return;

    try verifyFullFromJson(
        allocator,
        fixture.message,
        fixture.jwt_payload_b64,
        fixture.jwt_signature_b64,
        fixture.jwk_json,
        fixture.inputs_json,
        fixture.signature_json,
        fixture.max_epoch,
        fixture.use_dev_vk,
    );
}

test "zklogin proof fixture" {
    if (!build_options.zklogin_ffi) return;
    const allocator = std.testing.allocator;
    const fixture_path = "fixtures/zklogin_fixture.json";
    var fixture = loadZkloginFixtureFromFile(allocator, fixture_path) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer fixture.deinit(allocator);

    try verifyZkloginProofWithRustJson(
        allocator,
        fixture.jwk_json,
        fixture.inputs_json,
        fixture.signature_json,
        fixture.message,
        fixture.max_epoch,
        fixture.use_dev_vk,
    );
}

fn dupBytes(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, input.len);
    std.mem.copyForwards(u8, out, input);
    return out;
}

fn decodeBase64UrlClaim(allocator: std.mem.Allocator, input: []const u8, index_mod_4: u8) ![]u8 {
    const bits = try base64ToBitArray(allocator, input);
    defer allocator.free(bits);

    var start: usize = 0;
    switch (index_mod_4) {
        0 => {},
        1 => start = 2,
        2 => start = 4,
        else => return error.InvalidZkLoginClaim,
    }

    var end = bits.len;
    const last_char_offset = @as(u8, @intCast((index_mod_4 + @as(u8, @intCast(input.len)) - 1) % 4));
    switch (last_char_offset) {
        3 => {},
        2 => {
            if (end < 2) return error.InvalidZkLoginClaim;
            end -= 2;
        },
        1 => {
            if (end < 4) return error.InvalidZkLoginClaim;
            end -= 4;
        },
        else => return error.InvalidZkLoginClaim,
    }

    if (end < start or ((end - start) % 8) != 0) return error.InvalidZkLoginClaim;
    const trimmed = bits[start..end];
    return bitArrayToBytes(allocator, trimmed);
}

fn base64ToBitArray(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    var list = try std.ArrayList(u8).initCapacity(allocator, input.len * 6);
    errdefer list.deinit(allocator);
    for (input) |c| {
        const index_usize = std.mem.indexOfScalar(u8, charset, c) orelse return error.InvalidZkLoginClaim;
        const index: u8 = @intCast(index_usize);
        var i: u8 = 0;
        while (i < 6) : (i += 1) {
            const bit = @as(u8, @intCast((index >> (5 - i)) & 1));
            try list.append(allocator, bit);
        }
    }
    return list.toOwnedSlice(allocator);
}

fn bitArrayToBytes(allocator: std.mem.Allocator, bits: []const u8) ![]u8 {
    if ((bits.len % 8) != 0) return error.InvalidZkLoginClaim;
    const out = try allocator.alloc(u8, bits.len / 8);
    var i: usize = 0;
    while (i < out.len) : (i += 1) {
        var byte: u8 = 0;
        var j: usize = 0;
        while (j < 8) : (j += 1) {
            const bit = bits[i * 8 + j];
            const shift: u8 = @intCast(7 - j);
            byte |= bit << shift;
        }
        out[i] = byte;
    }
    return out;
}
