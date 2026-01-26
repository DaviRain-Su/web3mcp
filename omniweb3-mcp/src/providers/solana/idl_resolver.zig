const std = @import("std");
const chain_provider = @import("../../core/chain_provider.zig");
const http_utils = @import("../../core/http_utils.zig");
const secure_http = @import("../../core/secure_http.zig");

const ContractMeta = chain_provider.ContractMeta;
const ChainType = chain_provider.ChainType;
const Function = chain_provider.Function;
const Parameter = chain_provider.Parameter;
const Type = chain_provider.Type;
const PrimitiveType = chain_provider.PrimitiveType;
const Mutability = chain_provider.Mutability;
const TypeDef = chain_provider.TypeDef;
const Event = chain_provider.Event;

/// IDL Resolver - fetches and parses Solana program IDLs
pub const IdlResolver = struct {
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    registry_path: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, rpc_url: []const u8) !IdlResolver {
        return .{
            .allocator = allocator,
            .rpc_url = rpc_url,
            .registry_path = null,
        };
    }

    pub fn deinit(self: *IdlResolver) void {
        _ = self;
    }

    /// Resolve IDL for a program
    /// Tries multiple strategies in order:
    /// 1. Local registry
    /// 2. Solana FM API
    /// 3. On-chain IDL account (TODO)
    pub fn resolve(
        self: *IdlResolver,
        allocator: std.mem.Allocator,
        program_id: []const u8,
    ) !ContractMeta {
        // Strategy 1: Check local registry first
        if (self.loadFromRegistry(allocator, program_id)) |meta| {
            return meta;
        } else |_| {}

        // Strategy 2: Try Solana FM API
        if (self.fetchFromSolanaFM(allocator, program_id)) |meta| {
            return meta;
        } else |_| {}

        // Strategy 3: Try on-chain IDL account (TODO)
        // if (self.fetchOnChainIdl(allocator, program_id)) |meta| {
        //     return meta;
        // } else |_| {}

        return error.IdlNotFound;
    }

    /// Load IDL from local registry
    fn loadFromRegistry(
        self: *IdlResolver,
        allocator: std.mem.Allocator,
        program_id: []const u8,
    ) !ContractMeta {
        const registry_path = self.registry_path orelse "idl_registry";

        // Construct file path: idl_registry/<program_id>.json
        const file_path = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}.json",
            .{ registry_path, program_id },
        );
        defer allocator.free(file_path);

        // Try to read the file
        const file = std.fs.cwd().openFile(file_path, .{}) catch {
            return error.RegistryNotFound;
        };
        defer file.close();

        // Read entire file
        const max_size = 10 * 1024 * 1024; // 10MB max
        const idl_json = try file.readToEndAlloc(allocator, max_size);
        defer allocator.free(idl_json);

        // Parse IDL JSON
        return try self.parseIdl(allocator, idl_json, program_id);
    }

    /// Fetch IDL from Solana FM API
    fn fetchFromSolanaFM(
        self: *IdlResolver,
        allocator: std.mem.Allocator,
        program_id: []const u8,
    ) !ContractMeta {
        const url = try std.fmt.allocPrint(
            allocator,
            "https://api.solana.fm/v1/programs/{s}/idl",
            .{program_id},
        );
        defer allocator.free(url);

        // Fetch via HTTP
        const use_api_key = false;
        const insecure = false;
        const idl_json = secure_http.secureGet(allocator, url, use_api_key, insecure) catch {
            return error.SolanaFMFetchFailed;
        };
        defer allocator.free(idl_json);

        // Parse IDL JSON
        return try self.parseIdl(allocator, idl_json, program_id);
    }

    /// Parse Anchor IDL JSON into ContractMeta
    fn parseIdl(
        self: *IdlResolver,
        allocator: std.mem.Allocator,
        idl_json: []const u8,
        program_id: []const u8,
    ) !ContractMeta {
        _ = self;

        // Parse JSON
        const parsed = try std.json.parseFromSlice(
            std.json.Value,
            allocator,
            idl_json,
            .{ .allocate = .alloc_always },
        );
        defer parsed.deinit();

        const idl = parsed.value;

        // Extract metadata
        const name = if (idl.object.get("name")) |n|
            try allocator.dupe(u8, n.string)
        else
            null;

        const version = if (idl.object.get("version")) |v|
            try allocator.dupe(u8, v.string)
        else
            null;

        // Parse instructions -> Functions
        var functions = std.ArrayList(Function).init(allocator);
        errdefer {
            for (functions.items) |*func| {
                func.deinit(allocator);
            }
            functions.deinit();
        }

        if (idl.object.get("instructions")) |instructions| {
            for (instructions.array.items) |instr| {
                const func = try parseInstruction(allocator, instr);
                try functions.append(func);
            }
        }

        // Parse accounts -> TypeDefs
        var types = std.ArrayList(TypeDef).init(allocator);
        errdefer {
            for (types.items) |*type_def| {
                type_def.deinit(allocator);
            }
            types.deinit();
        }

        if (idl.object.get("accounts")) |accounts| {
            for (accounts.array.items) |account| {
                const type_def = try parseAccountType(allocator, account);
                try types.append(type_def);
            }
        }

        // Parse events
        var events = std.ArrayList(Event).init(allocator);
        errdefer {
            for (events.items) |*event| {
                event.deinit(allocator);
            }
            events.deinit();
        }

        if (idl.object.get("events")) |event_list| {
            for (event_list.array.items) |event| {
                const parsed_event = try parseEvent(allocator, event);
                try events.append(parsed_event);
            }
        }

        return ContractMeta{
            .chain = .solana,
            .address = try allocator.dupe(u8, program_id),
            .name = name,
            .version = version,
            .functions = try functions.toOwnedSlice(),
            .types = try types.toOwnedSlice(),
            .events = try events.toOwnedSlice(),
            .raw = idl,
        };
    }

    /// Parse Anchor instruction into Function
    fn parseInstruction(allocator: std.mem.Allocator, instr: std.json.Value) !Function {
        const name = try allocator.dupe(u8, instr.object.get("name").?.string);

        // Parse docs
        const description = if (instr.object.get("docs")) |docs_array|
            if (docs_array.array.items.len > 0)
                try allocator.dupe(u8, docs_array.array.items[0].string)
            else
                null
        else
            null;

        // Parse args -> inputs
        var inputs = std.ArrayList(Parameter).init(allocator);
        errdefer {
            for (inputs.items) |*param| {
                param.deinit(allocator);
            }
            inputs.deinit();
        }

        if (instr.object.get("args")) |args| {
            for (args.array.items) |arg| {
                const param = try parseParameter(allocator, arg);
                try inputs.append(param);
            }
        }

        // Solana instructions don't have return values in IDL
        const outputs = try allocator.alloc(Parameter, 0);

        // All instructions are mutable (they modify state)
        const mutability = Mutability.mutable;

        return Function{
            .name = name,
            .description = description,
            .inputs = try inputs.toOwnedSlice(),
            .outputs = outputs,
            .mutability = mutability,
        };
    }

    /// Parse parameter from IDL
    fn parseParameter(allocator: std.mem.Allocator, param_json: std.json.Value) !Parameter {
        const name = try allocator.dupe(u8, param_json.object.get("name").?.string);
        const type_json = param_json.object.get("type").?;
        const param_type = try parseType(allocator, type_json);

        return Parameter{
            .name = name,
            .type = param_type,
            .optional = false,
        };
    }

    /// Parse type from IDL
    fn parseType(allocator: std.mem.Allocator, type_json: std.json.Value) error{OutOfMemory}!Type {
        // Handle string types (primitives)
        if (type_json == .string) {
            const type_str = type_json.string;

            // Map Anchor types to our primitive types
            if (std.mem.eql(u8, type_str, "u8")) return Type{ .primitive = .u8 };
            if (std.mem.eql(u8, type_str, "u16")) return Type{ .primitive = .u16 };
            if (std.mem.eql(u8, type_str, "u32")) return Type{ .primitive = .u32 };
            if (std.mem.eql(u8, type_str, "u64")) return Type{ .primitive = .u64 };
            if (std.mem.eql(u8, type_str, "u128")) return Type{ .primitive = .u128 };
            if (std.mem.eql(u8, type_str, "i8")) return Type{ .primitive = .i8 };
            if (std.mem.eql(u8, type_str, "i16")) return Type{ .primitive = .i16 };
            if (std.mem.eql(u8, type_str, "i32")) return Type{ .primitive = .i32 };
            if (std.mem.eql(u8, type_str, "i64")) return Type{ .primitive = .i64 };
            if (std.mem.eql(u8, type_str, "i128")) return Type{ .primitive = .i128 };
            if (std.mem.eql(u8, type_str, "bool")) return Type{ .primitive = .bool };
            if (std.mem.eql(u8, type_str, "string")) return Type{ .primitive = .string };
            if (std.mem.eql(u8, type_str, "publicKey")) return Type{ .primitive = .pubkey };
            if (std.mem.eql(u8, type_str, "bytes")) return Type{ .primitive = .bytes };

            // Custom type reference
            return Type{ .custom = try allocator.dupe(u8, type_str) };
        }

        // Handle object types (array, option, etc.)
        if (type_json == .object) {
            // Array type: { "vec": <inner_type> }
            if (type_json.object.get("vec")) |inner| {
                const inner_type = try allocator.create(Type);
                inner_type.* = try parseType(allocator, inner);
                return Type{ .array = inner_type };
            }

            // Option type: { "option": <inner_type> }
            if (type_json.object.get("option")) |inner| {
                const inner_type = try allocator.create(Type);
                inner_type.* = try parseType(allocator, inner);
                return Type{ .option = inner_type };
            }
        }

        // Default to custom type
        return Type{ .custom = try allocator.dupe(u8, "unknown") };
    }

    /// Parse account type into TypeDef
    fn parseAccountType(allocator: std.mem.Allocator, account_json: std.json.Value) !TypeDef {
        const name = try allocator.dupe(u8, account_json.object.get("name").?.string);

        // Parse type fields
        var fields = std.ArrayList(chain_provider.Field).init(allocator);
        errdefer {
            for (fields.items) |*field| {
                field.deinit(allocator);
            }
            fields.deinit();
        }

        if (account_json.object.get("type")) |type_obj| {
            if (type_obj.object.get("fields")) |field_list| {
                for (field_list.array.items) |field_json| {
                    const field_name = try allocator.dupe(u8, field_json.object.get("name").?.string);
                    const field_type = try parseType(allocator, field_json.object.get("type").?);

                    try fields.append(.{
                        .name = field_name,
                        .type = field_type,
                    });
                }
            }
        }

        return TypeDef{
            .name = name,
            .kind = .{ .struct_def = try fields.toOwnedSlice() },
        };
    }

    /// Parse event from IDL
    fn parseEvent(allocator: std.mem.Allocator, event_json: std.json.Value) !Event {
        const name = try allocator.dupe(u8, event_json.object.get("name").?.string);

        var fields = std.ArrayList(chain_provider.Field).init(allocator);
        errdefer {
            for (fields.items) |*field| {
                field.deinit(allocator);
            }
            fields.deinit();
        }

        if (event_json.object.get("fields")) |field_list| {
            for (field_list.array.items) |field_json| {
                const field_name = try allocator.dupe(u8, field_json.object.get("name").?.string);
                const field_type = try parseType(allocator, field_json.object.get("type").?);

                try fields.append(.{
                    .name = field_name,
                    .type = field_type,
                });
            }
        }

        return Event{
            .name = name,
            .fields = try fields.toOwnedSlice(),
        };
    }
};

// Unit tests
test "parseType primitives" {
    const allocator = std.testing.allocator;

    const u64_json = std.json.Value{ .string = "u64" };
    const u64_type = try IdlResolver.parseType(allocator, u64_json);
    try std.testing.expectEqual(Type{ .primitive = .u64 }, u64_type);

    const pubkey_json = std.json.Value{ .string = "publicKey" };
    const pubkey_type = try IdlResolver.parseType(allocator, pubkey_json);
    try std.testing.expectEqual(Type{ .primitive = .pubkey }, pubkey_type);
}
