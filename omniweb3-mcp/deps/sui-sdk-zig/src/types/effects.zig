const std = @import("std");
const bcs = @import("bcs.zig");
const Digest = @import("digest.zig").Digest;
const EpochId = @import("checkpoint.zig").EpochId;
const GasCostSummary = @import("gas.zig").GasCostSummary;
const ExecutionStatus = @import("execution_status.zig").ExecutionStatus;
const Owner = @import("object.zig").Owner;
const Version = @import("object.zig").Version;
const ObjectReference = @import("object.zig").ObjectReference;
const TypeTag = @import("type_tag.zig").TypeTag;
const Address = @import("address.zig").Address;

pub const TransactionEffects = union(enum) {
    v1: TransactionEffectsV1,
    v2: TransactionEffectsV2,

    pub fn deinit(self: *TransactionEffects, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .v1 => |*value| value.deinit(allocator),
            .v2 => |*value| value.deinit(allocator),
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: TransactionEffects, writer: *bcs.Writer) !void {
        switch (self) {
            .v1 => |value| {
                try writer.writeUleb128(0);
                try value.encodeBcs(writer);
            },
            .v2 => |value| {
                try writer.writeUleb128(1);
                try value.encodeBcs(writer);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !TransactionEffects {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .{ .v1 = try TransactionEffectsV1.decodeBcs(reader, allocator) },
            1 => .{ .v2 = try TransactionEffectsV2.decodeBcs(reader, allocator) },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const TransactionEffectsV1 = struct {
    status: ExecutionStatus,
    epoch: EpochId,
    gas_used: GasCostSummary,
    modified_at_versions: []ModifiedAtVersion,
    consensus_objects: []ObjectReference,
    transaction_digest: Digest,
    created: []ObjectReferenceWithOwner,
    mutated: []ObjectReferenceWithOwner,
    unwrapped: []ObjectReferenceWithOwner,
    deleted: []ObjectReference,
    unwrapped_then_deleted: []ObjectReference,
    wrapped: []ObjectReference,
    gas_object: ObjectReferenceWithOwner,
    events_digest: ?Digest,
    dependencies: []Digest,

    pub fn deinit(self: *TransactionEffectsV1, allocator: std.mem.Allocator) void {
        self.status.deinit(allocator);
        allocator.free(self.modified_at_versions);
        allocator.free(self.consensus_objects);
        for (self.created) |*item| item.deinit(allocator);
        allocator.free(self.created);
        for (self.mutated) |*item| item.deinit(allocator);
        allocator.free(self.mutated);
        for (self.unwrapped) |*item| item.deinit(allocator);
        allocator.free(self.unwrapped);
        allocator.free(self.deleted);
        allocator.free(self.unwrapped_then_deleted);
        allocator.free(self.wrapped);
        self.gas_object.deinit(allocator);
        allocator.free(self.dependencies);
        self.* = undefined;
    }

    pub fn encodeBcs(self: TransactionEffectsV1, writer: *bcs.Writer) !void {
        try self.status.encodeBcs(writer);
        try writer.writeU64(self.epoch);
        try self.gas_used.encodeBcs(writer);
        try writer.writeUleb128(self.modified_at_versions.len);
        for (self.modified_at_versions) |item| try item.encodeBcs(writer);
        try writer.writeUleb128(self.consensus_objects.len);
        for (self.consensus_objects) |item| try item.encodeBcs(writer);
        try self.transaction_digest.encodeBcs(writer);
        try writer.writeUleb128(self.created.len);
        for (self.created) |item| try item.encodeBcs(writer);
        try writer.writeUleb128(self.mutated.len);
        for (self.mutated) |item| try item.encodeBcs(writer);
        try writer.writeUleb128(self.unwrapped.len);
        for (self.unwrapped) |item| try item.encodeBcs(writer);
        try writer.writeUleb128(self.deleted.len);
        for (self.deleted) |item| try item.encodeBcs(writer);
        try writer.writeUleb128(self.unwrapped_then_deleted.len);
        for (self.unwrapped_then_deleted) |item| try item.encodeBcs(writer);
        try writer.writeUleb128(self.wrapped.len);
        for (self.wrapped) |item| try item.encodeBcs(writer);
        try self.gas_object.encodeBcs(writer);
        try writeOptionalDigest(writer, self.events_digest);
        try writer.writeUleb128(self.dependencies.len);
        for (self.dependencies) |item| try item.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !TransactionEffectsV1 {
        var status = try ExecutionStatus.decodeBcs(reader, allocator);
        errdefer status.deinit(allocator);
        const epoch = try reader.readU64();
        const gas_used = try GasCostSummary.decodeBcs(reader);
        const modified_at_versions = try readVector0(ModifiedAtVersion, reader, allocator, ModifiedAtVersion.decodeBcs);
        const consensus_objects = try readVector0(ObjectReference, reader, allocator, ObjectReference.decodeBcs);
        const transaction_digest = try Digest.decodeBcs(reader);
        const created = try readVector1(ObjectReferenceWithOwner, reader, allocator, ObjectReferenceWithOwner.decodeBcs);
        const mutated = try readVector1(ObjectReferenceWithOwner, reader, allocator, ObjectReferenceWithOwner.decodeBcs);
        const unwrapped = try readVector1(ObjectReferenceWithOwner, reader, allocator, ObjectReferenceWithOwner.decodeBcs);
        const deleted = try readVector0(ObjectReference, reader, allocator, ObjectReference.decodeBcs);
        const unwrapped_then_deleted = try readVector0(ObjectReference, reader, allocator, ObjectReference.decodeBcs);
        const wrapped = try readVector0(ObjectReference, reader, allocator, ObjectReference.decodeBcs);
        var gas_object = try ObjectReferenceWithOwner.decodeBcs(reader, allocator);
        errdefer gas_object.deinit(allocator);
        const events_digest = try readOptionalDigest(reader);
        const dependencies = try readVector0(Digest, reader, allocator, Digest.decodeBcs);
        return .{
            .status = status,
            .epoch = epoch,
            .gas_used = gas_used,
            .modified_at_versions = modified_at_versions,
            .consensus_objects = consensus_objects,
            .transaction_digest = transaction_digest,
            .created = created,
            .mutated = mutated,
            .unwrapped = unwrapped,
            .deleted = deleted,
            .unwrapped_then_deleted = unwrapped_then_deleted,
            .wrapped = wrapped,
            .gas_object = gas_object,
            .events_digest = events_digest,
            .dependencies = dependencies,
        };
    }
};

pub const ModifiedAtVersion = struct {
    object_id: Address,
    version: Version,

    pub fn encodeBcs(self: ModifiedAtVersion, writer: *bcs.Writer) !void {
        try self.object_id.encodeBcs(writer);
        try writer.writeU64(self.version);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !ModifiedAtVersion {
        return .{ .object_id = try Address.decodeBcs(reader), .version = try reader.readU64() };
    }
};

pub const ObjectReferenceWithOwner = struct {
    reference: ObjectReference,
    owner: Owner,

    pub fn deinit(self: *ObjectReferenceWithOwner, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.* = undefined;
    }

    pub fn encodeBcs(self: ObjectReferenceWithOwner, writer: *bcs.Writer) !void {
        try self.reference.encodeBcs(writer);
        try self.owner.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ObjectReferenceWithOwner {
        _ = allocator;
        return .{ .reference = try ObjectReference.decodeBcs(reader), .owner = try Owner.decodeBcs(reader) };
    }
};

pub const TransactionEffectsV2 = struct {
    status: ExecutionStatus,
    epoch: EpochId,
    gas_used: GasCostSummary,
    transaction_digest: Digest,
    gas_object_index: ?u32,
    events_digest: ?Digest,
    dependencies: []Digest,
    lamport_version: Version,
    changed_objects: []ChangedObject,
    unchanged_consensus_objects: []UnchangedConsensusObject,
    auxiliary_data_digest: ?Digest,

    pub fn deinit(self: *TransactionEffectsV2, allocator: std.mem.Allocator) void {
        self.status.deinit(allocator);
        allocator.free(self.dependencies);
        for (self.changed_objects) |*item| item.deinit(allocator);
        allocator.free(self.changed_objects);
        for (self.unchanged_consensus_objects) |*item| item.deinit(allocator);
        allocator.free(self.unchanged_consensus_objects);
        self.* = undefined;
    }

    pub fn encodeBcs(self: TransactionEffectsV2, writer: *bcs.Writer) !void {
        try self.status.encodeBcs(writer);
        try writer.writeU64(self.epoch);
        try self.gas_used.encodeBcs(writer);
        try self.transaction_digest.encodeBcs(writer);
        try writeOptionalU32(writer, self.gas_object_index);
        try writeOptionalDigest(writer, self.events_digest);
        try writer.writeUleb128(self.dependencies.len);
        for (self.dependencies) |item| try item.encodeBcs(writer);
        try writer.writeU64(self.lamport_version);
        try writer.writeUleb128(self.changed_objects.len);
        for (self.changed_objects) |item| try item.encodeBcs(writer);
        try writer.writeUleb128(self.unchanged_consensus_objects.len);
        for (self.unchanged_consensus_objects) |item| try item.encodeBcs(writer);
        try writeOptionalDigest(writer, self.auxiliary_data_digest);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !TransactionEffectsV2 {
        var status = try ExecutionStatus.decodeBcs(reader, allocator);
        errdefer status.deinit(allocator);
        const epoch = try reader.readU64();
        const gas_used = try GasCostSummary.decodeBcs(reader);
        const transaction_digest = try Digest.decodeBcs(reader);
        const gas_object_index = try readOptionalU32(reader);
        const events_digest = try readOptionalDigest(reader);
        const dependencies = try readVector0(Digest, reader, allocator, Digest.decodeBcs);
        const lamport_version = try reader.readU64();
        const changed_objects = try readVector1(ChangedObject, reader, allocator, ChangedObject.decodeBcs);
        const unchanged_consensus_objects = try readVector1(UnchangedConsensusObject, reader, allocator, UnchangedConsensusObject.decodeBcs);
        const auxiliary_data_digest = try readOptionalDigest(reader);
        return .{
            .status = status,
            .epoch = epoch,
            .gas_used = gas_used,
            .transaction_digest = transaction_digest,
            .gas_object_index = gas_object_index,
            .events_digest = events_digest,
            .dependencies = dependencies,
            .lamport_version = lamport_version,
            .changed_objects = changed_objects,
            .unchanged_consensus_objects = unchanged_consensus_objects,
            .auxiliary_data_digest = auxiliary_data_digest,
        };
    }
};

pub const ChangedObject = struct {
    object_id: Address,
    input_state: ObjectIn,
    output_state: ObjectOut,
    id_operation: IdOperation,

    pub fn deinit(self: *ChangedObject, allocator: std.mem.Allocator) void {
        self.input_state.deinit(allocator);
        self.output_state.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: ChangedObject, writer: *bcs.Writer) !void {
        try self.object_id.encodeBcs(writer);
        try self.input_state.encodeBcs(writer);
        try self.output_state.encodeBcs(writer);
        try self.id_operation.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ChangedObject {
        const object_id = try Address.decodeBcs(reader);
        const input_state = try ObjectIn.decodeBcs(reader, allocator);
        const output_state = try ObjectOut.decodeBcs(reader, allocator);
        const id_operation = try IdOperation.decodeBcs(reader);
        return .{ .object_id = object_id, .input_state = input_state, .output_state = output_state, .id_operation = id_operation };
    }
};

pub const UnchangedConsensusObject = struct {
    object_id: Address,
    kind: UnchangedConsensusKind,

    pub fn deinit(self: *UnchangedConsensusObject, allocator: std.mem.Allocator) void {
        self.kind.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: UnchangedConsensusObject, writer: *bcs.Writer) !void {
        try self.object_id.encodeBcs(writer);
        try self.kind.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !UnchangedConsensusObject {
        _ = allocator;
        const object_id = try Address.decodeBcs(reader);
        const kind = try UnchangedConsensusKind.decodeBcs(reader);
        return .{ .object_id = object_id, .kind = kind };
    }
};

pub const UnchangedConsensusKind = union(enum) {
    read_only_root: struct { version: Version, digest: Digest },
    mutate_deleted: struct { version: Version },
    read_deleted: struct { version: Version },
    canceled: struct { version: Version },
    per_epoch_config,

    pub fn deinit(self: *UnchangedConsensusKind, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.* = undefined;
    }

    pub fn encodeBcs(self: UnchangedConsensusKind, writer: *bcs.Writer) !void {
        switch (self) {
            .read_only_root => |value| {
                try writer.writeUleb128(0);
                try writer.writeU64(value.version);
                try value.digest.encodeBcs(writer);
            },
            .mutate_deleted => |value| {
                try writer.writeUleb128(1);
                try writer.writeU64(value.version);
            },
            .read_deleted => |value| {
                try writer.writeUleb128(2);
                try writer.writeU64(value.version);
            },
            .canceled => |value| {
                try writer.writeUleb128(3);
                try writer.writeU64(value.version);
            },
            .per_epoch_config => try writer.writeUleb128(4),
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader) !UnchangedConsensusKind {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .{ .read_only_root = .{ .version = try reader.readU64(), .digest = try Digest.decodeBcs(reader) } },
            1 => .{ .mutate_deleted = .{ .version = try reader.readU64() } },
            2 => .{ .read_deleted = .{ .version = try reader.readU64() } },
            3 => .{ .canceled = .{ .version = try reader.readU64() } },
            4 => .per_epoch_config,
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const ObjectIn = union(enum) {
    not_exist,
    exist: struct { version: Version, digest: Digest, owner: Owner },

    pub fn deinit(self: *ObjectIn, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.* = undefined;
    }

    pub fn encodeBcs(self: ObjectIn, writer: *bcs.Writer) !void {
        switch (self) {
            .not_exist => try writer.writeUleb128(0),
            .exist => |value| {
                try writer.writeUleb128(1);
                try writer.writeU64(value.version);
                try value.digest.encodeBcs(writer);
                try value.owner.encodeBcs(writer);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ObjectIn {
        _ = allocator;
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .not_exist,
            1 => .{ .exist = .{ .version = try reader.readU64(), .digest = try Digest.decodeBcs(reader), .owner = try Owner.decodeBcs(reader) } },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const ObjectOut = union(enum) {
    not_exist,
    object_write: struct { digest: Digest, owner: Owner },
    package_write: struct { version: Version, digest: Digest },
    accumulator_write: AccumulatorWrite,

    pub fn deinit(self: *ObjectOut, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .accumulator_write => |*value| value.deinit(allocator),
            else => {},
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: ObjectOut, writer: *bcs.Writer) !void {
        switch (self) {
            .not_exist => try writer.writeUleb128(0),
            .object_write => |value| {
                try writer.writeUleb128(1);
                try value.digest.encodeBcs(writer);
                try value.owner.encodeBcs(writer);
            },
            .package_write => |value| {
                try writer.writeUleb128(2);
                try writer.writeU64(value.version);
                try value.digest.encodeBcs(writer);
            },
            .accumulator_write => |value| {
                try writer.writeUleb128(3);
                try value.encodeBcs(writer);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ObjectOut {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .not_exist,
            1 => .{ .object_write = .{ .digest = try Digest.decodeBcs(reader), .owner = try Owner.decodeBcs(reader) } },
            2 => .{ .package_write = .{ .version = try reader.readU64(), .digest = try Digest.decodeBcs(reader) } },
            3 => .{ .accumulator_write = try AccumulatorWrite.decodeBcs(reader, allocator) },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const AccumulatorWrite = struct {
    address: Address,
    type_: TypeTag,
    operation: AccumulatorOperation,
    value: AccumulatorValue,

    pub fn deinit(self: *AccumulatorWrite, allocator: std.mem.Allocator) void {
        self.type_.deinit(allocator);
        self.value.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: AccumulatorWrite, writer: *bcs.Writer) !void {
        try self.address.encodeBcs(writer);
        try self.type_.encodeBcs(writer);
        try self.operation.encodeBcs(writer);
        try self.value.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !AccumulatorWrite {
        const address = try Address.decodeBcs(reader);
        const type_ = try TypeTag.decodeBcs(reader, allocator);
        const operation = try AccumulatorOperation.decodeBcs(reader);
        const value = try AccumulatorValue.decodeBcs(reader);
        return .{ .address = address, .type_ = type_, .operation = operation, .value = value };
    }
};

pub const AccumulatorOperation = enum {
    merge,
    split,

    pub fn encodeBcs(self: AccumulatorOperation, writer: *bcs.Writer) !void {
        try writer.writeUleb128(@intFromEnum(self));
    }

    pub fn decodeBcs(reader: *bcs.Reader) !AccumulatorOperation {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .merge,
            1 => .split,
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const AccumulatorValue = union(enum) {
    integer: u64,

    pub fn deinit(self: *AccumulatorValue, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.* = undefined;
    }

    pub fn encodeBcs(self: AccumulatorValue, writer: *bcs.Writer) !void {
        switch (self) {
            .integer => |value| {
                try writer.writeUleb128(0);
                try writer.writeU64(value);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader) !AccumulatorValue {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .{ .integer = try reader.readU64() },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const IdOperation = enum {
    none,
    created,
    deleted,

    pub fn encodeBcs(self: IdOperation, writer: *bcs.Writer) !void {
        try writer.writeUleb128(@intFromEnum(self));
    }

    pub fn decodeBcs(reader: *bcs.Reader) !IdOperation {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .none,
            1 => .created,
            2 => .deleted,
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

fn writeOptionalDigest(writer: *bcs.Writer, value: ?Digest) !void {
    if (value) |digest| {
        try writer.writeU8(1);
        try digest.encodeBcs(writer);
    } else {
        try writer.writeU8(0);
    }
}

fn readOptionalDigest(reader: *bcs.Reader) !?Digest {
    const tag = try reader.readU8();
    switch (tag) {
        0 => return null,
        1 => return try Digest.decodeBcs(reader),
        else => return bcs.BcsError.InvalidOptionTag,
    }
}

fn writeOptionalU32(writer: *bcs.Writer, value: ?u32) !void {
    if (value) |v| {
        try writer.writeU8(1);
        try writer.writeU32(v);
    } else {
        try writer.writeU8(0);
    }
}

fn readOptionalU32(reader: *bcs.Reader) !?u32 {
    const tag = try reader.readU8();
    switch (tag) {
        0 => return null,
        1 => return try reader.readU32(),
        else => return bcs.BcsError.InvalidOptionTag,
    }
}

fn readVector0(comptime T: type, reader: *bcs.Reader, allocator: std.mem.Allocator, decodeFn: *const fn (*bcs.Reader) anyerror!T) ![]T {
    const len = try reader.readUleb128();
    var items = try allocator.alloc(T, len);
    errdefer allocator.free(items);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        items[i] = try decodeFn(reader);
    }
    return items;
}

fn readVector1(comptime T: type, reader: *bcs.Reader, allocator: std.mem.Allocator, decodeFn: *const fn (*bcs.Reader, std.mem.Allocator) anyerror!T) ![]T {
    const len = try reader.readUleb128();
    var items = try allocator.alloc(T, len);
    errdefer allocator.free(items);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        items[i] = try decodeFn(reader, allocator);
    }
    return items;
}
