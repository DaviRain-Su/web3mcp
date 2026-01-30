pub const Intent = struct {
    scope: IntentScope,
    version: IntentVersion,
    app_id: IntentAppId,

    pub fn init(scope: IntentScope, version: IntentVersion, app_id: IntentAppId) Intent {
        return .{ .scope = scope, .version = version, .app_id = app_id };
    }

    pub fn toBytes(self: Intent) [3]u8 {
        return .{
            @intFromEnum(self.scope),
            @intFromEnum(self.version),
            @intFromEnum(self.app_id),
        };
    }
};

pub const IntentScope = enum(u8) {
    transaction_data = 0,
    transaction_effects = 1,
    checkpoint_summary = 2,
    personal_message = 3,
    sender_signed_transaction = 4,
    proof_of_possession = 5,
    header_digest = 6,
    bridge_event_unused = 7,
    consensus_block = 8,
};

pub const IntentVersion = enum(u8) {
    v0 = 0,
};

pub const IntentAppId = enum(u8) {
    sui = 0,
    narwhal = 1,
    consensus = 2,
};
