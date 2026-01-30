const std = @import("std");
const bcs = @import("bcs.zig");
const Address = @import("address.zig").Address;
const Digest = @import("digest.zig").Digest;
const Identifier = @import("type_tag.zig").Identifier;
const StructTag = @import("type_tag.zig").StructTag;
const TypeTag = @import("type_tag.zig").TypeTag;
const Version = @import("object.zig").Version;
const ObjectReference = @import("object.zig").ObjectReference;
const GenesisObject = @import("object.zig").GenesisObject;
const EpochId = @import("checkpoint.zig").EpochId;
const ProtocolVersion = @import("checkpoint.zig").ProtocolVersion;
const CheckpointTimestamp = @import("checkpoint.zig").CheckpointTimestamp;
const Jwk = @import("zklogin.zig").Jwk;
const JwkId = @import("zklogin.zig").JwkId;
const UserSignature = @import("signature.zig").UserSignature;

pub const Transaction = struct {
    kind: TransactionKind,
    sender: Address,
    gas_payment: GasPayment,
    expiration: TransactionExpiration,

    pub fn deinit(self: *Transaction, allocator: std.mem.Allocator) void {
        self.kind.deinit(allocator);
        self.gas_payment.deinit(allocator);
        self.expiration.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: Transaction, writer: *bcs.Writer) !void {
        try writer.writeUleb128(0);
        try self.kind.encodeBcs(writer);
        try self.sender.encodeBcs(writer);
        try self.gas_payment.encodeBcs(writer);
        try self.expiration.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !Transaction {
        const variant = try reader.readUleb128();
        if (variant != 0) return bcs.BcsError.InvalidOptionTag;
        var kind = try TransactionKind.decodeBcs(reader, allocator);
        errdefer kind.deinit(allocator);
        const sender = try Address.decodeBcs(reader);
        var gas_payment = try GasPayment.decodeBcs(reader, allocator);
        errdefer gas_payment.deinit(allocator);
        var expiration = try TransactionExpiration.decodeBcs(reader, allocator);
        errdefer expiration.deinit(allocator);
        return .{ .kind = kind, .sender = sender, .gas_payment = gas_payment, .expiration = expiration };
    }
};

pub const SignedTransaction = struct {
    transaction: Transaction,
    signatures: []UserSignature,

    pub fn deinit(self: *SignedTransaction, allocator: std.mem.Allocator) void {
        self.transaction.deinit(allocator);
        for (self.signatures) |*sig| {
            sig.deinit(allocator);
        }
        allocator.free(self.signatures);
        self.* = undefined;
    }

    pub fn encodeBcs(self: SignedTransaction, writer: *bcs.Writer) !void {
        try self.transaction.encodeBcs(writer);
        try writer.writeUleb128(self.signatures.len);
        for (self.signatures) |sig| {
            try sig.encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !SignedTransaction {
        var transaction = try Transaction.decodeBcs(reader, allocator);
        errdefer transaction.deinit(allocator);
        const sig_len = try reader.readUleb128();
        var signatures = try allocator.alloc(UserSignature, sig_len);
        errdefer {
            for (signatures) |*sig| {
                sig.deinit(allocator);
            }
            allocator.free(signatures);
        }
        var i: usize = 0;
        while (i < sig_len) : (i += 1) {
            signatures[i] = try UserSignature.decodeBcs(reader, allocator);
        }
        return .{ .transaction = transaction, .signatures = signatures };
    }
};

pub const TransactionExpiration = union(enum) {
    none,
    epoch: EpochId,
    valid_during: ValidDuring,

    pub const ValidDuring = struct {
        min_epoch: ?EpochId,
        max_epoch: ?EpochId,
        min_timestamp: ?u64,
        max_timestamp: ?u64,
        chain: Digest,
        nonce: u32,

        pub fn encodeBcs(self: ValidDuring, writer: *bcs.Writer) !void {
            try writeOptionalU64(writer, self.min_epoch);
            try writeOptionalU64(writer, self.max_epoch);
            try writeOptionalU64(writer, self.min_timestamp);
            try writeOptionalU64(writer, self.max_timestamp);
            try self.chain.encodeBcs(writer);
            try writer.writeU32(self.nonce);
        }

        pub fn decodeBcs(reader: *bcs.Reader) !ValidDuring {
            return .{
                .min_epoch = try readOptionalU64(reader),
                .max_epoch = try readOptionalU64(reader),
                .min_timestamp = try readOptionalU64(reader),
                .max_timestamp = try readOptionalU64(reader),
                .chain = try Digest.decodeBcs(reader),
                .nonce = try reader.readU32(),
            };
        }
    };

    pub fn deinit(self: *TransactionExpiration, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.* = undefined;
    }

    pub fn encodeBcs(self: TransactionExpiration, writer: *bcs.Writer) !void {
        switch (self) {
            .none => try writer.writeUleb128(0),
            .epoch => |epoch| {
                try writer.writeUleb128(1);
                try writer.writeU64(epoch);
            },
            .valid_during => |value| {
                try writer.writeUleb128(2);
                try value.encodeBcs(writer);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !TransactionExpiration {
        _ = allocator;
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .none,
            1 => .{ .epoch = try reader.readU64() },
            2 => .{ .valid_during = try ValidDuring.decodeBcs(reader) },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const GasPayment = struct {
    objects: []ObjectReference,
    owner: Address,
    price: u64,
    budget: u64,

    pub fn deinit(self: *GasPayment, allocator: std.mem.Allocator) void {
        allocator.free(self.objects);
        self.* = undefined;
    }

    pub fn encodeBcs(self: GasPayment, writer: *bcs.Writer) !void {
        try writer.writeUleb128(self.objects.len);
        for (self.objects) |object_ref| {
            try object_ref.encodeBcs(writer);
        }
        try self.owner.encodeBcs(writer);
        try writer.writeU64(self.price);
        try writer.writeU64(self.budget);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !GasPayment {
        const len = try reader.readUleb128();
        var objects = try allocator.alloc(ObjectReference, len);
        errdefer allocator.free(objects);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            objects[i] = try ObjectReference.decodeBcs(reader);
        }
        const owner = try Address.decodeBcs(reader);
        const price = try reader.readU64();
        const budget = try reader.readU64();
        return .{ .objects = objects, .owner = owner, .price = price, .budget = budget };
    }
};

pub const RandomnessStateUpdate = struct {
    epoch: u64,
    randomness_round: u64,
    random_bytes: []u8,
    randomness_obj_initial_shared_version: u64,

    pub fn deinit(self: *RandomnessStateUpdate, allocator: std.mem.Allocator) void {
        allocator.free(self.random_bytes);
        self.* = undefined;
    }

    pub fn encodeBcs(self: RandomnessStateUpdate, writer: *bcs.Writer) !void {
        try writer.writeU64(self.epoch);
        try writer.writeU64(self.randomness_round);
        try writer.writeBytes(self.random_bytes);
        try writer.writeU64(self.randomness_obj_initial_shared_version);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !RandomnessStateUpdate {
        const epoch = try reader.readU64();
        const randomness_round = try reader.readU64();
        const random_bytes = try readOwnedBytes(reader, allocator);
        const version = try reader.readU64();
        return .{ .epoch = epoch, .randomness_round = randomness_round, .random_bytes = random_bytes, .randomness_obj_initial_shared_version = version };
    }
};

pub const TransactionKind = union(enum) {
    programmable_transaction: ProgrammableTransaction,
    change_epoch: ChangeEpoch,
    genesis: GenesisTransaction,
    consensus_commit_prologue: ConsensusCommitPrologue,
    authenticator_state_update: AuthenticatorStateUpdate,
    end_of_epoch: []EndOfEpochTransactionKind,
    randomness_state_update: RandomnessStateUpdate,
    consensus_commit_prologue_v2: ConsensusCommitPrologueV2,
    consensus_commit_prologue_v3: ConsensusCommitPrologueV3,
    consensus_commit_prologue_v4: ConsensusCommitPrologueV4,
    programmable_system_transaction: ProgrammableTransaction,

    pub fn deinit(self: *TransactionKind, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .programmable_transaction => |*value| value.deinit(allocator),
            .change_epoch => |*value| value.deinit(allocator),
            .genesis => |*value| value.deinit(allocator),
            .consensus_commit_prologue => {},
            .authenticator_state_update => |*value| value.deinit(allocator),
            .end_of_epoch => |value| {
                for (value) |*entry| entry.deinit(allocator);
                allocator.free(value);
            },
            .randomness_state_update => |*value| value.deinit(allocator),
            .consensus_commit_prologue_v2 => {},
            .consensus_commit_prologue_v3 => |*value| value.deinit(allocator),
            .consensus_commit_prologue_v4 => |*value| value.deinit(allocator),
            .programmable_system_transaction => |*value| value.deinit(allocator),
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: TransactionKind, writer: *bcs.Writer) !void {
        switch (self) {
            .programmable_transaction => |value| {
                try writer.writeUleb128(0);
                try value.encodeBcs(writer);
            },
            .change_epoch => |value| {
                try writer.writeUleb128(1);
                try value.encodeBcs(writer);
            },
            .genesis => |value| {
                try writer.writeUleb128(2);
                try value.encodeBcs(writer);
            },
            .consensus_commit_prologue => |value| {
                try writer.writeUleb128(3);
                try value.encodeBcs(writer);
            },
            .authenticator_state_update => |value| {
                try writer.writeUleb128(4);
                try value.encodeBcs(writer);
            },
            .end_of_epoch => |value| {
                try writer.writeUleb128(5);
                try writer.writeUleb128(value.len);
                for (value) |entry| {
                    try entry.encodeBcs(writer);
                }
            },
            .randomness_state_update => |value| {
                try writer.writeUleb128(6);
                try value.encodeBcs(writer);
            },
            .consensus_commit_prologue_v2 => |value| {
                try writer.writeUleb128(7);
                try value.encodeBcs(writer);
            },
            .consensus_commit_prologue_v3 => |value| {
                try writer.writeUleb128(8);
                try value.encodeBcs(writer);
            },
            .consensus_commit_prologue_v4 => |value| {
                try writer.writeUleb128(9);
                try value.encodeBcs(writer);
            },
            .programmable_system_transaction => |value| {
                try writer.writeUleb128(10);
                try value.encodeBcs(writer);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !TransactionKind {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .{ .programmable_transaction = try ProgrammableTransaction.decodeBcs(reader, allocator) },
            1 => .{ .change_epoch = try ChangeEpoch.decodeBcs(reader, allocator) },
            2 => .{ .genesis = try GenesisTransaction.decodeBcs(reader, allocator) },
            3 => .{ .consensus_commit_prologue = try ConsensusCommitPrologue.decodeBcs(reader) },
            4 => .{ .authenticator_state_update = try AuthenticatorStateUpdate.decodeBcs(reader, allocator) },
            5 => {
                const len = try reader.readUleb128();
                var entries = try allocator.alloc(EndOfEpochTransactionKind, len);
                errdefer {
                    for (entries) |*entry| entry.deinit(allocator);
                    allocator.free(entries);
                }
                var i: usize = 0;
                while (i < len) : (i += 1) {
                    entries[i] = try EndOfEpochTransactionKind.decodeBcs(reader, allocator);
                }
                return .{ .end_of_epoch = entries };
            },
            6 => .{ .randomness_state_update = try RandomnessStateUpdate.decodeBcs(reader, allocator) },
            7 => .{ .consensus_commit_prologue_v2 = try ConsensusCommitPrologueV2.decodeBcs(reader) },
            8 => .{ .consensus_commit_prologue_v3 = try ConsensusCommitPrologueV3.decodeBcs(reader, allocator) },
            9 => .{ .consensus_commit_prologue_v4 = try ConsensusCommitPrologueV4.decodeBcs(reader, allocator) },
            10 => .{ .programmable_system_transaction = try ProgrammableTransaction.decodeBcs(reader, allocator) },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const EndOfEpochTransactionKind = union(enum) {
    change_epoch: ChangeEpoch,
    authenticator_state_create,
    authenticator_state_expire: AuthenticatorStateExpire,
    randomness_state_create,
    deny_list_state_create,
    bridge_state_create: Digest,
    bridge_committee_init: u64,
    store_execution_time_observations: ExecutionTimeObservations,
    accumulator_root_create,
    coin_registry_create,
    display_registry_create,
    address_alias_state_create,
    write_accumulator_storage_cost: u64,

    pub fn deinit(self: *EndOfEpochTransactionKind, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .change_epoch => |*value| value.deinit(allocator),
            .authenticator_state_expire => {},
            .bridge_state_create => {},
            .store_execution_time_observations => |*value| value.deinit(allocator),
            .write_accumulator_storage_cost => {},
            else => {},
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: EndOfEpochTransactionKind, writer: *bcs.Writer) !void {
        switch (self) {
            .change_epoch => |value| {
                try writer.writeUleb128(0);
                try value.encodeBcs(writer);
            },
            .authenticator_state_create => try writer.writeUleb128(1),
            .authenticator_state_expire => |value| {
                try writer.writeUleb128(2);
                try value.encodeBcs(writer);
            },
            .randomness_state_create => try writer.writeUleb128(3),
            .deny_list_state_create => try writer.writeUleb128(4),
            .bridge_state_create => |digest| {
                try writer.writeUleb128(5);
                try digest.encodeBcs(writer);
            },
            .bridge_committee_init => |version| {
                try writer.writeUleb128(6);
                try writer.writeU64(version);
            },
            .store_execution_time_observations => |value| {
                try writer.writeUleb128(7);
                try value.encodeBcs(writer);
            },
            .accumulator_root_create => try writer.writeUleb128(8),
            .coin_registry_create => try writer.writeUleb128(9),
            .display_registry_create => try writer.writeUleb128(10),
            .address_alias_state_create => try writer.writeUleb128(11),
            .write_accumulator_storage_cost => |storage_cost| {
                try writer.writeUleb128(12);
                try writer.writeU64(storage_cost);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !EndOfEpochTransactionKind {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .{ .change_epoch = try ChangeEpoch.decodeBcs(reader, allocator) },
            1 => .authenticator_state_create,
            2 => .{ .authenticator_state_expire = try AuthenticatorStateExpire.decodeBcs(reader) },
            3 => .randomness_state_create,
            4 => .deny_list_state_create,
            5 => .{ .bridge_state_create = try Digest.decodeBcs(reader) },
            6 => .{ .bridge_committee_init = try reader.readU64() },
            7 => .{ .store_execution_time_observations = try ExecutionTimeObservations.decodeBcs(reader, allocator) },
            8 => .accumulator_root_create,
            9 => .coin_registry_create,
            10 => .display_registry_create,
            11 => .address_alias_state_create,
            12 => .{ .write_accumulator_storage_cost = try reader.readU64() },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const ExecutionTimeObservations = union(enum) {
    v1: []ExecutionTimeObservationEntry,

    pub fn deinit(self: *ExecutionTimeObservations, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .v1 => |entries| {
                for (entries) |*entry| entry.deinit(allocator);
                allocator.free(entries);
            },
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: ExecutionTimeObservations, writer: *bcs.Writer) !void {
        switch (self) {
            .v1 => |entries| {
                try writer.writeUleb128(0);
                try writer.writeUleb128(entries.len);
                for (entries) |entry| {
                    try entry.encodeBcs(writer);
                }
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ExecutionTimeObservations {
        const variant = try reader.readUleb128();
        if (variant != 0) return bcs.BcsError.InvalidOptionTag;
        const len = try reader.readUleb128();
        var entries = try allocator.alloc(ExecutionTimeObservationEntry, len);
        errdefer {
            for (entries) |*entry| entry.deinit(allocator);
            allocator.free(entries);
        }
        var i: usize = 0;
        while (i < len) : (i += 1) {
            entries[i] = try ExecutionTimeObservationEntry.decodeBcs(reader, allocator);
        }
        return .{ .v1 = entries };
    }
};

pub const ExecutionTimeObservationEntry = struct {
    key: ExecutionTimeObservationKey,
    observations: []ValidatorExecutionTimeObservation,

    pub fn deinit(self: *ExecutionTimeObservationEntry, allocator: std.mem.Allocator) void {
        self.key.deinit(allocator);
        for (self.observations) |*obs| {
            obs.deinit(allocator);
        }
        allocator.free(self.observations);
        self.* = undefined;
    }

    pub fn encodeBcs(self: ExecutionTimeObservationEntry, writer: *bcs.Writer) !void {
        try self.key.encodeBcs(writer);
        try writer.writeUleb128(self.observations.len);
        for (self.observations) |obs| {
            try obs.encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ExecutionTimeObservationEntry {
        var key = try ExecutionTimeObservationKey.decodeBcs(reader, allocator);
        errdefer key.deinit(allocator);
        const len = try reader.readUleb128();
        var observations = try allocator.alloc(ValidatorExecutionTimeObservation, len);
        errdefer {
            for (observations) |*obs| obs.deinit(allocator);
            allocator.free(observations);
        }
        var i: usize = 0;
        while (i < len) : (i += 1) {
            observations[i] = try ValidatorExecutionTimeObservation.decodeBcs(reader, allocator);
        }
        return .{ .key = key, .observations = observations };
    }
};

pub const ValidatorExecutionTimeObservation = struct {
    validator: []u8,
    duration_seconds: u64,
    duration_nanos: u32,

    pub fn deinit(self: *ValidatorExecutionTimeObservation, allocator: std.mem.Allocator) void {
        allocator.free(self.validator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: ValidatorExecutionTimeObservation, writer: *bcs.Writer) !void {
        try writer.writeBytes(self.validator);
        try writer.writeU64(self.duration_seconds);
        try writer.writeU32(self.duration_nanos);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ValidatorExecutionTimeObservation {
        const validator = try readOwnedBytes(reader, allocator);
        const seconds = try reader.readU64();
        const nanos = try reader.readU32();
        return .{ .validator = validator, .duration_seconds = seconds, .duration_nanos = nanos };
    }
};

pub const ExecutionTimeObservationKey = union(enum) {
    move_entry_point: struct { package: Address, module: []u8, function: []u8, type_arguments: []TypeTag },
    transfer_objects,
    split_coins,
    merge_coins,
    publish,
    make_move_vec,
    upgrade,

    pub fn deinit(self: *ExecutionTimeObservationKey, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .move_entry_point => |*value| {
                allocator.free(value.module);
                allocator.free(value.function);
                for (value.type_arguments) |*arg| arg.deinit(allocator);
                allocator.free(value.type_arguments);
            },
            else => {},
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: ExecutionTimeObservationKey, writer: *bcs.Writer) !void {
        switch (self) {
            .move_entry_point => |value| {
                try writer.writeUleb128(0);
                try value.package.encodeBcs(writer);
                try writer.writeString(value.module);
                try writer.writeString(value.function);
                try writer.writeUleb128(value.type_arguments.len);
                for (value.type_arguments) |arg| {
                    try arg.encodeBcs(writer);
                }
            },
            .transfer_objects => try writer.writeUleb128(1),
            .split_coins => try writer.writeUleb128(2),
            .merge_coins => try writer.writeUleb128(3),
            .publish => try writer.writeUleb128(4),
            .make_move_vec => try writer.writeUleb128(5),
            .upgrade => try writer.writeUleb128(6),
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ExecutionTimeObservationKey {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => {
                const package = try Address.decodeBcs(reader);
                const module = try readOwnedString(reader, allocator);
                const function = try readOwnedString(reader, allocator);
                const len = try reader.readUleb128();
                var type_arguments = try allocator.alloc(TypeTag, len);
                errdefer {
                    allocator.free(module);
                    allocator.free(function);
                    for (type_arguments) |*arg| arg.deinit(allocator);
                    allocator.free(type_arguments);
                }
                var i: usize = 0;
                while (i < len) : (i += 1) {
                    type_arguments[i] = try TypeTag.decodeBcs(reader, allocator);
                }
                return .{ .move_entry_point = .{ .package = package, .module = module, .function = function, .type_arguments = type_arguments } };
            },
            1 => .transfer_objects,
            2 => .split_coins,
            3 => .merge_coins,
            4 => .publish,
            5 => .make_move_vec,
            6 => .upgrade,
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const AuthenticatorStateExpire = struct {
    min_epoch: u64,
    authenticator_object_initial_shared_version: u64,

    pub fn encodeBcs(self: AuthenticatorStateExpire, writer: *bcs.Writer) !void {
        try writer.writeU64(self.min_epoch);
        try writer.writeU64(self.authenticator_object_initial_shared_version);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !AuthenticatorStateExpire {
        return .{ .min_epoch = try reader.readU64(), .authenticator_object_initial_shared_version = try reader.readU64() };
    }
};

pub const ActiveJwk = struct {
    jwk_id: JwkId,
    jwk: Jwk,
    epoch: u64,

    pub fn deinit(self: *ActiveJwk, allocator: std.mem.Allocator) void {
        self.jwk_id.deinit(allocator);
        self.jwk.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: ActiveJwk, writer: *bcs.Writer) !void {
        try self.jwk_id.encodeBcs(writer);
        try self.jwk.encodeBcs(writer);
        try writer.writeU64(self.epoch);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ActiveJwk {
        var jwk_id = try JwkId.decodeBcs(reader, allocator);
        errdefer jwk_id.deinit(allocator);
        var jwk = try Jwk.decodeBcs(reader, allocator);
        errdefer jwk.deinit(allocator);
        const epoch = try reader.readU64();
        return .{ .jwk_id = jwk_id, .jwk = jwk, .epoch = epoch };
    }
};

pub const AuthenticatorStateUpdate = struct {
    epoch: u64,
    round: u64,
    new_active_jwks: []ActiveJwk,
    authenticator_obj_initial_shared_version: u64,

    pub fn deinit(self: *AuthenticatorStateUpdate, allocator: std.mem.Allocator) void {
        for (self.new_active_jwks) |*jwk| {
            jwk.deinit(allocator);
        }
        allocator.free(self.new_active_jwks);
        self.* = undefined;
    }

    pub fn encodeBcs(self: AuthenticatorStateUpdate, writer: *bcs.Writer) !void {
        try writer.writeU64(self.epoch);
        try writer.writeU64(self.round);
        try writer.writeUleb128(self.new_active_jwks.len);
        for (self.new_active_jwks) |jwk| {
            try jwk.encodeBcs(writer);
        }
        try writer.writeU64(self.authenticator_obj_initial_shared_version);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !AuthenticatorStateUpdate {
        const epoch = try reader.readU64();
        const round = try reader.readU64();
        const len = try reader.readUleb128();
        var jwks = try allocator.alloc(ActiveJwk, len);
        errdefer {
            for (jwks) |*jwk| jwk.deinit(allocator);
            allocator.free(jwks);
        }
        var i: usize = 0;
        while (i < len) : (i += 1) {
            jwks[i] = try ActiveJwk.decodeBcs(reader, allocator);
        }
        const version = try reader.readU64();
        return .{ .epoch = epoch, .round = round, .new_active_jwks = jwks, .authenticator_obj_initial_shared_version = version };
    }
};

pub const ConsensusCommitPrologue = struct {
    epoch: u64,
    round: u64,
    commit_timestamp_ms: CheckpointTimestamp,

    pub fn encodeBcs(self: ConsensusCommitPrologue, writer: *bcs.Writer) !void {
        try writer.writeU64(self.epoch);
        try writer.writeU64(self.round);
        try writer.writeU64(self.commit_timestamp_ms);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !ConsensusCommitPrologue {
        return .{ .epoch = try reader.readU64(), .round = try reader.readU64(), .commit_timestamp_ms = try reader.readU64() };
    }
};

pub const ConsensusCommitPrologueV2 = struct {
    epoch: u64,
    round: u64,
    commit_timestamp_ms: CheckpointTimestamp,
    consensus_commit_digest: Digest,

    pub fn encodeBcs(self: ConsensusCommitPrologueV2, writer: *bcs.Writer) !void {
        try writer.writeU64(self.epoch);
        try writer.writeU64(self.round);
        try writer.writeU64(self.commit_timestamp_ms);
        try self.consensus_commit_digest.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !ConsensusCommitPrologueV2 {
        return .{
            .epoch = try reader.readU64(),
            .round = try reader.readU64(),
            .commit_timestamp_ms = try reader.readU64(),
            .consensus_commit_digest = try Digest.decodeBcs(reader),
        };
    }
};

pub const ConsensusDeterminedVersionAssignments = union(enum) {
    canceled_transactions: []CanceledTransaction,
    canceled_transactions_v2: []CanceledTransactionV2,

    pub fn deinit(self: *ConsensusDeterminedVersionAssignments, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .canceled_transactions => |items| {
                for (items) |*item| item.deinit(allocator);
                allocator.free(items);
            },
            .canceled_transactions_v2 => |items| {
                for (items) |*item| item.deinit(allocator);
                allocator.free(items);
            },
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: ConsensusDeterminedVersionAssignments, writer: *bcs.Writer) !void {
        switch (self) {
            .canceled_transactions => |items| {
                try writer.writeUleb128(0);
                try writer.writeUleb128(items.len);
                for (items) |item| try item.encodeBcs(writer);
            },
            .canceled_transactions_v2 => |items| {
                try writer.writeUleb128(1);
                try writer.writeUleb128(items.len);
                for (items) |item| try item.encodeBcs(writer);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ConsensusDeterminedVersionAssignments {
        const variant = try reader.readUleb128();
        const len = try reader.readUleb128();
        switch (variant) {
            0 => {
                var items = try allocator.alloc(CanceledTransaction, len);
                errdefer {
                    for (items) |*item| item.deinit(allocator);
                    allocator.free(items);
                }
                var i: usize = 0;
                while (i < len) : (i += 1) {
                    items[i] = try CanceledTransaction.decodeBcs(reader, allocator);
                }
                return .{ .canceled_transactions = items };
            },
            1 => {
                var items = try allocator.alloc(CanceledTransactionV2, len);
                errdefer {
                    for (items) |*item| item.deinit(allocator);
                    allocator.free(items);
                }
                var i: usize = 0;
                while (i < len) : (i += 1) {
                    items[i] = try CanceledTransactionV2.decodeBcs(reader, allocator);
                }
                return .{ .canceled_transactions_v2 = items };
            },
            else => return bcs.BcsError.InvalidOptionTag,
        }
    }
};

pub const CanceledTransaction = struct {
    digest: Digest,
    version_assignments: []VersionAssignment,

    pub fn deinit(self: *CanceledTransaction, allocator: std.mem.Allocator) void {
        allocator.free(self.version_assignments);
        self.* = undefined;
    }

    pub fn encodeBcs(self: CanceledTransaction, writer: *bcs.Writer) !void {
        try self.digest.encodeBcs(writer);
        try writer.writeUleb128(self.version_assignments.len);
        for (self.version_assignments) |item| try item.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !CanceledTransaction {
        const digest = try Digest.decodeBcs(reader);
        const len = try reader.readUleb128();
        var items = try allocator.alloc(VersionAssignment, len);
        errdefer allocator.free(items);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            items[i] = try VersionAssignment.decodeBcs(reader);
        }
        return .{ .digest = digest, .version_assignments = items };
    }
};

pub const VersionAssignment = struct {
    object_id: Address,
    version: Version,

    pub fn encodeBcs(self: VersionAssignment, writer: *bcs.Writer) !void {
        try self.object_id.encodeBcs(writer);
        try writer.writeU64(self.version);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !VersionAssignment {
        return .{ .object_id = try Address.decodeBcs(reader), .version = try reader.readU64() };
    }
};

pub const CanceledTransactionV2 = struct {
    digest: Digest,
    version_assignments: []VersionAssignmentV2,

    pub fn deinit(self: *CanceledTransactionV2, allocator: std.mem.Allocator) void {
        allocator.free(self.version_assignments);
        self.* = undefined;
    }

    pub fn encodeBcs(self: CanceledTransactionV2, writer: *bcs.Writer) !void {
        try self.digest.encodeBcs(writer);
        try writer.writeUleb128(self.version_assignments.len);
        for (self.version_assignments) |item| try item.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !CanceledTransactionV2 {
        const digest = try Digest.decodeBcs(reader);
        const len = try reader.readUleb128();
        var items = try allocator.alloc(VersionAssignmentV2, len);
        errdefer allocator.free(items);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            items[i] = try VersionAssignmentV2.decodeBcs(reader);
        }
        return .{ .digest = digest, .version_assignments = items };
    }
};

pub const VersionAssignmentV2 = struct {
    object_id: Address,
    start_version: Version,
    version: Version,

    pub fn encodeBcs(self: VersionAssignmentV2, writer: *bcs.Writer) !void {
        try self.object_id.encodeBcs(writer);
        try writer.writeU64(self.start_version);
        try writer.writeU64(self.version);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !VersionAssignmentV2 {
        return .{ .object_id = try Address.decodeBcs(reader), .start_version = try reader.readU64(), .version = try reader.readU64() };
    }
};

pub const ConsensusCommitPrologueV3 = struct {
    epoch: u64,
    round: u64,
    sub_dag_index: ?u64,
    commit_timestamp_ms: CheckpointTimestamp,
    consensus_commit_digest: Digest,
    consensus_determined_version_assignments: ConsensusDeterminedVersionAssignments,

    pub fn deinit(self: *ConsensusCommitPrologueV3, allocator: std.mem.Allocator) void {
        self.consensus_determined_version_assignments.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: ConsensusCommitPrologueV3, writer: *bcs.Writer) !void {
        try writer.writeU64(self.epoch);
        try writer.writeU64(self.round);
        try writeOptionalU64(writer, self.sub_dag_index);
        try writer.writeU64(self.commit_timestamp_ms);
        try self.consensus_commit_digest.encodeBcs(writer);
        try self.consensus_determined_version_assignments.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ConsensusCommitPrologueV3 {
        const epoch = try reader.readU64();
        const round = try reader.readU64();
        const sub_dag_index = try readOptionalU64(reader);
        const commit_timestamp_ms = try reader.readU64();
        const consensus_commit_digest = try Digest.decodeBcs(reader);
        const assignments = try ConsensusDeterminedVersionAssignments.decodeBcs(reader, allocator);
        return .{
            .epoch = epoch,
            .round = round,
            .sub_dag_index = sub_dag_index,
            .commit_timestamp_ms = commit_timestamp_ms,
            .consensus_commit_digest = consensus_commit_digest,
            .consensus_determined_version_assignments = assignments,
        };
    }
};

pub const ConsensusCommitPrologueV4 = struct {
    epoch: u64,
    round: u64,
    sub_dag_index: ?u64,
    commit_timestamp_ms: CheckpointTimestamp,
    consensus_commit_digest: Digest,
    consensus_determined_version_assignments: ConsensusDeterminedVersionAssignments,
    additional_state_digest: Digest,

    pub fn deinit(self: *ConsensusCommitPrologueV4, allocator: std.mem.Allocator) void {
        self.consensus_determined_version_assignments.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: ConsensusCommitPrologueV4, writer: *bcs.Writer) !void {
        try writer.writeU64(self.epoch);
        try writer.writeU64(self.round);
        try writeOptionalU64(writer, self.sub_dag_index);
        try writer.writeU64(self.commit_timestamp_ms);
        try self.consensus_commit_digest.encodeBcs(writer);
        try self.consensus_determined_version_assignments.encodeBcs(writer);
        try self.additional_state_digest.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ConsensusCommitPrologueV4 {
        const epoch = try reader.readU64();
        const round = try reader.readU64();
        const sub_dag_index = try readOptionalU64(reader);
        const commit_timestamp_ms = try reader.readU64();
        const consensus_commit_digest = try Digest.decodeBcs(reader);
        const assignments = try ConsensusDeterminedVersionAssignments.decodeBcs(reader, allocator);
        const additional_state_digest = try Digest.decodeBcs(reader);
        return .{
            .epoch = epoch,
            .round = round,
            .sub_dag_index = sub_dag_index,
            .commit_timestamp_ms = commit_timestamp_ms,
            .consensus_commit_digest = consensus_commit_digest,
            .consensus_determined_version_assignments = assignments,
            .additional_state_digest = additional_state_digest,
        };
    }
};

pub const ChangeEpoch = struct {
    epoch: EpochId,
    protocol_version: ProtocolVersion,
    storage_charge: u64,
    computation_charge: u64,
    storage_rebate: u64,
    non_refundable_storage_fee: u64,
    epoch_start_timestamp_ms: u64,
    system_packages: []SystemPackage,

    pub fn deinit(self: *ChangeEpoch, allocator: std.mem.Allocator) void {
        for (self.system_packages) |*package| package.deinit(allocator);
        allocator.free(self.system_packages);
        self.* = undefined;
    }

    pub fn encodeBcs(self: ChangeEpoch, writer: *bcs.Writer) !void {
        try writer.writeU64(self.epoch);
        try writer.writeU64(self.protocol_version);
        try writer.writeU64(self.storage_charge);
        try writer.writeU64(self.computation_charge);
        try writer.writeU64(self.storage_rebate);
        try writer.writeU64(self.non_refundable_storage_fee);
        try writer.writeU64(self.epoch_start_timestamp_ms);
        try writer.writeUleb128(self.system_packages.len);
        for (self.system_packages) |package| {
            try package.encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ChangeEpoch {
        const epoch = try reader.readU64();
        const protocol_version = try reader.readU64();
        const storage_charge = try reader.readU64();
        const computation_charge = try reader.readU64();
        const storage_rebate = try reader.readU64();
        const non_refundable_storage_fee = try reader.readU64();
        const epoch_start_timestamp_ms = try reader.readU64();
        const len = try reader.readUleb128();
        var packages = try allocator.alloc(SystemPackage, len);
        errdefer {
            for (packages) |*package| package.deinit(allocator);
            allocator.free(packages);
        }
        var i: usize = 0;
        while (i < len) : (i += 1) {
            packages[i] = try SystemPackage.decodeBcs(reader, allocator);
        }
        return .{
            .epoch = epoch,
            .protocol_version = protocol_version,
            .storage_charge = storage_charge,
            .computation_charge = computation_charge,
            .storage_rebate = storage_rebate,
            .non_refundable_storage_fee = non_refundable_storage_fee,
            .epoch_start_timestamp_ms = epoch_start_timestamp_ms,
            .system_packages = packages,
        };
    }
};

pub const SystemPackage = struct {
    version: Version,
    modules: [][]u8,
    dependencies: []Address,

    pub fn deinit(self: *SystemPackage, allocator: std.mem.Allocator) void {
        for (self.modules) |module| allocator.free(module);
        allocator.free(self.modules);
        allocator.free(self.dependencies);
        self.* = undefined;
    }

    pub fn encodeBcs(self: SystemPackage, writer: *bcs.Writer) !void {
        try writer.writeU64(self.version);
        try writer.writeUleb128(self.modules.len);
        for (self.modules) |module| {
            try writer.writeBytes(module);
        }
        try writer.writeUleb128(self.dependencies.len);
        for (self.dependencies) |dep| {
            try dep.encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !SystemPackage {
        const version = try reader.readU64();
        const modules_len = try reader.readUleb128();
        var modules = try allocator.alloc([]u8, modules_len);
        errdefer {
            for (modules) |module| allocator.free(module);
            allocator.free(modules);
        }
        var i: usize = 0;
        while (i < modules_len) : (i += 1) {
            modules[i] = try readOwnedBytes(reader, allocator);
        }
        const deps_len = try reader.readUleb128();
        var dependencies = try allocator.alloc(Address, deps_len);
        errdefer allocator.free(dependencies);
        i = 0;
        while (i < deps_len) : (i += 1) {
            dependencies[i] = try Address.decodeBcs(reader);
        }
        return .{ .version = version, .modules = modules, .dependencies = dependencies };
    }
};

pub const GenesisTransaction = struct {
    objects: []GenesisObject,

    pub fn deinit(self: *GenesisTransaction, allocator: std.mem.Allocator) void {
        for (self.objects) |*obj| obj.deinit(allocator);
        allocator.free(self.objects);
        self.* = undefined;
    }

    pub fn encodeBcs(self: GenesisTransaction, writer: *bcs.Writer) !void {
        try writer.writeUleb128(self.objects.len);
        for (self.objects) |obj| {
            try obj.encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !GenesisTransaction {
        const len = try reader.readUleb128();
        var objects = try allocator.alloc(GenesisObject, len);
        errdefer {
            for (objects) |*obj| obj.deinit(allocator);
            allocator.free(objects);
        }
        var i: usize = 0;
        while (i < len) : (i += 1) {
            objects[i] = try GenesisObject.decodeBcs(reader, allocator);
        }
        return .{ .objects = objects };
    }
};

pub const ProgrammableTransaction = struct {
    inputs: []Input,
    commands: []Command,

    pub fn deinit(self: *ProgrammableTransaction, allocator: std.mem.Allocator) void {
        for (self.inputs) |*input| input.deinit(allocator);
        allocator.free(self.inputs);
        for (self.commands) |*command| command.deinit(allocator);
        allocator.free(self.commands);
        self.* = undefined;
    }

    pub fn encodeBcs(self: ProgrammableTransaction, writer: *bcs.Writer) !void {
        try writer.writeUleb128(self.inputs.len);
        for (self.inputs) |input| {
            try input.encodeBcs(writer);
        }
        try writer.writeUleb128(self.commands.len);
        for (self.commands) |command| {
            try command.encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ProgrammableTransaction {
        const input_len = try reader.readUleb128();
        var inputs = try allocator.alloc(Input, input_len);
        errdefer {
            for (inputs) |*input| input.deinit(allocator);
            allocator.free(inputs);
        }
        var i: usize = 0;
        while (i < input_len) : (i += 1) {
            inputs[i] = try Input.decodeBcs(reader, allocator);
        }
        const cmd_len = try reader.readUleb128();
        var commands = try allocator.alloc(Command, cmd_len);
        errdefer {
            for (commands) |*cmd| cmd.deinit(allocator);
            allocator.free(commands);
        }
        i = 0;
        while (i < cmd_len) : (i += 1) {
            commands[i] = try Command.decodeBcs(reader, allocator);
        }
        return .{ .inputs = inputs, .commands = commands };
    }
};

pub const Input = union(enum) {
    pure: []u8,
    immutable_or_owned: ObjectReference,
    shared: SharedInput,
    receiving: ObjectReference,
    funds_withdrawal: FundsWithdrawal,

    pub fn deinit(self: *Input, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .pure => |bytes| allocator.free(bytes),
            .shared => {},
            .funds_withdrawal => |*value| value.deinit(allocator),
            else => {},
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: Input, writer: *bcs.Writer) !void {
        switch (self) {
            .pure => |bytes| {
                try writer.writeUleb128(0);
                try writer.writeBytes(bytes);
            },
            .immutable_or_owned => |object_ref| {
                try writer.writeUleb128(1);
                try object_ref.encodeBcs(writer);
            },
            .shared => |shared| {
                try writer.writeUleb128(2);
                try shared.encodeBcs(writer);
            },
            .receiving => |object_ref| {
                try writer.writeUleb128(3);
                try object_ref.encodeBcs(writer);
            },
            .funds_withdrawal => |value| {
                try writer.writeUleb128(4);
                try value.encodeBcs(writer);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !Input {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .{ .pure = try readOwnedBytes(reader, allocator) },
            1 => .{ .immutable_or_owned = try ObjectReference.decodeBcs(reader) },
            2 => .{ .shared = try SharedInput.decodeBcs(reader) },
            3 => .{ .receiving = try ObjectReference.decodeBcs(reader) },
            4 => .{ .funds_withdrawal = try FundsWithdrawal.decodeBcs(reader, allocator) },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const SharedInput = struct {
    object_id: Address,
    version: u64,
    mutability: Mutability,

    pub fn encodeBcs(self: SharedInput, writer: *bcs.Writer) !void {
        try self.object_id.encodeBcs(writer);
        try writer.writeU64(self.version);
        try self.mutability.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !SharedInput {
        const object_id = try Address.decodeBcs(reader);
        const version = try reader.readU64();
        const mutability = try Mutability.decodeBcs(reader);
        return .{ .object_id = object_id, .version = version, .mutability = mutability };
    }
};

pub const Mutability = enum {
    immutable,
    mutable,
    non_exclusive_write,

    pub fn encodeBcs(self: Mutability, writer: *bcs.Writer) !void {
        const variant: u64 = switch (self) {
            .immutable => 0,
            .mutable => 1,
            .non_exclusive_write => 2,
        };
        try writer.writeUleb128(variant);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !Mutability {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .immutable,
            1 => .mutable,
            2 => .non_exclusive_write,
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const FundsWithdrawal = struct {
    reservation: Reservation,
    type_: WithdrawalType,
    source: WithdrawFrom,

    pub fn deinit(self: *FundsWithdrawal, allocator: std.mem.Allocator) void {
        self.type_.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: FundsWithdrawal, writer: *bcs.Writer) !void {
        try self.reservation.encodeBcs(writer);
        try self.type_.encodeBcs(writer);
        try self.source.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !FundsWithdrawal {
        const reservation = try Reservation.decodeBcs(reader);
        const type_ = try WithdrawalType.decodeBcs(reader, allocator);
        const source = try WithdrawFrom.decodeBcs(reader);
        return .{ .reservation = reservation, .type_ = type_, .source = source };
    }
};

pub const WithdrawFrom = enum {
    sender,
    sponsor,

    pub fn encodeBcs(self: WithdrawFrom, writer: *bcs.Writer) !void {
        const variant: u64 = switch (self) {
            .sender => 0,
            .sponsor => 1,
        };
        try writer.writeUleb128(variant);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !WithdrawFrom {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .sender,
            1 => .sponsor,
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const Reservation = union(enum) {
    amount: u64,

    pub fn encodeBcs(self: Reservation, writer: *bcs.Writer) !void {
        switch (self) {
            .amount => |value| {
                try writer.writeUleb128(0);
                try writer.writeU64(value);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader) !Reservation {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .{ .amount = try reader.readU64() },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const WithdrawalType = union(enum) {
    balance: TypeTag,

    pub fn deinit(self: *WithdrawalType, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .balance => |*value| value.deinit(allocator),
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: WithdrawalType, writer: *bcs.Writer) !void {
        switch (self) {
            .balance => |value| {
                try writer.writeUleb128(0);
                try value.encodeBcs(writer);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !WithdrawalType {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .{ .balance = try TypeTag.decodeBcs(reader, allocator) },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const Command = union(enum) {
    move_call: MoveCall,
    transfer_objects: TransferObjects,
    split_coins: SplitCoins,
    merge_coins: MergeCoins,
    publish: Publish,
    make_move_vector: MakeMoveVector,
    upgrade: Upgrade,

    pub fn deinit(self: *Command, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .move_call => |*value| value.deinit(allocator),
            .transfer_objects => |*value| value.deinit(allocator),
            .split_coins => |*value| value.deinit(allocator),
            .merge_coins => |*value| value.deinit(allocator),
            .publish => |*value| value.deinit(allocator),
            .make_move_vector => |*value| value.deinit(allocator),
            .upgrade => |*value| value.deinit(allocator),
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: Command, writer: *bcs.Writer) !void {
        switch (self) {
            .move_call => |value| {
                try writer.writeUleb128(0);
                try value.encodeBcs(writer);
            },
            .transfer_objects => |value| {
                try writer.writeUleb128(1);
                try value.encodeBcs(writer);
            },
            .split_coins => |value| {
                try writer.writeUleb128(2);
                try value.encodeBcs(writer);
            },
            .merge_coins => |value| {
                try writer.writeUleb128(3);
                try value.encodeBcs(writer);
            },
            .publish => |value| {
                try writer.writeUleb128(4);
                try value.encodeBcs(writer);
            },
            .make_move_vector => |value| {
                try writer.writeUleb128(5);
                try value.encodeBcs(writer);
            },
            .upgrade => |value| {
                try writer.writeUleb128(6);
                try value.encodeBcs(writer);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !Command {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .{ .move_call = try MoveCall.decodeBcs(reader, allocator) },
            1 => .{ .transfer_objects = try TransferObjects.decodeBcs(reader, allocator) },
            2 => .{ .split_coins = try SplitCoins.decodeBcs(reader, allocator) },
            3 => .{ .merge_coins = try MergeCoins.decodeBcs(reader, allocator) },
            4 => .{ .publish = try Publish.decodeBcs(reader, allocator) },
            5 => .{ .make_move_vector = try MakeMoveVector.decodeBcs(reader, allocator) },
            6 => .{ .upgrade = try Upgrade.decodeBcs(reader, allocator) },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const TransferObjects = struct {
    objects: []Argument,
    address: Argument,

    pub fn deinit(self: *TransferObjects, allocator: std.mem.Allocator) void {
        allocator.free(self.objects);
        self.* = undefined;
    }

    pub fn encodeBcs(self: TransferObjects, writer: *bcs.Writer) !void {
        try writer.writeUleb128(self.objects.len);
        for (self.objects) |arg| {
            try arg.encodeBcs(writer);
        }
        try self.address.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !TransferObjects {
        const len = try reader.readUleb128();
        var objects = try allocator.alloc(Argument, len);
        errdefer allocator.free(objects);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            objects[i] = try Argument.decodeBcs(reader);
        }
        const address = try Argument.decodeBcs(reader);
        return .{ .objects = objects, .address = address };
    }
};

pub const SplitCoins = struct {
    coin: Argument,
    amounts: []Argument,

    pub fn deinit(self: *SplitCoins, allocator: std.mem.Allocator) void {
        allocator.free(self.amounts);
        self.* = undefined;
    }

    pub fn encodeBcs(self: SplitCoins, writer: *bcs.Writer) !void {
        try self.coin.encodeBcs(writer);
        try writer.writeUleb128(self.amounts.len);
        for (self.amounts) |arg| {
            try arg.encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !SplitCoins {
        const coin = try Argument.decodeBcs(reader);
        const len = try reader.readUleb128();
        var amounts = try allocator.alloc(Argument, len);
        errdefer allocator.free(amounts);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            amounts[i] = try Argument.decodeBcs(reader);
        }
        return .{ .coin = coin, .amounts = amounts };
    }
};

pub const MergeCoins = struct {
    coin: Argument,
    coins_to_merge: []Argument,

    pub fn deinit(self: *MergeCoins, allocator: std.mem.Allocator) void {
        allocator.free(self.coins_to_merge);
        self.* = undefined;
    }

    pub fn encodeBcs(self: MergeCoins, writer: *bcs.Writer) !void {
        try self.coin.encodeBcs(writer);
        try writer.writeUleb128(self.coins_to_merge.len);
        for (self.coins_to_merge) |arg| {
            try arg.encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !MergeCoins {
        const coin = try Argument.decodeBcs(reader);
        const len = try reader.readUleb128();
        var coins = try allocator.alloc(Argument, len);
        errdefer allocator.free(coins);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            coins[i] = try Argument.decodeBcs(reader);
        }
        return .{ .coin = coin, .coins_to_merge = coins };
    }
};

pub const Publish = struct {
    modules: [][]u8,
    dependencies: []Address,

    pub fn deinit(self: *Publish, allocator: std.mem.Allocator) void {
        for (self.modules) |module| allocator.free(module);
        allocator.free(self.modules);
        allocator.free(self.dependencies);
        self.* = undefined;
    }

    pub fn encodeBcs(self: Publish, writer: *bcs.Writer) !void {
        try writer.writeUleb128(self.modules.len);
        for (self.modules) |module| {
            try writer.writeBytes(module);
        }
        try writer.writeUleb128(self.dependencies.len);
        for (self.dependencies) |dep| {
            try dep.encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !Publish {
        const modules_len = try reader.readUleb128();
        var modules = try allocator.alloc([]u8, modules_len);
        errdefer {
            for (modules) |module| allocator.free(module);
            allocator.free(modules);
        }
        var i: usize = 0;
        while (i < modules_len) : (i += 1) {
            modules[i] = try readOwnedBytes(reader, allocator);
        }
        const deps_len = try reader.readUleb128();
        var dependencies = try allocator.alloc(Address, deps_len);
        errdefer allocator.free(dependencies);
        i = 0;
        while (i < deps_len) : (i += 1) {
            dependencies[i] = try Address.decodeBcs(reader);
        }
        return .{ .modules = modules, .dependencies = dependencies };
    }
};

pub const MakeMoveVector = struct {
    type_: ?TypeTag,
    elements: []Argument,

    pub fn deinit(self: *MakeMoveVector, allocator: std.mem.Allocator) void {
        if (self.type_) |*value| value.deinit(allocator);
        allocator.free(self.elements);
        self.* = undefined;
    }

    pub fn encodeBcs(self: MakeMoveVector, writer: *bcs.Writer) !void {
        if (self.type_) |value| {
            try writer.writeU8(1);
            try value.encodeBcs(writer);
        } else {
            try writer.writeU8(0);
        }
        try writer.writeUleb128(self.elements.len);
        for (self.elements) |arg| {
            try arg.encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !MakeMoveVector {
        const tag = try reader.readU8();
        var type_value: ?TypeTag = null;
        if (tag == 1) {
            type_value = try TypeTag.decodeBcs(reader, allocator);
        } else if (tag != 0) {
            return bcs.BcsError.InvalidOptionTag;
        }
        const len = try reader.readUleb128();
        var elements = try allocator.alloc(Argument, len);
        errdefer allocator.free(elements);
        var i: usize = 0;
        while (i < len) : (i += 1) {
            elements[i] = try Argument.decodeBcs(reader);
        }
        return .{ .type_ = type_value, .elements = elements };
    }
};

pub const Upgrade = struct {
    modules: [][]u8,
    dependencies: []Address,
    package: Address,
    ticket: Argument,

    pub fn deinit(self: *Upgrade, allocator: std.mem.Allocator) void {
        for (self.modules) |module| allocator.free(module);
        allocator.free(self.modules);
        allocator.free(self.dependencies);
        self.* = undefined;
    }

    pub fn encodeBcs(self: Upgrade, writer: *bcs.Writer) !void {
        try writer.writeUleb128(self.modules.len);
        for (self.modules) |module| {
            try writer.writeBytes(module);
        }
        try writer.writeUleb128(self.dependencies.len);
        for (self.dependencies) |dep| {
            try dep.encodeBcs(writer);
        }
        try self.package.encodeBcs(writer);
        try self.ticket.encodeBcs(writer);
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !Upgrade {
        const modules_len = try reader.readUleb128();
        var modules = try allocator.alloc([]u8, modules_len);
        errdefer {
            for (modules) |module| allocator.free(module);
            allocator.free(modules);
        }
        var i: usize = 0;
        while (i < modules_len) : (i += 1) {
            modules[i] = try readOwnedBytes(reader, allocator);
        }
        const deps_len = try reader.readUleb128();
        var dependencies = try allocator.alloc(Address, deps_len);
        errdefer allocator.free(dependencies);
        i = 0;
        while (i < deps_len) : (i += 1) {
            dependencies[i] = try Address.decodeBcs(reader);
        }
        const package = try Address.decodeBcs(reader);
        const ticket = try Argument.decodeBcs(reader);
        return .{ .modules = modules, .dependencies = dependencies, .package = package, .ticket = ticket };
    }
};

pub const Argument = union(enum) {
    gas,
    input: u16,
    result: u16,
    nested_result: struct { result: u16, index: u16 },

    pub fn encodeBcs(self: Argument, writer: *bcs.Writer) !void {
        switch (self) {
            .gas => try writer.writeUleb128(0),
            .input => |value| {
                try writer.writeUleb128(1);
                try writer.writeU16(value);
            },
            .result => |value| {
                try writer.writeUleb128(2);
                try writer.writeU16(value);
            },
            .nested_result => |value| {
                try writer.writeUleb128(3);
                try writer.writeU16(value.result);
                try writer.writeU16(value.index);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader) !Argument {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .gas,
            1 => .{ .input = try reader.readU16() },
            2 => .{ .result = try reader.readU16() },
            3 => .{ .nested_result = .{ .result = try reader.readU16(), .index = try reader.readU16() } },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const MoveCall = struct {
    package: Address,
    module: Identifier,
    function: Identifier,
    type_arguments: []TypeTag,
    arguments: []Argument,

    pub fn deinit(self: *MoveCall, allocator: std.mem.Allocator) void {
        self.module.deinit(allocator);
        self.function.deinit(allocator);
        for (self.type_arguments) |*arg| arg.deinit(allocator);
        allocator.free(self.type_arguments);
        allocator.free(self.arguments);
        self.* = undefined;
    }

    pub fn encodeBcs(self: MoveCall, writer: *bcs.Writer) !void {
        try self.package.encodeBcs(writer);
        try self.module.encodeBcs(writer);
        try self.function.encodeBcs(writer);
        try writer.writeUleb128(self.type_arguments.len);
        for (self.type_arguments) |arg| {
            try arg.encodeBcs(writer);
        }
        try writer.writeUleb128(self.arguments.len);
        for (self.arguments) |arg| {
            try arg.encodeBcs(writer);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !MoveCall {
        const package = try Address.decodeBcs(reader);
        var module = try Identifier.decodeBcs(reader, allocator);
        errdefer module.deinit(allocator);
        var function = try Identifier.decodeBcs(reader, allocator);
        errdefer function.deinit(allocator);

        const ty_len = try reader.readUleb128();
        var type_arguments = try allocator.alloc(TypeTag, ty_len);
        errdefer {
            for (type_arguments) |*arg| arg.deinit(allocator);
            allocator.free(type_arguments);
        }
        var i: usize = 0;
        while (i < ty_len) : (i += 1) {
            type_arguments[i] = try TypeTag.decodeBcs(reader, allocator);
        }

        const arg_len = try reader.readUleb128();
        var arguments = try allocator.alloc(Argument, arg_len);
        errdefer allocator.free(arguments);
        i = 0;
        while (i < arg_len) : (i += 1) {
            arguments[i] = try Argument.decodeBcs(reader);
        }

        return .{
            .package = package,
            .module = module,
            .function = function,
            .type_arguments = type_arguments,
            .arguments = arguments,
        };
    }
};

fn readOwnedBytes(reader: *bcs.Reader, allocator: std.mem.Allocator) ![]u8 {
    const bytes = try reader.readBytes();
    const copy = try allocator.alloc(u8, bytes.len);
    std.mem.copyForwards(u8, copy, bytes);
    return copy;
}

fn readOwnedString(reader: *bcs.Reader, allocator: std.mem.Allocator) ![]u8 {
    const bytes = try reader.readString();
    const copy = try allocator.alloc(u8, bytes.len);
    std.mem.copyForwards(u8, copy, bytes);
    return copy;
}

fn writeOptionalU64(writer: *bcs.Writer, value: ?u64) !void {
    if (value) |v| {
        try writer.writeU8(1);
        try writer.writeU64(v);
    } else {
        try writer.writeU8(0);
    }
}

fn readOptionalU64(reader: *bcs.Reader) !?u64 {
    const tag = try reader.readU8();
    switch (tag) {
        0 => return null,
        1 => return try reader.readU64(),
        else => return bcs.BcsError.InvalidOptionTag,
    }
}
