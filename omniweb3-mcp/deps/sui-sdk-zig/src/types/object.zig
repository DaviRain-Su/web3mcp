const std = @import("std");
const bcs = @import("bcs.zig");
const Address = @import("address.zig").Address;
const Digest = @import("digest.zig").Digest;
const Identifier = @import("type_tag.zig").Identifier;
const StructTag = @import("type_tag.zig").StructTag;
const TypeTag = @import("type_tag.zig").TypeTag;

pub const Version = u64;

pub const ObjectReference = struct {
    object_id: Address,
    version: Version,
    digest: Digest,

    pub fn init(object_id: Address, version: Version, digest: Digest) ObjectReference {
        return .{ .object_id = object_id, .version = version, .digest = digest };
    }

    pub fn encodeBcs(self: ObjectReference, writer: *bcs.Writer) !void {
        try self.object_id.encodeBcs(writer);
        try writer.writeU64(self.version);
        try self.digest.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !ObjectReference {
        const object_id = try Address.decodeBcs(reader);
        const version = try reader.readU64();
        const digest = try Digest.decodeBcs(reader);
        return .{ .object_id = object_id, .version = version, .digest = digest };
    }
};

pub const Owner = union(enum) {
    address: Address,
    object: Address,
    shared: Version,
    immutable,
    consensus_address: struct { start_version: Version, owner: Address },

    pub fn encodeBcs(self: Owner, writer: *bcs.Writer) !void {
        switch (self) {
            .address => |addr| {
                try writer.writeUleb128(0);
                try addr.encodeBcs(writer);
            },
            .object => |addr| {
                try writer.writeUleb128(1);
                try addr.encodeBcs(writer);
            },
            .shared => |version| {
                try writer.writeUleb128(2);
                try writer.writeU64(version);
            },
            .immutable => {
                try writer.writeUleb128(3);
            },
            .consensus_address => |data| {
                try writer.writeUleb128(4);
                try writer.writeU64(data.start_version);
                try data.owner.encodeBcs(writer);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader) !Owner {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .{ .address = try Address.decodeBcs(reader) },
            1 => .{ .object = try Address.decodeBcs(reader) },
            2 => .{ .shared = try reader.readU64() },
            3 => .immutable,
            4 => .{ .consensus_address = .{ .start_version = try reader.readU64(), .owner = try Address.decodeBcs(reader) } },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const ObjectData = union(enum) {
    struct_: MoveStruct,
    package: MovePackage,

    pub fn deinit(self: *ObjectData, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .struct_ => |*value| value.deinit(allocator),
            .package => |*value| value.deinit(allocator),
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: ObjectData, writer: *bcs.Writer) !void {
        switch (self) {
            .struct_ => |value| {
                try writer.writeUleb128(0);
                try value.encodeBcs(writer);
            },
            .package => |value| {
                try writer.writeUleb128(1);
                try value.encodeBcs(writer);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ObjectData {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .{ .struct_ = try MoveStruct.decodeBcs(reader, allocator) },
            1 => .{ .package = try MovePackage.decodeBcs(reader, allocator) },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const ModuleEntry = struct {
    name: Identifier,
    bytes: []u8,

    pub fn deinit(self: *ModuleEntry, allocator: std.mem.Allocator) void {
        self.name.deinit(allocator);
        allocator.free(self.bytes);
        self.* = undefined;
    }

    pub fn encodeBcs(self: ModuleEntry, writer: *bcs.Writer) !void {
        try self.name.encodeBcs(writer);
        try writer.writeBytes(self.bytes);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ModuleEntry {
        var name = try Identifier.decodeBcs(reader, allocator);
        errdefer name.deinit(allocator);
        const bytes = try reader.readBytes();
        const copy = try allocator.alloc(u8, bytes.len);
        std.mem.copyForwards(u8, copy, bytes);
        return .{ .name = name, .bytes = copy };
    }
};

pub const LinkageEntry = struct {
    address: Address,
    info: UpgradeInfo,

    pub fn encodeBcs(self: LinkageEntry, writer: *bcs.Writer) !void {
        try self.address.encodeBcs(writer);
        try self.info.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !LinkageEntry {
        return .{ .address = try Address.decodeBcs(reader), .info = try UpgradeInfo.decodeBcs(reader) };
    }
};

pub const MovePackage = struct {
    id: Address,
    version: Version,
    modules: []ModuleEntry,
    type_origin_table: []TypeOrigin,
    linkage_table: []LinkageEntry,

    pub fn deinit(self: *MovePackage, allocator: std.mem.Allocator) void {
        for (self.modules) |*entry| {
            entry.deinit(allocator);
        }
        allocator.free(self.modules);

        for (self.type_origin_table) |*entry| {
            entry.deinit(allocator);
        }
        allocator.free(self.type_origin_table);

        allocator.free(self.linkage_table);
        self.* = undefined;
    }

    pub fn encodeBcs(self: MovePackage, writer: *bcs.Writer) !void {
        try self.id.encodeBcs(writer);
        try writer.writeU64(self.version);

        try writer.writeUleb128(self.modules.len);
        for (self.modules) |entry| {
            try entry.encodeBcs(writer);
        }

        try writer.writeUleb128(self.type_origin_table.len);
        for (self.type_origin_table) |entry| {
            try entry.encodeBcs(writer);
        }

        try writer.writeUleb128(self.linkage_table.len);
        for (self.linkage_table) |entry| {
            try entry.encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !MovePackage {
        const id = try Address.decodeBcs(reader);
        const version = try reader.readU64();

        const modules_len = try reader.readUleb128();
        var modules = try allocator.alloc(ModuleEntry, modules_len);
        errdefer {
            for (modules) |*entry| {
                entry.deinit(allocator);
            }
            allocator.free(modules);
        }
        var i: usize = 0;
        while (i < modules_len) : (i += 1) {
            modules[i] = try ModuleEntry.decodeBcs(reader, allocator);
        }

        const origin_len = try reader.readUleb128();
        var origins = try allocator.alloc(TypeOrigin, origin_len);
        errdefer {
            for (origins) |*entry| {
                entry.deinit(allocator);
            }
            allocator.free(origins);
        }
        i = 0;
        while (i < origin_len) : (i += 1) {
            origins[i] = try TypeOrigin.decodeBcs(reader, allocator);
        }

        const linkage_len = try reader.readUleb128();
        var linkage = try allocator.alloc(LinkageEntry, linkage_len);
        errdefer allocator.free(linkage);
        i = 0;
        while (i < linkage_len) : (i += 1) {
            linkage[i] = try LinkageEntry.decodeBcs(reader);
        }

        return .{
            .id = id,
            .version = version,
            .modules = modules,
            .type_origin_table = origins,
            .linkage_table = linkage,
        };
    }
};

pub const TypeOrigin = struct {
    module_name: Identifier,
    struct_name: Identifier,
    package: Address,

    pub fn deinit(self: *TypeOrigin, allocator: std.mem.Allocator) void {
        self.module_name.deinit(allocator);
        self.struct_name.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: TypeOrigin, writer: *bcs.Writer) !void {
        try self.module_name.encodeBcs(writer);
        try self.struct_name.encodeBcs(writer);
        try self.package.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !TypeOrigin {
        var module_name = try Identifier.decodeBcs(reader, allocator);
        errdefer module_name.deinit(allocator);
        var struct_name = try Identifier.decodeBcs(reader, allocator);
        errdefer struct_name.deinit(allocator);
        const package = try Address.decodeBcs(reader);
        return .{ .module_name = module_name, .struct_name = struct_name, .package = package };
    }
};

pub const UpgradeInfo = struct {
    upgraded_id: Address,
    upgraded_version: Version,

    pub fn encodeBcs(self: UpgradeInfo, writer: *bcs.Writer) !void {
        try self.upgraded_id.encodeBcs(writer);
        try writer.writeU64(self.upgraded_version);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !UpgradeInfo {
        return .{ .upgraded_id = try Address.decodeBcs(reader), .upgraded_version = try reader.readU64() };
    }
};

pub const MoveStruct = struct {
    type_: StructTag,
    has_public_transfer: bool,
    version: Version,
    contents: []u8,

    pub fn deinit(self: *MoveStruct, allocator: std.mem.Allocator) void {
        self.type_.deinit(allocator);
        allocator.free(self.contents);
        self.* = undefined;
    }

    pub fn encodeBcs(self: MoveStruct, writer: *bcs.Writer) !void {
        try encodeCompressedStructTag(self.type_, writer);
        try writer.writeBool(self.has_public_transfer);
        try writer.writeU64(self.version);
        try writer.writeBytes(self.contents);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !MoveStruct {
        var type_tag = try decodeCompressedStructTag(reader, allocator);
        errdefer type_tag.deinit(allocator);
        const has_public_transfer = try reader.readBool();
        const version = try reader.readU64();
        const contents = try reader.readBytes();
        const copy = try allocator.alloc(u8, contents.len);
        std.mem.copyForwards(u8, copy, contents);
        return .{ .type_ = type_tag, .has_public_transfer = has_public_transfer, .version = version, .contents = copy };
    }
};

pub const ObjectType = union(enum) {
    package,
    struct_: StructTag,
};

pub const Object = struct {
    data: ObjectData,
    owner: Owner,
    previous_transaction: Digest,
    storage_rebate: u64,

    pub fn deinit(self: *Object, allocator: std.mem.Allocator) void {
        self.data.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: Object, writer: *bcs.Writer) !void {
        try self.data.encodeBcs(writer);
        try self.owner.encodeBcs(writer);
        try self.previous_transaction.encodeBcs(writer);
        try writer.writeU64(self.storage_rebate);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !Object {
        var data = try ObjectData.decodeBcs(reader, allocator);
        errdefer data.deinit(allocator);
        const owner = try Owner.decodeBcs(reader);
        const previous_transaction = try Digest.decodeBcs(reader);
        const storage_rebate = try reader.readU64();
        return .{ .data = data, .owner = owner, .previous_transaction = previous_transaction, .storage_rebate = storage_rebate };
    }
};

pub const GenesisObject = struct {
    data: ObjectData,
    owner: Owner,

    pub fn deinit(self: *GenesisObject, allocator: std.mem.Allocator) void {
        self.data.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: GenesisObject, writer: *bcs.Writer) !void {
        try self.data.encodeBcs(writer);
        try self.owner.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !GenesisObject {
        var data = try ObjectData.decodeBcs(reader, allocator);
        errdefer data.deinit(allocator);
        const owner = try Owner.decodeBcs(reader);
        return .{ .data = data, .owner = owner };
    }
};

fn encodeCompressedStructTag(tag: StructTag, writer: *bcs.Writer) !void {
    if (tag.isGas()) {
        try writer.writeUleb128(1);
        return;
    }
    if (tag.isStakedSui()) {
        try writer.writeUleb128(2);
        return;
    }
    if (tag.isCoin()) |coin_type| {
        try writer.writeUleb128(3);
        try coin_type.encodeBcs(writer);
        return;
    }
    if (tag.isBalanceAccumulatorField()) |coin_type| {
        if (coin_type == .struct_ and coin_type.struct_.*.isGas()) {
            try writer.writeUleb128(4);
            return;
        }
        try writer.writeUleb128(5);
        try coin_type.encodeBcs(writer);
        return;
    }

    try writer.writeUleb128(0);
    try tag.encodeBcs(writer);
}

fn decodeCompressedStructTag(reader: *bcs.Reader, allocator: std.mem.Allocator) !StructTag {
    const variant = try reader.readUleb128();
    return switch (variant) {
        0 => StructTag.decodeBcs(reader, allocator),
        1 => StructTag.gasCoin(allocator),
        2 => StructTag.stakedSui(),
        3 => {
            const coin_type = try TypeTag.decodeBcs(reader, allocator);
            return StructTag.coinType(allocator, coin_type);
        },
        4 => {
            const boxed = try allocator.create(StructTag);
            boxed.* = StructTag.suiType();
            return StructTag.balanceAccumulatorField(allocator, .{ .struct_ = boxed });
        },
        5 => {
            const coin_type = try TypeTag.decodeBcs(reader, allocator);
            return StructTag.balanceAccumulatorField(allocator, coin_type);
        },
        else => return bcs.BcsError.InvalidOptionTag,
    };
}
