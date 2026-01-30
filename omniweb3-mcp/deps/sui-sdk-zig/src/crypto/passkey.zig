const std = @import("std");
const bcs = @import("../types/bcs.zig");
const signature = @import("signature.zig");
const secp256r1 = @import("secp256r1.zig");
const json = std.json;

pub const PasskeyPublicKey = struct {
    public_key: secp256r1.Secp256r1PublicKey,

    pub fn init(public_key: secp256r1.Secp256r1PublicKey) PasskeyPublicKey {
        return .{ .public_key = public_key };
    }

    pub fn deinit(self: *PasskeyPublicKey, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.* = undefined;
    }

    pub fn encodeBcs(self: PasskeyPublicKey, writer: *bcs.Writer) !void {
        try self.public_key.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !PasskeyPublicKey {
        _ = allocator;
        const public_key = try secp256r1.Secp256r1PublicKey.decodeBcs(reader);
        return .{ .public_key = public_key };
    }
};

pub const PasskeyAuthenticator = struct {
    public_key: secp256r1.Secp256r1PublicKey,
    signature: secp256r1.Secp256r1Signature,
    challenge: []u8,
    authenticator_data: []u8,
    client_data_json: []u8,

    pub fn deinit(self: *PasskeyAuthenticator, allocator: std.mem.Allocator) void {
        allocator.free(self.challenge);
        allocator.free(self.authenticator_data);
        allocator.free(self.client_data_json);
        self.* = undefined;
    }

    pub fn encodeBcs(self: PasskeyAuthenticator, writer: *bcs.Writer) !void {
        const bytes = try self.toBytes(writer.allocator);
        defer writer.allocator.free(bytes);
        try writer.writeBytes(bytes);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !PasskeyAuthenticator {
        const bytes = try reader.readBytes();
        return try PasskeyAuthenticator.fromSerializedBytes(bytes, allocator);
    }

    pub fn toBytes(self: PasskeyAuthenticator, allocator: std.mem.Allocator) ![]u8 {
        var inner = try bcs.Writer.init(allocator);
        defer inner.deinit();

        try inner.writeBytes(self.authenticator_data);
        try inner.writeString(self.client_data_json);
        const simple_sig = signature.SimpleSignature{ .secp256r1 = .{ .signature = self.signature, .public_key = self.public_key } };
        try simple_sig.encodeBcs(&inner);

        const inner_bytes = try inner.toOwnedSlice();
        defer allocator.free(inner_bytes);

        const out = try allocator.alloc(u8, inner_bytes.len + 1);
        out[0] = @intFromEnum(signature.SignatureScheme.passkey);
        std.mem.copyForwards(u8, out[1..], inner_bytes);
        return out;
    }

    pub fn fromSerializedBytes(bytes: []const u8, allocator: std.mem.Allocator) !PasskeyAuthenticator {
        if (bytes.len == 0) return error.InvalidSignature;
        if (bytes[0] != @intFromEnum(signature.SignatureScheme.passkey)) return error.InvalidSignature;

        var inner = bcs.Reader.init(bytes[1..]);
        const authenticator_data = try inner.readBytes();
        const client_data_json = try inner.readString();
        const simple_sig = try signature.SimpleSignature.decodeBcs(&inner);
        return try PasskeyAuthenticator.initFromRaw(
            allocator,
            authenticator_data,
            client_data_json,
            simple_sig,
        );
    }

    pub fn initFromRaw(
        allocator: std.mem.Allocator,
        authenticator_data: []const u8,
        client_data_json: []const u8,
        signature_value: signature.SimpleSignature,
    ) !PasskeyAuthenticator {
        const public_key = switch (signature_value) {
            .secp256r1 => |value| value.public_key,
            else => return error.InvalidSignature,
        };
        const sig = switch (signature_value) {
            .secp256r1 => |value| value.signature,
            else => return error.InvalidSignature,
        };

        const challenge = try parseChallenge(allocator, client_data_json);
        errdefer allocator.free(challenge);

        const authenticator_copy = try dupBytes(allocator, authenticator_data);
        errdefer allocator.free(authenticator_copy);
        const client_copy = try dupBytes(allocator, client_data_json);
        errdefer allocator.free(client_copy);

        return .{
            .public_key = public_key,
            .signature = sig,
            .challenge = challenge,
            .authenticator_data = authenticator_copy,
            .client_data_json = client_copy,
        };
    }

    pub fn verify(self: PasskeyAuthenticator, message: []const u8) !void {
        if (!std.mem.eql(u8, message, self.challenge)) return error.InvalidSignature;

        var signing_input = try std.heap.page_allocator.alloc(u8, self.authenticator_data.len + 32);
        defer std.heap.page_allocator.free(signing_input);

        std.mem.copyForwards(u8, signing_input[0..self.authenticator_data.len], self.authenticator_data);

        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(self.client_data_json);
        var digest: [32]u8 = undefined;
        hasher.final(&digest);
        std.mem.copyForwards(u8, signing_input[self.authenticator_data.len..], &digest);

        try secp256r1.verify(self.signature, signing_input, self.public_key);
    }
};

fn parseChallenge(allocator: std.mem.Allocator, client_data_json: []const u8) ![]u8 {
    const ClientData = struct {
        type: []const u8,
        challenge: []const u8,
        origin: []const u8,
    };

    var parsed = try json.parseFromSlice(ClientData, allocator, client_data_json, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.type, "webauthn.get")) {
        return error.InvalidSignature;
    }
    return decodeBase64Url(allocator, parsed.value.challenge);
}

fn decodeBase64Url(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const decoded_len = std.base64.url_safe_no_pad.Decoder.calcSizeForSlice(input) catch return error.InvalidBase64;
    const out = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(out);
    _ = try std.base64.url_safe_no_pad.Decoder.decode(out, input);
    return out;
}

fn dupBytes(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, input.len);
    std.mem.copyForwards(u8, out, input);
    return out;
}

