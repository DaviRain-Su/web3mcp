const std = @import("std");
const bcs = @import("bcs.zig");
const Address = @import("address.zig").Address;
const Identifier = @import("type_tag.zig").Identifier;
const StructTag = @import("type_tag.zig").StructTag;
const TypeTag = @import("type_tag.zig").TypeTag;

pub const TransactionEvents = struct {
    events: []Event,

    pub fn deinit(self: *TransactionEvents, allocator: std.mem.Allocator) void {
        for (self.events) |*event| event.deinit(allocator);
        allocator.free(self.events);
        self.* = undefined;
    }

    pub fn encodeBcs(self: TransactionEvents, writer: *bcs.Writer) !void {
        try writer.writeUleb128(self.events.len);
        for (self.events) |event| {
            try event.encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !TransactionEvents {
        const len = try reader.readUleb128();
        var events = try allocator.alloc(Event, len);
        errdefer {
            for (events) |*event| event.deinit(allocator);
            allocator.free(events);
        }
        var i: usize = 0;
        while (i < len) : (i += 1) {
            events[i] = try Event.decodeBcs(reader, allocator);
        }
        return .{ .events = events };
    }
};

pub const Event = struct {
    package_id: Address,
    module: Identifier,
    sender: Address,
    type_: StructTag,
    contents: []u8,

    pub fn deinit(self: *Event, allocator: std.mem.Allocator) void {
        self.module.deinit(allocator);
        self.type_.deinit(allocator);
        allocator.free(self.contents);
        self.* = undefined;
    }

    pub fn encodeBcs(self: Event, writer: *bcs.Writer) !void {
        try self.package_id.encodeBcs(writer);
        try self.module.encodeBcs(writer);
        try self.sender.encodeBcs(writer);
        try self.type_.encodeBcs(writer);
        try writer.writeBytes(self.contents);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !Event {
        const package_id = try Address.decodeBcs(reader);
        var module = try Identifier.decodeBcs(reader, allocator);
        errdefer module.deinit(allocator);
        const sender = try Address.decodeBcs(reader);
        var type_ = try StructTag.decodeBcs(reader, allocator);
        errdefer type_.deinit(allocator);
        const contents = try readOwnedBytes(reader, allocator);
        return .{ .package_id = package_id, .module = module, .sender = sender, .type_ = type_, .contents = contents };
    }
};

pub const BalanceChange = struct {
    address: Address,
    coin_type: TypeTag,
    amount: i128,

    pub fn deinit(self: *BalanceChange, allocator: std.mem.Allocator) void {
        self.coin_type.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: BalanceChange, writer: *bcs.Writer) !void {
        try self.address.encodeBcs(writer);
        try self.coin_type.encodeBcs(writer);
        try writer.writeI128(self.amount);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !BalanceChange {
        const address = try Address.decodeBcs(reader);
        const coin_type = try TypeTag.decodeBcs(reader, allocator);
        const amount = try reader.readI128();
        return .{ .address = address, .coin_type = coin_type, .amount = amount };
    }
};

fn readOwnedBytes(reader: *bcs.Reader, allocator: std.mem.Allocator) ![]u8 {
    const bytes = try reader.readBytes();
    const copy = try allocator.alloc(u8, bytes.len);
    std.mem.copyForwards(u8, copy, bytes);
    return copy;
}
