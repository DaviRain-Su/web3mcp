const std = @import("std");
const json = std.json;

pub const ObjectDataOptions = struct {
    showType: bool = false,
    showOwner: bool = false,
    showPreviousTransaction: bool = false,
    showDisplay: bool = false,
    showContent: bool = false,
    showBcs: bool = false,
    showStorageRebate: bool = false,

    pub fn toJson(self: ObjectDataOptions, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        defer out.deinit();
        var w: json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try w.beginObject();
        if (self.showType) {
            try w.objectField("showType");
            try w.write(true);
        }
        if (self.showOwner) {
            try w.objectField("showOwner");
            try w.write(true);
        }
        if (self.showPreviousTransaction) {
            try w.objectField("showPreviousTransaction");
            try w.write(true);
        }
        if (self.showDisplay) {
            try w.objectField("showDisplay");
            try w.write(true);
        }
        if (self.showContent) {
            try w.objectField("showContent");
            try w.write(true);
        }
        if (self.showBcs) {
            try w.objectField("showBcs");
            try w.write(true);
        }
        if (self.showStorageRebate) {
            try w.objectField("showStorageRebate");
            try w.write(true);
        }
        try w.endObject();
        return out.toOwnedSlice();
    }
};

pub const OwnedObjectsFilter = union(enum) {
    struct_type: []const u8,
    object_id: []const u8,
    package: []const u8,
    move_module: struct { package: []const u8, module: []const u8 },
    address_owner: []const u8,
    object_owner: []const u8,
    match_all: []OwnedObjectsFilter,
    match_any: []OwnedObjectsFilter,
    match_none: []OwnedObjectsFilter,

    pub fn toJson(self: OwnedObjectsFilter, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        defer out.deinit();
        var w: json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try w.beginObject();
        switch (self) {
            .struct_type => |value| {
                try w.objectField("StructType");
                try w.write(value);
            },
            .object_id => |value| {
                try w.objectField("ObjectId");
                try w.write(value);
            },
            .package => |value| {
                try w.objectField("Package");
                try w.write(value);
            },
            .move_module => |value| {
                try w.objectField("MoveModule");
                try w.beginObject();
                try w.objectField("package");
                try w.write(value.package);
                try w.objectField("module");
                try w.write(value.module);
                try w.endObject();
            },
            .address_owner => |value| {
                try w.objectField("AddressOwner");
                try w.write(value);
            },
            .object_owner => |value| {
                try w.objectField("ObjectOwner");
                try w.write(value);
            },
            .match_all => |items| {
                try w.objectField("MatchAll");
                try w.beginArray();
                for (items) |item| {
                    const json_str = try item.toJson(allocator);
                    defer allocator.free(json_str);
                    const parsed = try json.parseFromSlice(json.Value, allocator, json_str, .{});
                    defer parsed.deinit();
                    try w.write(parsed.value);
                }
                try w.endArray();
            },
            .match_any => |items| {
                try w.objectField("MatchAny");
                try w.beginArray();
                for (items) |item| {
                    const json_str = try item.toJson(allocator);
                    defer allocator.free(json_str);
                    const parsed = try json.parseFromSlice(json.Value, allocator, json_str, .{});
                    defer parsed.deinit();
                    try w.write(parsed.value);
                }
                try w.endArray();
            },
            .match_none => |items| {
                try w.objectField("MatchNone");
                try w.beginArray();
                for (items) |item| {
                    const json_str = try item.toJson(allocator);
                    defer allocator.free(json_str);
                    const parsed = try json.parseFromSlice(json.Value, allocator, json_str, .{});
                    defer parsed.deinit();
                    try w.write(parsed.value);
                }
                try w.endArray();
            },
        }
        try w.endObject();
        return out.toOwnedSlice();
    }
};

pub const OwnedObjectsQuery = struct {
    filter: ?OwnedObjectsFilter = null,
    options: ?ObjectDataOptions = null,

    pub fn toJson(self: OwnedObjectsQuery, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        defer out.deinit();
        var w: json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try w.beginObject();
        if (self.filter) |filter| {
            try w.objectField("filter");
            const filter_json = try filter.toJson(allocator);
            defer allocator.free(filter_json);
            const parsed = try json.parseFromSlice(json.Value, allocator, filter_json, .{});
            defer parsed.deinit();
            try w.write(parsed.value);
        }
        if (self.options) |options| {
            try w.objectField("options");
            const opts_json = try options.toJson(allocator);
            defer allocator.free(opts_json);
            const parsed = try json.parseFromSlice(json.Value, allocator, opts_json, .{});
            defer parsed.deinit();
            try w.write(parsed.value);
        }
        try w.endObject();
        return out.toOwnedSlice();
    }
};

