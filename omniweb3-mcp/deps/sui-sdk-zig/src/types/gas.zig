pub const GasCostSummary = struct {
    computation_cost: u64,
    storage_cost: u64,
    storage_rebate: u64,
    non_refundable_storage_fee: u64,

    pub fn encodeBcs(self: GasCostSummary, writer: *bcs.Writer) !void {
        try writer.writeU64(self.computation_cost);
        try writer.writeU64(self.storage_cost);
        try writer.writeU64(self.storage_rebate);
        try writer.writeU64(self.non_refundable_storage_fee);
    }

    pub fn decodeBcs(reader: *bcs.Reader) !GasCostSummary {
        return .{
            .computation_cost = try reader.readU64(),
            .storage_cost = try reader.readU64(),
            .storage_rebate = try reader.readU64(),
            .non_refundable_storage_fee = try reader.readU64(),
        };
    }
};

const bcs = @import("bcs.zig");
