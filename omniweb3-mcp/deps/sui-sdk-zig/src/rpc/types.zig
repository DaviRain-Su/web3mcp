const std = @import("std");

pub const Balance = struct {
    coinType: []const u8 = "",
    coinObjectCount: u64 = 0,
    totalBalance: []const u8 = "",
    lockedBalance: ?std.json.Value = null,
};

pub const Coin = struct {
    coinType: []const u8 = "",
    coinObjectId: []const u8 = "",
    version: u64 = 0,
    digest: []const u8 = "",
    balance: []const u8 = "",
    previousTransaction: ?[]const u8 = null,
};

pub const CoinMetadata = struct {
    decimals: u8 = 0,
    name: []const u8 = "",
    symbol: []const u8 = "",
    description: []const u8 = "",
    iconUrl: ?[]const u8 = null,
    id: ?[]const u8 = null,
};

pub const SuiObjectResponse = struct {
    data: ?SuiObjectData = null,
    @"error": ?SuiObjectError = null,
};

pub const SuiObjectData = struct {
    objectId: []const u8 = "",
    version: []const u8 = "",
    digest: []const u8 = "",
    type: ?[]const u8 = null,
    owner: ?SuiObjectOwner = null,
    previousTransaction: ?[]const u8 = null,
    storageRebate: ?[]const u8 = null,
    content: ?SuiObjectContent = null,
    bcs: ?std.json.Value = null,
    display: ?std.json.Value = null,
};

pub const SuiObjectOwner = struct {
    AddressOwner: ?[]const u8 = null,
    ObjectOwner: ?[]const u8 = null,
    Shared: ?SuiSharedObject = null,
    Immutable: ?bool = null,
};

pub const SuiSharedObject = struct {
    initial_shared_version: []const u8 = "",
    mutable: ?bool = null,
};

pub const SuiObjectContent = struct {
    dataType: []const u8 = "",
    type: ?[]const u8 = null,
    hasPublicTransfer: ?bool = null,
    fields: ?std.json.Value = null,
    moduleMap: ?std.json.Value = null,
    version: ?[]const u8 = null,
    packageId: ?[]const u8 = null,
};

pub const SuiObjectError = struct {
    code: ?[]const u8 = null,
    @"error": ?[]const u8 = null,
    object_id: ?[]const u8 = null,
};

pub const SuiTransactionBlockResponse = struct {
    digest: []const u8 = "",
    transaction: ?SuiTransactionBlockData = null,
    rawTransaction: ?[]const u8 = null,
    effects: ?SuiTransactionBlockEffects = null,
    events: ?std.json.Value = null,
    objectChanges: ?std.json.Value = null,
    balanceChanges: ?std.json.Value = null,
    timestampMs: ?std.json.Value = null,
    checkpoint: ?std.json.Value = null,
    confirmedLocalExecution: ?bool = null,
};

pub const SuiTransactionBlockData = struct {
    sender: ?[]const u8 = null,
    gasData: ?SuiGasData = null,
    kind: ?std.json.Value = null,
};

pub const SuiGasData = struct {
    payment: ?std.json.Value = null,
    owner: ?[]const u8 = null,
    price: ?[]const u8 = null,
    budget: ?[]const u8 = null,
};

pub const SuiTransactionBlockEffects = struct {
    status: ?std.json.Value = null,
    executedEpoch: ?[]const u8 = null,
    gasUsed: ?std.json.Value = null,
    transactionDigest: ?[]const u8 = null,
    gasObject: ?std.json.Value = null,
    eventsDigest: ?[]const u8 = null,
    dependencies: ?[][]const u8 = null,
    lamportVersion: ?[]const u8 = null,
    changedObjects: ?std.json.Value = null,
    unchangedSharedObjects: ?std.json.Value = null,
    auxiliaryDataDigest: ?[]const u8 = null,
};