pub const CoinFilter = struct {
    coin_type: ?[]const u8 = null,

    pub fn toJson(self: CoinFilter, allocator: std.mem.Allocator) ![]u8 {
        if (self.coin_type) |value| {
            var out: std.Io.Writer.Allocating = .init(allocator);
            defer out.deinit();
            var w: json.Stringify = .{ .writer = &out.writer, .options = .{} };
            try w.write(value);
            return out.toOwnedSlice();
        }
        return allocator.dupe(u8, "null");
    }
};

pub const TransactionFilter = union(enum) {
    move_event_type: []const u8,
    move_function: struct { package: []const u8, module: []const u8, function: []const u8 },
    input_object: []const u8,
    changed_object: []const u8,
    from_address: []const u8,
    to_address: []const u8,
    checkpoint: u64,
    match_all: []TransactionFilter,
    match_any: []TransactionFilter,
    match_none: []TransactionFilter,

    pub fn toJson(self: TransactionFilter, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        defer out.deinit();
        var w: json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try w.beginObject();
        switch (self) {
            .move_event_type => |value| {
                try w.objectField("MoveEventType");
                try w.write(value);
            },
            .move_function => |value| {
                try w.objectField("MoveFunction");
                try w.beginObject();
                try w.objectField("package");
                try w.write(value.package);
                try w.objectField("module");
                try w.write(value.module);
                try w.objectField("function");
                try w.write(value.function);
                try w.endObject();
            },
            .input_object => |value| {
                try w.objectField("InputObject");
                try w.write(value);
            },
            .changed_object => |value| {
                try w.objectField("ChangedObject");
                try w.write(value);
            },
            .from_address => |value| {
                try w.objectField("FromAddress");
                try w.write(value);
            },
            .to_address => |value| {
                try w.objectField("ToAddress");
                try w.write(value);
            },
            .checkpoint => |value| {
                try w.objectField("Checkpoint");
                try w.write(value);
            },
            .match_all => |items| {
                try w.objectField("MatchAll");
                try w.beginArray();
                for (items) |item| {
                    const json_str = try item.toJson(allocator);
                    defer allocator.free(json_str);
                    const parsed = try json.parseFromSlice(json.Value, allocator, json_str, .{});
                    defer parsed.deinit();
                    try w.write(parsed.value);
                }
                try w.endArray();
            },
            .match_any => |items| {
                try w.objectField("MatchAny");
                try w.beginArray();
                for (items) |item| {
                    const json_str = try item.toJson(allocator);
                    defer allocator.free(json_str);
                    const parsed = try json.parseFromSlice(json.Value, allocator, json_str, .{});
                    defer parsed.deinit();
                    try w.write(parsed.value);
                }
                try w.endArray();
            },
            .match_none => |items| {
                try w.objectField("MatchNone");
                try w.beginArray();
                for (items) |item| {
                    const json_str = try item.toJson(allocator);
                    defer allocator.free(json_str);
                    const parsed = try json.parseFromSlice(json.Value, allocator, json_str, .{});
                    defer parsed.deinit();
                    try w.write(parsed.value);
                }
                try w.endArray();
            },
        }
        try w.endObject();
        return out.toOwnedSlice();
    }
};

pub const TransactionQuery = struct {
    filter: ?TransactionFilter = null,

    pub fn toJson(self: TransactionQuery, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        defer out.deinit();
        var w: json.Stringify = .{ .writer = &out.writer, .options = .{} };
        try w.beginObject();
        if (self.filter) |filter| {
            try w.objectField("filter");
            const filter_json = try filter.toJson(allocator);
            defer allocator.free(filter_json);
            const parsed = try json.parseFromSlice(json.Value, allocator, filter_json, .{});
            defer parsed.deinit();
            try w.write(parsed.value);
        }
        try w.endObject();
        return out.toOwnedSlice();
    }
};
