const std = @import("std");
const bcs = @import("bcs.zig");
const Address = @import("address.zig").Address;

pub const TypeParseError = error{
    InvalidIdentifier,
    InvalidTypeTag,
    InvalidStructTag,
    InvalidAddress,
    UnexpectedEof,
    TrailingInput,
    AllocationFailed,
};

pub const Identifier = struct {
    bytes: []const u8,
    owned: bool,

    pub fn init(allocator: std.mem.Allocator, input: []const u8) !Identifier {
        if (!isValidIdentifier(input)) return TypeParseError.InvalidIdentifier;
        const copy = try allocator.alloc(u8, input.len);
        std.mem.copyForwards(u8, copy, input);
        return .{ .bytes = copy, .owned = true };
    }

    pub fn fromStatic(input: []const u8) Identifier {
        return .{ .bytes = input, .owned = false };
    }

    pub fn deinit(self: *Identifier, allocator: std.mem.Allocator) void {
        if (self.owned) allocator.free(self.bytes);
        self.* = .{ .bytes = &.{}, .owned = false };
    }

    pub fn asStr(self: Identifier) []const u8 {
        return self.bytes;
    }

    pub fn eql(self: Identifier, other: []const u8) bool {
        return std.mem.eql(u8, self.bytes, other);
    }

    pub fn encodeBcs(self: Identifier, writer: *bcs.Writer) !void {
        try writer.writeBytes(self.bytes);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !Identifier {
        const bytes = try reader.readBytes();
        return Identifier.init(allocator, bytes);
    }

    pub fn format(self: Identifier, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.writeAll(self.bytes);
    }
};

pub const StructTag = struct {
    address: Address,
    module: Identifier,
    name: Identifier,
    type_params: []TypeTag,
    type_params_owned: bool,

    pub fn initOwned(address: Address, module: Identifier, name: Identifier, type_params: []TypeTag) StructTag {
        return .{ .address = address, .module = module, .name = name, .type_params = type_params, .type_params_owned = true };
    }

    pub fn initBorrowed(address: Address, module: Identifier, name: Identifier, type_params: []TypeTag) StructTag {
        return .{ .address = address, .module = module, .name = name, .type_params = type_params, .type_params_owned = false };
    }

    pub fn deinit(self: *StructTag, allocator: std.mem.Allocator) void {
        self.module.deinit(allocator);
        self.name.deinit(allocator);
        for (self.type_params) |*param| {
            param.deinit(allocator);
        }
        if (self.type_params_owned) {
            allocator.free(self.type_params);
        }
        self.* = undefined;
    }

    pub fn addressRef(self: StructTag) Address {
        return self.address;
    }

    pub fn moduleRef(self: StructTag) Identifier {
        return self.module;
    }

    pub fn nameRef(self: StructTag) Identifier {
        return self.name;
    }

    pub fn typeParams(self: StructTag) []TypeTag {
        return self.type_params;
    }

    pub fn isGas(self: StructTag) bool {
        return self.address.bytes == Address.TWO.bytes and self.module.eql("sui") and self.name.eql("SUI") and self.type_params.len == 0;
    }

    pub fn isStakedSui(self: StructTag) bool {
        return self.address.bytes == Address.THREE.bytes and self.module.eql("staking_pool") and self.name.eql("StakedSui") and self.type_params.len == 0;
    }

    pub fn isCoin(self: StructTag) ?TypeTag {
        if (self.address.bytes == Address.TWO.bytes and self.module.eql("coin") and self.name.eql("Coin") and self.type_params.len == 1) {
            return self.type_params[0];
        }
        return null;
    }

    pub fn isBalanceAccumulatorField(self: StructTag) ?TypeTag {
        if (!(self.address.bytes == Address.TWO.bytes and self.module.eql("dynamic_field") and self.name.eql("Field") and self.type_params.len == 2)) {
            return null;
        }
        const key_type = self.type_params[0];
        const u128_type = self.type_params[1];
        if (u128_type != .struct_) return null;
        const u128_struct = u128_type.struct_.*;
        if (!(u128_struct.address.bytes == Address.TWO.bytes and u128_struct.module.eql("accumulator") and u128_struct.name.eql("U128") and u128_struct.type_params.len == 0)) {
            return null;
        }

        if (key_type != .struct_) return null;
        const key_struct = key_type.struct_.*;
        if (!(key_struct.address.bytes == Address.TWO.bytes and key_struct.module.eql("accumulator") and key_struct.name.eql("Key") and key_struct.type_params.len == 1)) {
            return null;
        }

        const balance_type = key_struct.type_params[0];
        if (balance_type != .struct_) return null;
        const balance_struct = balance_type.struct_.*;
        if (!(balance_struct.address.bytes == Address.TWO.bytes and balance_struct.module.eql("balance") and balance_struct.name.eql("Balance") and balance_struct.type_params.len == 1)) {
            return null;
        }
        return balance_struct.type_params[0];
    }

    pub fn gasCoin(allocator: std.mem.Allocator) !StructTag {
        const sui = suiType();
        return coinType(allocator, .{ .struct_ = try boxedStruct(allocator, sui) });
    }

    pub fn stakedSui() StructTag {
        return StructTag.initBorrowed(
            Address.THREE,
            Identifier.fromStatic("staking_pool"),
            Identifier.fromStatic("StakedSui"),
            &.{},
        );
    }

    pub fn suiType() StructTag {
        return StructTag.initBorrowed(
            Address.TWO,
            Identifier.fromStatic("sui"),
            Identifier.fromStatic("SUI"),
            &.{},
        );
    }

    pub fn coinType(allocator: std.mem.Allocator, type_tag: TypeTag) !StructTag {
        var params = try allocator.alloc(TypeTag, 1);
        params[0] = type_tag;
        return StructTag.initOwned(
            Address.TWO,
            Identifier.fromStatic("coin"),
            Identifier.fromStatic("Coin"),
            params,
        );
    }

    pub fn balanceAccumulatorField(allocator: std.mem.Allocator, coin_type: TypeTag) !StructTag {
        var balance_params = try allocator.alloc(TypeTag, 1);
        balance_params[0] = coin_type;
        const balance = StructTag.initOwned(
            Address.TWO,
            Identifier.fromStatic("balance"),
            Identifier.fromStatic("Balance"),
            balance_params,
        );

        var key_params = try allocator.alloc(TypeTag, 1);
        key_params[0] = .{ .struct_ = try boxedStruct(allocator, balance) };
        const key = StructTag.initOwned(
            Address.TWO,
            Identifier.fromStatic("accumulator"),
            Identifier.fromStatic("Key"),
            key_params,
        );

        const u128_struct = StructTag.initBorrowed(
            Address.TWO,
            Identifier.fromStatic("accumulator"),
            Identifier.fromStatic("U128"),
            &.{},
        );

        var field_params = try allocator.alloc(TypeTag, 2);
        field_params[0] = .{ .struct_ = try boxedStruct(allocator, key) };
        field_params[1] = .{ .struct_ = try boxedStruct(allocator, u128_struct) };

        return StructTag.initOwned(
            Address.TWO,
            Identifier.fromStatic("dynamic_field"),
            Identifier.fromStatic("Field"),
            field_params,
        );
    }

    pub fn format(self: StructTag, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        var buffer: [66]u8 = undefined;
        const hex = try self.address.toHexLower(&buffer);
        try writer.writeAll(hex);
        try writer.writeAll("::");
        try writer.writeAll(self.module.asStr());
        try writer.writeAll("::");
        try writer.writeAll(self.name.asStr());
        if (self.type_params.len > 0) {
            try writer.writeAll("<");
            try std.fmt.format(writer, "{}", .{self.type_params[0]});
            var i: usize = 1;
            while (i < self.type_params.len) : (i += 1) {
                try writer.writeAll(", ");
                try std.fmt.format(writer, "{}", .{self.type_params[i]});
            }
            try writer.writeAll(">");
        }
    }

    pub fn encodeBcs(self: StructTag, writer: *bcs.Writer) !void {
        try self.address.encodeBcs(writer);
        try self.module.encodeBcs(writer);
        try self.name.encodeBcs(writer);
        try writer.writeUleb128(self.type_params.len);
        for (self.type_params) |param| {
            try param.encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !StructTag {
        const address = try Address.decodeBcs(reader);
        const module_bytes = try reader.readBytes();
        const name_bytes = try reader.readBytes();

        var module = try Identifier.init(allocator, module_bytes);
        errdefer module.deinit(allocator);
        var name = try Identifier.init(allocator, name_bytes);
        errdefer name.deinit(allocator);

        const len = try reader.readUleb128();
        var params = try allocator.alloc(TypeTag, len);
        errdefer {
            for (params) |*param| {
                param.deinit(allocator);
            }
            allocator.free(params);
        }
        var i: usize = 0;
        while (i < len) : (i += 1) {
            params[i] = try TypeTag.decodeBcs(reader, allocator);
        }

        return StructTag.initOwned(address, module, name, params);
    }
};

pub const TypeTag = union(enum) {
    bool,
    u8,
    u16,
    u32,
    u64,
    u128,
    u256,
    address,
    signer,
    vector: *TypeTag,
    struct_: *StructTag,

    pub fn deinit(self: *TypeTag, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .vector => |inner| {
                inner.deinit(allocator);
                allocator.destroy(inner);
            },
            .struct_ => |inner| {
                inner.deinit(allocator);
                allocator.destroy(inner);
            },
            else => {},
        }
        self.* = undefined;
    }

    pub fn format(self: TypeTag, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            .bool => try writer.writeAll("bool"),
            .u8 => try writer.writeAll("u8"),
            .u16 => try writer.writeAll("u16"),
            .u32 => try writer.writeAll("u32"),
            .u64 => try writer.writeAll("u64"),
            .u128 => try writer.writeAll("u128"),
            .u256 => try writer.writeAll("u256"),
            .address => try writer.writeAll("address"),
            .signer => try writer.writeAll("signer"),
            .vector => |inner| {
                try writer.writeAll("vector<");
                try std.fmt.format(writer, "{}", .{inner.*});
                try writer.writeAll(">");
            },
            .struct_ => |inner| {
                try std.fmt.format(writer, "{}", .{inner.*});
            },
        }
    }

    pub fn encodeBcs(self: TypeTag, writer: *bcs.Writer) !void {
        switch (self) {
            .bool => try writer.writeUleb128(0),
            .u8 => try writer.writeUleb128(1),
            .u64 => try writer.writeUleb128(2),
            .u128 => try writer.writeUleb128(3),
            .address => try writer.writeUleb128(4),
            .signer => try writer.writeUleb128(5),
            .vector => |inner| {
                try writer.writeUleb128(6);
                try inner.encodeBcs(writer);
            },
            .struct_ => |inner| {
                try writer.writeUleb128(7);
                try inner.encodeBcs(writer);
            },
            .u16 => try writer.writeUleb128(8),
            .u32 => try writer.writeUleb128(9),
            .u256 => try writer.writeUleb128(10),
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !TypeTag {
        const variant = try reader.readUleb128();
        switch (variant) {
            0 => return .bool,
            1 => return .u8,
            2 => return .u64,
            3 => return .u128,
            4 => return .address,
            5 => return .signer,
            6 => {
                const inner = try allocator.create(TypeTag);
                errdefer allocator.destroy(inner);
                inner.* = try TypeTag.decodeBcs(reader, allocator);
                return .{ .vector = inner };
            },
            7 => {
                const inner = try allocator.create(StructTag);
                errdefer allocator.destroy(inner);
                inner.* = try StructTag.decodeBcs(reader, allocator);
                return .{ .struct_ = inner };
            },
            8 => return .u16,
            9 => return .u32,
            10 => return .u256,
            else => return TypeParseError.InvalidTypeTag,
        }
    }
};

pub fn parseTypeTag(allocator: std.mem.Allocator, input: []const u8) !TypeTag {
    var parser = Parser.init(input);
    const result = try parser.parseTypeTag(allocator);
    parser.skipSpaces();
    if (!parser.isEof()) return TypeParseError.TrailingInput;
    return result;
}

pub fn parseStructTag(allocator: std.mem.Allocator, input: []const u8) !StructTag {
    var parser = Parser.init(input);
    const result = try parser.parseStructTag(allocator);
    parser.skipSpaces();
    if (!parser.isEof()) return TypeParseError.TrailingInput;
    return result;
}

const Parser = struct {
    input: []const u8,
    index: usize,

    fn init(input: []const u8) Parser {
        return .{ .input = input, .index = 0 };
    }

    fn isEof(self: *Parser) bool {
        return self.index >= self.input.len;
    }

    fn skipSpaces(self: *Parser) void {
        while (!self.isEof()) {
            const c = self.input[self.index];
            if (c == ' ' or c == '\n' or c == '\t' or c == '\r') {
                self.index += 1;
            } else break;
        }
    }

    fn consume(self: *Parser, token: []const u8) bool {
        if (self.index + token.len > self.input.len) return false;
        if (!std.mem.eql(u8, self.input[self.index .. self.index + token.len], token)) return false;
        self.index += token.len;
        return true;
    }

    fn parseIdentifierSlice(self: *Parser) ?[]const u8 {
        if (self.isEof()) return null;
        const start = self.index;
        const first = self.input[self.index];
        if (!isAlpha(first) and first != '_') return null;
        self.index += 1;
        if (first == '_' and (self.isEof() or !isIdentChar(self.input[self.index]))) {
            return null;
        }
        while (!self.isEof() and isIdentChar(self.input[self.index]) and (self.index - start) < 128) {
            self.index += 1;
        }
        const slice = self.input[start..self.index];
        if (!isValidIdentifier(slice)) return null;
        return slice;
    }

    fn parseAddressSlice(self: *Parser) ?[]const u8 {
        if (!self.consume("0x")) return null;
        const start = self.index - 2;
        var count: usize = 0;
        while (!self.isEof() and isHex(self.input[self.index]) and count < 64) {
            self.index += 1;
            count += 1;
        }
        if (count == 0) return null;
        return self.input[start..self.index];
    }

    fn parseTypeTag(self: *Parser, allocator: std.mem.Allocator) !TypeTag {
        self.skipSpaces();

        if (self.consume("u8")) return .u8;
        if (self.consume("u16")) return .u16;
        if (self.consume("u32")) return .u32;
        if (self.consume("u64")) return .u64;
        if (self.consume("u128")) return .u128;
        if (self.consume("u256")) return .u256;
        if (self.consume("bool")) return .bool;
        if (self.consume("address")) return .address;
        if (self.consume("signer")) return .signer;

        if (self.consume("vector<")) {
            const inner = try allocator.create(TypeTag);
            errdefer allocator.destroy(inner);
            inner.* = try self.parseTypeTag(allocator);
            self.skipSpaces();
            if (!self.consume(">")) return TypeParseError.InvalidTypeTag;
            return .{ .vector = inner };
        }

        const struct_tag = try self.parseStructTag(allocator);
        const boxed = try allocator.create(StructTag);
        boxed.* = struct_tag;
        return .{ .struct_ = boxed };
    }

    fn parseStructTag(self: *Parser, allocator: std.mem.Allocator) !StructTag {
        self.skipSpaces();
        const address_slice = self.parseAddressSlice() orelse return TypeParseError.InvalidStructTag;
        const address = Address.parseHexLenient(address_slice) catch return TypeParseError.InvalidAddress;

        if (!self.consume("::")) return TypeParseError.InvalidStructTag;
        const module_slice = self.parseIdentifierSlice() orelse return TypeParseError.InvalidStructTag;
        if (!self.consume("::")) return TypeParseError.InvalidStructTag;
        const name_slice = self.parseIdentifierSlice() orelse return TypeParseError.InvalidStructTag;

        var module = try Identifier.init(allocator, module_slice);
        errdefer module.deinit(allocator);
        var name = try Identifier.init(allocator, name_slice);
        errdefer name.deinit(allocator);

        var params: []TypeTag = &.{};
        self.skipSpaces();
        if (self.consume("<")) {
            var list = std.ArrayList(TypeTag).initCapacity(allocator, 1) catch return TypeParseError.AllocationFailed;
            errdefer {
                for (list.items) |*param| {
                    param.deinit(allocator);
                }
                list.deinit(allocator);
            }

            while (true) {
                const param = try self.parseTypeTag(allocator);
                try list.append(allocator, param);
                self.skipSpaces();
                if (self.consume(">")) break;
                if (!self.consume(",")) return TypeParseError.InvalidStructTag;
            }
            params = try list.toOwnedSlice(allocator);
        }

        return StructTag.initOwned(address, module, name, params);
    }
};

fn boxedStruct(allocator: std.mem.Allocator, value: StructTag) !*StructTag {
    const boxed = try allocator.create(StructTag);
    boxed.* = value;
    return boxed;
}

fn isAlpha(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}

fn isIdentChar(c: u8) bool {
    return isAlpha(c) or (c >= '0' and c <= '9') or c == '_';
}

fn isHex(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

pub fn isValidIdentifier(input: []const u8) bool {
    if (input.len == 0 or input.len > 128) return false;
    const first = input[0];
    if (!isAlpha(first) and first != '_') return false;
    if (first == '_' and input.len == 1) return false;
    var i: usize = 1;
    while (i < input.len) : (i += 1) {
        if (!isIdentChar(input[i])) return false;
    }
    return true;
}

test "type tag bcs fixture" {
    const allocator = std.testing.allocator;
    const display = "0x0000000000000000000000000000000000000000000000000000000000000001::Foo::Bar<bool,u8,u64,u128,address,signer,u16,u32,u256,vector<address>>";

    var type_tag = try parseTypeTag(allocator, display);
    defer type_tag.deinit(allocator);

    var writer = try bcs.Writer.init(allocator);
    defer writer.deinit();
    try type_tag.encodeBcs(&writer);
    const bytes = try writer.toOwnedSlice();
    defer allocator.free(bytes);

    const expected: []const u8 = &[_]u8{
        7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 70, 111, 111, 3, 66, 97, 114, 10, 0, 1, 2, 3, 4, 5, 8, 9, 10, 6, 4,
    };
    try std.testing.expectEqualSlices(u8, expected, bytes);

    var reader = bcs.Reader.init(bytes);
    var decoded = try TypeTag.decodeBcs(&reader, allocator);
    defer decoded.deinit(allocator);
    var buffer: [256]u8 = undefined;
    const rendered = try std.fmt.bufPrint(&buffer, "{}", .{decoded});
    try std.testing.expect(std.mem.eql(u8, display, rendered));
}