test "passkey verify and bcs roundtrip" {
    const allocator = std.testing.allocator;
    const private_key: [32]u8 = [_]u8{0x11} ** 32;
    const message = "passkey-challenge";
    const authenticator_data = "auth-data";

    const challenge_len = std.base64.url_safe_no_pad.Encoder.calcSize(message.len);
    var challenge_buf = try allocator.alloc(u8, challenge_len);
    defer allocator.free(challenge_buf);
    _ = std.base64.url_safe_no_pad.Encoder.encode(challenge_buf, message);
    const challenge = challenge_buf[0..challenge_len];

    const client_data_json = try std.fmt.allocPrint(
        allocator,
        "{{\"type\":\"webauthn.get\",\"challenge\":\"{s}\",\"origin\":\"https://example.com\"}}",
        .{challenge},
    );
    defer allocator.free(client_data_json);

    var sign_input = try allocator.alloc(u8, authenticator_data.len + 32);
    defer allocator.free(sign_input);
    std.mem.copyForwards(u8, sign_input[0..authenticator_data.len], authenticator_data);
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(client_data_json);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    std.mem.copyForwards(u8, sign_input[authenticator_data.len..], &digest);

    const signature_bytes = try secp256r1.signDeterministic(private_key, sign_input);
    const public_key = try secp256r1.derivePublicKey(private_key);
    const simple_sig = signature.SimpleSignature{
        .secp256r1 = .{ .signature = signature_bytes, .public_key = public_key },
    };

    var authenticator = try PasskeyAuthenticator.initFromRaw(
        allocator,
        authenticator_data,
        client_data_json,
        simple_sig,
    );
    defer authenticator.deinit(allocator);

    try authenticator.verify(message);

    var writer = try bcs.Writer.init(allocator);
    defer writer.deinit();
    try authenticator.encodeBcs(&writer);
    const encoded = try writer.toOwnedSlice();
    defer allocator.free(encoded);

    var reader = bcs.Reader.init(encoded);
    var decoded = try PasskeyAuthenticator.decodeBcs(&reader, allocator);
    defer decoded.deinit(allocator);
    try decoded.verify(message);
}

fn decodeBase64Std(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(input) catch return error.InvalidBase64;
    const out = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(out);
    _ = try std.base64.standard.Decoder.decode(out, input);
    return out;
}

test "passkey fixture" {
    const allocator = std.testing.allocator;
    const fixture_path = "fixtures/passkey_fixture.json";

    var file = std.fs.cwd().openFile(fixture_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer file.close();
    const contents = try file.readToEndAlloc(allocator, 4096);
    defer allocator.free(contents);

    const Raw = struct {
        message_base64: []const u8,
        passkey_bcs_base64: []const u8,
    };
    var parsed = try json.parseFromSlice(Raw, allocator, contents, .{});
    defer parsed.deinit();

    const message = try decodeBase64Std(allocator, parsed.value.message_base64);
    defer allocator.free(message);
    const passkey_bytes = try decodeBase64Std(allocator, parsed.value.passkey_bcs_base64);
    defer allocator.free(passkey_bytes);

    var reader = bcs.Reader.init(passkey_bytes);
    var authenticator = try PasskeyAuthenticator.decodeBcs(&reader, allocator);
    defer authenticator.deinit(allocator);
    try authenticator.verify(message);
}
