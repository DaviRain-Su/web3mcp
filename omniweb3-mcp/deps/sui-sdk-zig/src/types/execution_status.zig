const std = @import("std");
const bcs = @import("bcs.zig");
const Address = @import("address.zig").Address;
const Digest = @import("digest.zig").Digest;
const Identifier = @import("type_tag.zig").Identifier;

pub const ExecutionStatus = union(enum) {
    success,
    failure: struct { err: ExecutionError, command: ?u64 },

    pub fn deinit(self: *ExecutionStatus, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .failure => |*value| value.err.deinit(allocator),
            else => {},
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: ExecutionStatus, writer: *bcs.Writer) !void {
        switch (self) {
            .success => try writer.writeUleb128(0),
            .failure => |value| {
                try writer.writeUleb128(1);
                try value.err.encodeBcs(writer);
                try writeOptionalU64(writer, value.command);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ExecutionStatus {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .success,
            1 => .{ .failure = .{ .err = try ExecutionError.decodeBcs(reader, allocator), .command = try readOptionalU64(reader) } },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const ExecutionError = union(enum) {
    insufficient_gas,
    invalid_gas_object,
    invariant_violation,
    feature_not_yet_supported,
    object_too_big: struct { object_size: u64, max_object_size: u64 },
    package_too_big: struct { object_size: u64, max_object_size: u64 },
    circular_object_ownership: struct { object: Address },
    insufficient_coin_balance,
    coin_balance_overflow,
    publish_error_non_zero_address,
    sui_move_verification_error,
    move_primitive_runtime_error: struct { location: ?MoveLocation },
    move_abort: struct { location: MoveLocation, code: u64 },
    vm_verification_or_deserialization_error,
    vm_invariant_violation,
    function_not_found,
    arity_mismatch,
    type_arity_mismatch,
    non_entry_function_invoked,
    command_argument_error: struct { argument: u16, kind: CommandArgumentError },
    type_argument_error: struct { type_argument: u16, kind: TypeArgumentError },
    unused_value_without_drop: struct { result: u16, subresult: u16 },
    invalid_public_function_return_type: struct { index: u16 },
    invalid_transfer_object,
    effects_too_large: struct { current_size: u64, max_size: u64 },
    publish_upgrade_missing_dependency,
    publish_upgrade_dependency_downgrade,
    package_upgrade_error: struct { kind: PackageUpgradeError },
    written_objects_too_large: struct { object_size: u64, max_object_size: u64 },
    certificate_denied,
    sui_move_verification_timedout,
    consensus_object_operation_not_allowed,
    input_object_deleted,
    execution_canceled_due_to_consensus_object_congestion: struct { congested_objects: []Address },
    address_denied_for_coin: struct { address: Address, coin_type: []u8 },
    coin_type_global_pause: struct { coin_type: []u8 },
    execution_canceled_due_to_randomness_unavailable,
    move_vector_elem_too_big: struct { value_size: u64, max_scaled_size: u64 },
    move_raw_value_too_big: struct { value_size: u64, max_scaled_size: u64 },
    invalid_linkage,
    insufficient_funds_for_withdraw,
    non_exclusive_write_input_object_modified: struct { object: Address },

    pub fn deinit(self: *ExecutionError, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .move_primitive_runtime_error => |*value| {
                if (value.location) |*loc| loc.deinit(allocator);
            },
            .move_abort => |*value| value.location.deinit(allocator),
            .command_argument_error => |*value| value.kind.deinit(allocator),
            .type_argument_error => |*value| value.kind.deinit(allocator),
            .package_upgrade_error => |*value| value.kind.deinit(allocator),
            .execution_canceled_due_to_consensus_object_congestion => |value| allocator.free(value.congested_objects),
            .address_denied_for_coin => |value| allocator.free(value.coin_type),
            .coin_type_global_pause => |value| allocator.free(value.coin_type),
            else => {},
        }
        self.* = undefined;
    }

    pub fn encodeBcs(self: ExecutionError, writer: *bcs.Writer) !void {
        switch (self) {
            .insufficient_gas => try writer.writeUleb128(0),
            .invalid_gas_object => try writer.writeUleb128(1),
            .invariant_violation => try writer.writeUleb128(2),
            .feature_not_yet_supported => try writer.writeUleb128(3),
            .object_too_big => |value| {
                try writer.writeUleb128(4);
                try writer.writeU64(value.object_size);
                try writer.writeU64(value.max_object_size);
            },
            .package_too_big => |value| {
                try writer.writeUleb128(5);
                try writer.writeU64(value.object_size);
                try writer.writeU64(value.max_object_size);
            },
            .circular_object_ownership => |value| {
                try writer.writeUleb128(6);
                try value.object.encodeBcs(writer);
            },
            .insufficient_coin_balance => try writer.writeUleb128(7),
            .coin_balance_overflow => try writer.writeUleb128(8),
            .publish_error_non_zero_address => try writer.writeUleb128(9),
            .sui_move_verification_error => try writer.writeUleb128(10),
            .move_primitive_runtime_error => |value| {
                try writer.writeUleb128(11);
                try writeOptionalMoveLocation(writer, value.location);
            },
            .move_abort => |value| {
                try writer.writeUleb128(12);
                try value.location.encodeBcs(writer);
                try writer.writeU64(value.code);
            },
            .vm_verification_or_deserialization_error => try writer.writeUleb128(13),
            .vm_invariant_violation => try writer.writeUleb128(14),
            .function_not_found => try writer.writeUleb128(15),
            .arity_mismatch => try writer.writeUleb128(16),
            .type_arity_mismatch => try writer.writeUleb128(17),
            .non_entry_function_invoked => try writer.writeUleb128(18),
            .command_argument_error => |value| {
                try writer.writeUleb128(19);
                try writer.writeU16(value.argument);
                try value.kind.encodeBcs(writer);
            },
            .type_argument_error => |value| {
                try writer.writeUleb128(20);
                try writer.writeU16(value.type_argument);
                try value.kind.encodeBcs(writer);
            },
            .unused_value_without_drop => |value| {
                try writer.writeUleb128(21);
                try writer.writeU16(value.result);
                try writer.writeU16(value.subresult);
            },
            .invalid_public_function_return_type => |value| {
                try writer.writeUleb128(22);
                try writer.writeU16(value.index);
            },
            .invalid_transfer_object => try writer.writeUleb128(23),
            .effects_too_large => |value| {
                try writer.writeUleb128(24);
                try writer.writeU64(value.current_size);
                try writer.writeU64(value.max_size);
            },
            .publish_upgrade_missing_dependency => try writer.writeUleb128(25),
            .publish_upgrade_dependency_downgrade => try writer.writeUleb128(26),
            .package_upgrade_error => |value| {
                try writer.writeUleb128(27);
                try value.kind.encodeBcs(writer);
            },
            .written_objects_too_large => |value| {
                try writer.writeUleb128(28);
                try writer.writeU64(value.object_size);
                try writer.writeU64(value.max_object_size);
            },
            .certificate_denied => try writer.writeUleb128(29),
            .sui_move_verification_timedout => try writer.writeUleb128(30),
            .consensus_object_operation_not_allowed => try writer.writeUleb128(31),
            .input_object_deleted => try writer.writeUleb128(32),
            .execution_canceled_due_to_consensus_object_congestion => |value| {
                try writer.writeUleb128(33);
                try writer.writeUleb128(value.congested_objects.len);
                for (value.congested_objects) |addr| try addr.encodeBcs(writer);
            },
            .address_denied_for_coin => |value| {
                try writer.writeUleb128(34);
                try value.address.encodeBcs(writer);
                try writer.writeString(value.coin_type);
            },
            .coin_type_global_pause => |value| {
                try writer.writeUleb128(35);
                try writer.writeString(value.coin_type);
            },
            .execution_canceled_due_to_randomness_unavailable => try writer.writeUleb128(36),
            .move_vector_elem_too_big => |value| {
                try writer.writeUleb128(37);
                try writer.writeU64(value.value_size);
                try writer.writeU64(value.max_scaled_size);
            },
            .move_raw_value_too_big => |value| {
                try writer.writeUleb128(38);
                try writer.writeU64(value.value_size);
                try writer.writeU64(value.max_scaled_size);
            },
            .invalid_linkage => try writer.writeUleb128(39),
            .insufficient_funds_for_withdraw => try writer.writeUleb128(40),
            .non_exclusive_write_input_object_modified => |value| {
                try writer.writeUleb128(41);
                try value.object.encodeBcs(writer);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !ExecutionError {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .insufficient_gas,
            1 => .invalid_gas_object,
            2 => .invariant_violation,
            3 => .feature_not_yet_supported,
            4 => .{ .object_too_big = .{ .object_size = try reader.readU64(), .max_object_size = try reader.readU64() } },
            5 => .{ .package_too_big = .{ .object_size = try reader.readU64(), .max_object_size = try reader.readU64() } },
            6 => .{ .circular_object_ownership = .{ .object = try Address.decodeBcs(reader) } },
            7 => .insufficient_coin_balance,
            8 => .coin_balance_overflow,
            9 => .publish_error_non_zero_address,
            10 => .sui_move_verification_error,
            11 => .{ .move_primitive_runtime_error = .{ .location = try readOptionalMoveLocation(reader, allocator) } },
            12 => .{ .move_abort = .{ .location = try MoveLocation.decodeBcs(reader, allocator), .code = try reader.readU64() } },
            13 => .vm_verification_or_deserialization_error,
            14 => .vm_invariant_violation,
            15 => .function_not_found,
            16 => .arity_mismatch,
            17 => .type_arity_mismatch,
            18 => .non_entry_function_invoked,
            19 => .{ .command_argument_error = .{ .argument = try reader.readU16(), .kind = try CommandArgumentError.decodeBcs(reader, allocator) } },
            20 => .{ .type_argument_error = .{ .type_argument = try reader.readU16(), .kind = try TypeArgumentError.decodeBcs(reader) } },
            21 => .{ .unused_value_without_drop = .{ .result = try reader.readU16(), .subresult = try reader.readU16() } },
            22 => .{ .invalid_public_function_return_type = .{ .index = try reader.readU16() } },
            23 => .invalid_transfer_object,
            24 => .{ .effects_too_large = .{ .current_size = try reader.readU64(), .max_size = try reader.readU64() } },
            25 => .publish_upgrade_missing_dependency,
            26 => .publish_upgrade_dependency_downgrade,
            27 => .{ .package_upgrade_error = .{ .kind = try PackageUpgradeError.decodeBcs(reader, allocator) } },
            28 => .{ .written_objects_too_large = .{ .object_size = try reader.readU64(), .max_object_size = try reader.readU64() } },
            29 => .certificate_denied,
            30 => .sui_move_verification_timedout,
            31 => .consensus_object_operation_not_allowed,
            32 => .input_object_deleted,
            33 => {
                const len = try reader.readUleb128();
                var items = try allocator.alloc(Address, len);
                var i: usize = 0;
                while (i < len) : (i += 1) {
                    items[i] = try Address.decodeBcs(reader);
                }
                return .{ .execution_canceled_due_to_consensus_object_congestion = .{ .congested_objects = items } };
            },
            34 => {
                const address = try Address.decodeBcs(reader);
                const coin_type = try readOwnedString(reader, allocator);
                return .{ .address_denied_for_coin = .{ .address = address, .coin_type = coin_type } };
            },
            35 => .{ .coin_type_global_pause = .{ .coin_type = try readOwnedString(reader, allocator) } },
            36 => .execution_canceled_due_to_randomness_unavailable,
            37 => .{ .move_vector_elem_too_big = .{ .value_size = try reader.readU64(), .max_scaled_size = try reader.readU64() } },
            38 => .{ .move_raw_value_too_big = .{ .value_size = try reader.readU64(), .max_scaled_size = try reader.readU64() } },
            39 => .invalid_linkage,
            40 => .insufficient_funds_for_withdraw,
            41 => .{ .non_exclusive_write_input_object_modified = .{ .object = try Address.decodeBcs(reader) } },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const MoveLocation = struct {
    package: Address,
    module: Identifier,
    function: u16,
    instruction: u16,
    function_name: ?Identifier,

    pub fn deinit(self: *MoveLocation, allocator: std.mem.Allocator) void {
        self.module.deinit(allocator);
        if (self.function_name) |*name| name.deinit(allocator);
        self.* = undefined;
    }

    pub fn encodeBcs(self: MoveLocation, writer: *bcs.Writer) !void {
        try self.package.encodeBcs(writer);
        try self.module.encodeBcs(writer);
        try writer.writeU16(self.function);
        try writer.writeU16(self.instruction);
        if (self.function_name) |name| {
            try writer.writeU8(1);
            try name.encodeBcs(writer);
        } else {
            try writer.writeU8(0);
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !MoveLocation {
        const package = try Address.decodeBcs(reader);
        var module = try Identifier.decodeBcs(reader, allocator);
        errdefer module.deinit(allocator);
        const function = try reader.readU16();
        const instruction = try reader.readU16();
        const tag = try reader.readU8();
        var function_name: ?Identifier = null;
        if (tag == 1) {
            function_name = try Identifier.decodeBcs(reader, allocator);
        } else if (tag != 0) {
            return bcs.BcsError.InvalidOptionTag;
        }
        return .{ .package = package, .module = module, .function = function, .instruction = instruction, .function_name = function_name };
    }
};

pub const CommandArgumentError = union(enum) {
    type_mismatch,
    invalid_bcs_bytes,
    invalid_usage_of_pure_argument,
    invalid_argument_to_private_entry_function,
    index_out_of_bounds: struct { index: u16 },
    secondary_index_out_of_bounds: struct { result: u16, subresult: u16 },
    invalid_result_arity: struct { result: u16 },
    invalid_gas_coin_usage,
    invalid_value_usage,
    invalid_object_by_value,
    invalid_object_by_mut_ref,
    consensus_object_operation_not_allowed,
    invalid_argument_arity,
    invalid_transfer_object,
    invalid_make_move_vec_non_object_argument,
    argument_without_value,
    cannot_move_borrowed_value,
    cannot_write_to_extended_reference,
    invalid_reference_argument,

    pub fn deinit(self: *CommandArgumentError, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.* = undefined;
    }

    pub fn encodeBcs(self: CommandArgumentError, writer: *bcs.Writer) !void {
        switch (self) {
            .type_mismatch => try writer.writeUleb128(0),
            .invalid_bcs_bytes => try writer.writeUleb128(1),
            .invalid_usage_of_pure_argument => try writer.writeUleb128(2),
            .invalid_argument_to_private_entry_function => try writer.writeUleb128(3),
            .index_out_of_bounds => |value| {
                try writer.writeUleb128(4);
                try writer.writeU16(value.index);
            },
            .secondary_index_out_of_bounds => |value| {
                try writer.writeUleb128(5);
                try writer.writeU16(value.result);
                try writer.writeU16(value.subresult);
            },
            .invalid_result_arity => |value| {
                try writer.writeUleb128(6);
                try writer.writeU16(value.result);
            },
            .invalid_gas_coin_usage => try writer.writeUleb128(7),
            .invalid_value_usage => try writer.writeUleb128(8),
            .invalid_object_by_value => try writer.writeUleb128(9),
            .invalid_object_by_mut_ref => try writer.writeUleb128(10),
            .consensus_object_operation_not_allowed => try writer.writeUleb128(11),
            .invalid_argument_arity => try writer.writeUleb128(12),
            .invalid_transfer_object => try writer.writeUleb128(13),
            .invalid_make_move_vec_non_object_argument => try writer.writeUleb128(14),
            .argument_without_value => try writer.writeUleb128(15),
            .cannot_move_borrowed_value => try writer.writeUleb128(16),
            .cannot_write_to_extended_reference => try writer.writeUleb128(17),
            .invalid_reference_argument => try writer.writeUleb128(18),
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !CommandArgumentError {
        _ = allocator;
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .type_mismatch,
            1 => .invalid_bcs_bytes,
            2 => .invalid_usage_of_pure_argument,
            3 => .invalid_argument_to_private_entry_function,
            4 => .{ .index_out_of_bounds = .{ .index = try reader.readU16() } },
            5 => .{ .secondary_index_out_of_bounds = .{ .result = try reader.readU16(), .subresult = try reader.readU16() } },
            6 => .{ .invalid_result_arity = .{ .result = try reader.readU16() } },
            7 => .invalid_gas_coin_usage,
            8 => .invalid_value_usage,
            9 => .invalid_object_by_value,
            10 => .invalid_object_by_mut_ref,
            11 => .consensus_object_operation_not_allowed,
            12 => .invalid_argument_arity,
            13 => .invalid_transfer_object,
            14 => .invalid_make_move_vec_non_object_argument,
            15 => .argument_without_value,
            16 => .cannot_move_borrowed_value,
            17 => .cannot_write_to_extended_reference,
            18 => .invalid_reference_argument,
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const PackageUpgradeError = union(enum) {
    unable_to_fetch_package: struct { package_id: Address },
    not_a_package: struct { object_id: Address },
    incompatible_upgrade,
    digest_does_not_match: struct { digest: Digest },
    unknown_upgrade_policy: struct { policy: u8 },
    package_id_does_not_match: struct { package_id: Address, ticket_id: Address },

    pub fn deinit(self: *PackageUpgradeError, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.* = undefined;
    }

    pub fn encodeBcs(self: PackageUpgradeError, writer: *bcs.Writer) !void {
        switch (self) {
            .unable_to_fetch_package => |value| {
                try writer.writeUleb128(0);
                try value.package_id.encodeBcs(writer);
            },
            .not_a_package => |value| {
                try writer.writeUleb128(1);
                try value.object_id.encodeBcs(writer);
            },
            .incompatible_upgrade => try writer.writeUleb128(2),
            .digest_does_not_match => |value| {
                try writer.writeUleb128(3);
                try value.digest.encodeBcs(writer);
            },
            .unknown_upgrade_policy => |value| {
                try writer.writeUleb128(4);
                try writer.writeU8(value.policy);
            },
            .package_id_does_not_match => |value| {
                try writer.writeUleb128(5);
                try value.package_id.encodeBcs(writer);
                try value.ticket_id.encodeBcs(writer);
            },
        }
    }

    pub fn decodeBcs(reader: *bcs.Reader, allocator: std.mem.Allocator) !PackageUpgradeError {
        _ = allocator;
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .{ .unable_to_fetch_package = .{ .package_id = try Address.decodeBcs(reader) } },
            1 => .{ .not_a_package = .{ .object_id = try Address.decodeBcs(reader) } },
            2 => .incompatible_upgrade,
            3 => .{ .digest_does_not_match = .{ .digest = try Digest.decodeBcs(reader) } },
            4 => .{ .unknown_upgrade_policy = .{ .policy = try reader.readU8() } },
            5 => .{ .package_id_does_not_match = .{ .package_id = try Address.decodeBcs(reader), .ticket_id = try Address.decodeBcs(reader) } },
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

pub const TypeArgumentError = enum {
    type_not_found,
    constraint_not_satisfied,

    pub fn encodeBcs(self: TypeArgumentError, writer: *bcs.Writer) !void {
        try writer.writeUleb128(@intFromEnum(self));
    }

    pub fn decodeBcs(reader: *bcs.Reader) !TypeArgumentError {
        const variant = try reader.readUleb128();
        return switch (variant) {
            0 => .type_not_found,
            1 => .constraint_not_satisfied,
            else => return bcs.BcsError.InvalidOptionTag,
        };
    }
};

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

fn writeOptionalMoveLocation(writer: *bcs.Writer, value: ?MoveLocation) !void {
    if (value) |loc| {
        try writer.writeU8(1);
        try loc.encodeBcs(writer);
    } else {
        try writer.writeU8(0);
    }
}

fn readOptionalMoveLocation(reader: *bcs.Reader, allocator: std.mem.Allocator) !?MoveLocation {
    const tag = try reader.readU8();
    switch (tag) {
        0 => return null,
        1 => return try MoveLocation.decodeBcs(reader, allocator),
        else => return bcs.BcsError.InvalidOptionTag,
    }
}

fn readOwnedString(reader: *bcs.Reader, allocator: std.mem.Allocator) ![]u8 {
    const bytes = try reader.readString();
    const copy = try allocator.alloc(u8, bytes.len);
    std.mem.copyForwards(u8, copy, bytes);
    return copy;
}
