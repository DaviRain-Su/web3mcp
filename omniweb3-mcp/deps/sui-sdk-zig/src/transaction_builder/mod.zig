const std = @import("std");
const types = @import("../types/mod.zig");
const bcs = @import("../types/bcs.zig");
const ed25519 = @import("../crypto/ed25519.zig");
const secp256k1 = @import("../crypto/secp256k1.zig");
const secp256r1 = @import("../crypto/secp256r1.zig");
const intent_mod = @import("../crypto/intent.zig");

pub const TransactionBuilder = struct {
    allocator: std.mem.Allocator,
    sender: types.Address,
    gas_payment: ?types.GasPayment,
    expiration: types.TransactionExpiration,
    inputs: std.ArrayList(types.Input),
    commands: std.ArrayList(types.Command),

    pub fn init(allocator: std.mem.Allocator, sender: types.Address) TransactionBuilder {
        return .{
            .allocator = allocator,
            .sender = sender,
            .gas_payment = null,
            .expiration = .none,
            .inputs = std.ArrayList(types.Input).initCapacity(allocator, 0) catch unreachable,
            .commands = std.ArrayList(types.Command).initCapacity(allocator, 0) catch unreachable,
        };
    }

    pub fn deinit(self: *TransactionBuilder) void {
        for (self.inputs.items) |*input| input.deinit(self.allocator);
        self.inputs.deinit(self.allocator);
        for (self.commands.items) |*command| command.deinit(self.allocator);
        self.commands.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn setGasPayment(self: *TransactionBuilder, gas_payment: types.GasPayment) void {
        self.gas_payment = gas_payment;
    }

    pub fn setExpiration(self: *TransactionBuilder, expiration: types.TransactionExpiration) void {
        self.expiration = expiration;
    }

    pub fn addInput(self: *TransactionBuilder, input: types.Input) !void {
        try self.inputs.append(self.allocator, input);
    }

    pub fn addInputArgument(self: *TransactionBuilder, input: types.Input) !types.Argument {
        if (self.inputs.items.len >= std.math.maxInt(u16)) return error.InputIndexOverflow;
        const index: u16 = @intCast(self.inputs.items.len);
        try self.inputs.append(self.allocator, input);
        return .{ .input = index };
    }

    pub fn addMoveCall(
        self: *TransactionBuilder,
        package: types.Address,
        module: []const u8,
        function: []const u8,
        type_arguments: []const types.TypeTag,
        arguments: []const types.Argument,
    ) !void {
        var module_id = try types.Identifier.init(self.allocator, module);
        errdefer module_id.deinit(self.allocator);
        var function_id = try types.Identifier.init(self.allocator, function);
        errdefer function_id.deinit(self.allocator);

        var ty_args = try self.allocator.alloc(types.TypeTag, type_arguments.len);
        errdefer {
            for (ty_args) |*arg| arg.deinit(self.allocator);
            self.allocator.free(ty_args);
        }
        var i: usize = 0;
        while (i < type_arguments.len) : (i += 1) {
            ty_args[i] = try cloneTypeTag(self.allocator, type_arguments[i]);
        }

        const arg_list = try self.allocator.alloc(types.Argument, arguments.len);
        errdefer self.allocator.free(arg_list);
        std.mem.copyForwards(types.Argument, arg_list, arguments);

        const move_call = types.MoveCall{
            .package = package,
            .module = module_id,
            .function = function_id,
            .type_arguments = ty_args,
            .arguments = arg_list,
        };
        try self.commands.append(self.allocator, .{ .move_call = move_call });
    }

    pub fn addTransferObjects(self: *TransactionBuilder, objects: []const types.Argument, address: types.Argument) !void {
        const obj_list = try self.allocator.alloc(types.Argument, objects.len);
        errdefer self.allocator.free(obj_list);
        std.mem.copyForwards(types.Argument, obj_list, objects);
        const transfer = types.TransferObjects{ .objects = obj_list, .address = address };
        try self.commands.append(self.allocator, .{ .transfer_objects = transfer });
    }

    pub fn addSplitCoins(self: *TransactionBuilder, coin: types.Argument, amounts: []const types.Argument) !void {
        const amount_list = try self.allocator.alloc(types.Argument, amounts.len);
        errdefer self.allocator.free(amount_list);
        std.mem.copyForwards(types.Argument, amount_list, amounts);
        const split = types.SplitCoins{ .coin = coin, .amounts = amount_list };
        try self.commands.append(self.allocator, .{ .split_coins = split });
    }

    pub fn addMergeCoins(self: *TransactionBuilder, coin: types.Argument, coins_to_merge: []const types.Argument) !void {
        const coin_list = try self.allocator.alloc(types.Argument, coins_to_merge.len);
        errdefer self.allocator.free(coin_list);
        std.mem.copyForwards(types.Argument, coin_list, coins_to_merge);
        const merge = types.MergeCoins{ .coin = coin, .coins_to_merge = coin_list };
        try self.commands.append(self.allocator, .{ .merge_coins = merge });
    }

    pub fn addPublish(self: *TransactionBuilder, modules: []const []const u8, dependencies: []const types.Address) !void {
        const module_list = try self.allocator.alloc([]u8, modules.len);
        errdefer {
            for (module_list) |module| self.allocator.free(module);
            self.allocator.free(module_list);
        }
        var i: usize = 0;
        while (i < modules.len) : (i += 1) {
            module_list[i] = try dupBytes(self.allocator, modules[i]);
        }

        const deps = try self.allocator.alloc(types.Address, dependencies.len);
        errdefer self.allocator.free(deps);
        std.mem.copyForwards(types.Address, deps, dependencies);

        const publish = types.Publish{ .modules = module_list, .dependencies = deps };
        try self.commands.append(self.allocator, .{ .publish = publish });
    }

    pub fn addUpgrade(
        self: *TransactionBuilder,
        modules: []const []const u8,
        dependencies: []const types.Address,
        package: types.Address,
        ticket: types.Argument,
    ) !void {
        const module_list = try self.allocator.alloc([]u8, modules.len);
        errdefer {
            for (module_list) |module| self.allocator.free(module);
            self.allocator.free(module_list);
        }
        var i: usize = 0;
        while (i < modules.len) : (i += 1) {
            module_list[i] = try dupBytes(self.allocator, modules[i]);
        }

        const deps = try self.allocator.alloc(types.Address, dependencies.len);
        errdefer self.allocator.free(deps);
        std.mem.copyForwards(types.Address, deps, dependencies);

        const upgrade = types.Upgrade{ .modules = module_list, .dependencies = deps, .package = package, .ticket = ticket };
        try self.commands.append(self.allocator, .{ .upgrade = upgrade });
    }

    pub fn addMakeMoveVector(
        self: *TransactionBuilder,
        type_tag: ?types.TypeTag,
        elements: []const types.Argument,
    ) !void {
        var cloned_type: ?types.TypeTag = null;
        if (type_tag) |tag| {
            cloned_type = try cloneTypeTag(self.allocator, tag);
        }

        const element_list = try self.allocator.alloc(types.Argument, elements.len);
        errdefer self.allocator.free(element_list);
        std.mem.copyForwards(types.Argument, element_list, elements);

        const make = types.MakeMoveVector{ .type_ = cloned_type, .elements = element_list };
        try self.commands.append(self.allocator, .{ .make_move_vector = make });
    }

    pub fn addPureInput(self: *TransactionBuilder, bytes: []const u8) !types.Argument {
        const data = try dupBytes(self.allocator, bytes);
        const input = types.Input{ .pure = data };
        return self.addInputArgument(input);
    }

    pub fn addCommand(self: *TransactionBuilder, command: types.Command) !void {
        try self.commands.append(self.allocator, command);
    }

    pub fn build(self: *TransactionBuilder) !types.Transaction {
        const inputs = try self.inputs.toOwnedSlice(self.allocator);
        const commands = try self.commands.toOwnedSlice(self.allocator);
        const programmable = types.ProgrammableTransaction{ .inputs = inputs, .commands = commands };
        const kind = types.TransactionKind{ .programmable_transaction = programmable };
        const gas_payment = self.gas_payment orelse types.GasPayment{
            .objects = &.{},
            .owner = self.sender,
            .price = 0,
            .budget = 0,
        };
        return .{
            .kind = kind,
            .sender = self.sender,
            .gas_payment = gas_payment,
            .expiration = self.expiration,
        };
    }

    pub fn signEd25519(self: *TransactionBuilder, seed: [32]u8) !types.SignedTransaction {
        const intent_message = try buildIntentMessage(self.allocator, self);
        defer self.allocator.free(intent_message.bytes);

        const signature = try ed25519.signDeterministic(seed, intent_message.bytes);
        const public_key = try ed25519.derivePublicKey(seed);
        const simple = types.SimpleSignature{ .ed25519 = .{ .signature = signature, .public_key = public_key } };
        const user_sig = types.UserSignature{ .simple = simple };

        return try buildSignedTransaction(self.allocator, intent_message.transaction, user_sig);
    }

    pub fn signSecp256k1(self: *TransactionBuilder, private_key: [32]u8) !types.SignedTransaction {
        const intent_message = try buildIntentMessage(self.allocator, self);
        defer self.allocator.free(intent_message.bytes);

        const signature = try secp256k1.signDeterministic(private_key, intent_message.bytes);
        const public_key = try secp256k1.derivePublicKey(private_key);
        const simple = types.SimpleSignature{ .secp256k1 = .{ .signature = signature, .public_key = public_key } };
        const user_sig = types.UserSignature{ .simple = simple };

        return try buildSignedTransaction(self.allocator, intent_message.transaction, user_sig);
    }

    pub fn signSecp256r1(self: *TransactionBuilder, private_key: [32]u8) !types.SignedTransaction {
        const intent_message = try buildIntentMessage(self.allocator, self);
        defer self.allocator.free(intent_message.bytes);

        const signature = try secp256r1.signDeterministic(private_key, intent_message.bytes);
        const public_key = try secp256r1.derivePublicKey(private_key);
        const simple = types.SimpleSignature{ .secp256r1 = .{ .signature = signature, .public_key = public_key } };
        const user_sig = types.UserSignature{ .simple = simple };

        return try buildSignedTransaction(self.allocator, intent_message.transaction, user_sig);
    }

    pub fn signWithMultisig(self: *TransactionBuilder, multisig: types.MultisigAggregatedSignature) !types.SignedTransaction {
        const intent_message = try buildIntentMessage(self.allocator, self);
        defer self.allocator.free(intent_message.bytes);
        const user_sig = types.UserSignature{ .multisig = multisig };
        return try buildSignedTransaction(self.allocator, intent_message.transaction, user_sig);
    }
};

fn cloneIdentifier(allocator: std.mem.Allocator, ident: types.Identifier) !types.Identifier {
    return types.Identifier.init(allocator, ident.asStr());
}

fn cloneStructTag(allocator: std.mem.Allocator, tag: types.StructTag) !types.StructTag {
    var module_id = try cloneIdentifier(allocator, tag.moduleRef());
    errdefer module_id.deinit(allocator);
    var name_id = try cloneIdentifier(allocator, tag.nameRef());
    errdefer name_id.deinit(allocator);

    var params = try allocator.alloc(types.TypeTag, tag.typeParams().len);
    errdefer {
        for (params) |*param| param.deinit(allocator);
        allocator.free(params);
    }
    var i: usize = 0;
    while (i < params.len) : (i += 1) {
        params[i] = try cloneTypeTag(allocator, tag.typeParams()[i]);
    }

    return types.StructTag.initOwned(tag.addressRef(), module_id, name_id, params);
}

fn cloneTypeTag(allocator: std.mem.Allocator, tag: types.TypeTag) !types.TypeTag {
    return switch (tag) {
        .vector => |inner| {
            const boxed = try allocator.create(types.TypeTag);
            errdefer allocator.destroy(boxed);
            boxed.* = try cloneTypeTag(allocator, inner.*);
            return .{ .vector = boxed };
        },
        .struct_ => |inner| {
            const boxed = try allocator.create(types.StructTag);
            errdefer allocator.destroy(boxed);
            boxed.* = try cloneStructTag(allocator, inner.*);
            return .{ .struct_ = boxed };
        },
        else => tag,
    };
}

fn dupBytes(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const copy = try allocator.alloc(u8, bytes.len);
    std.mem.copyForwards(u8, copy, bytes);
    return copy;
}

const IntentMessage = struct {
    transaction: types.Transaction,
    bytes: []u8,
};

fn buildIntentMessage(allocator: std.mem.Allocator, builder: *TransactionBuilder) !IntentMessage {
    var transaction = try builder.build();
    errdefer transaction.deinit(allocator);

    var writer = try bcs.Writer.init(allocator);
    defer writer.deinit();
    try transaction.encodeBcs(&writer);
    const tx_bytes = try writer.toOwnedSlice();
    defer allocator.free(tx_bytes);

    const intent = intent_mod.Intent.init(.transaction_data, .v0, .sui);
    const intent_bytes = intent.toBytes();
    const message = try allocator.alloc(u8, 3 + tx_bytes.len);
    std.mem.copyForwards(u8, message[0..3], &intent_bytes);
    std.mem.copyForwards(u8, message[3..], tx_bytes);

    return .{ .transaction = transaction, .bytes = message };
}

fn buildSignedTransaction(
    allocator: std.mem.Allocator,
    transaction: types.Transaction,
    user_sig: types.UserSignature,
) !types.SignedTransaction {
    const sigs = try allocator.alloc(types.UserSignature, 1);
    sigs[0] = user_sig;
    return .{ .transaction = transaction, .signatures = sigs };
}
