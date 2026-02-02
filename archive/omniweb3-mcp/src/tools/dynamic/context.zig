///! Global context for dynamic tool handlers
///!
///! Since MCP tool handlers cannot carry context, we use a global
///! registry to map tool names to their metadata.

const std = @import("std");
const DynamicToolRegistry = @import("./registry.zig").DynamicToolRegistry;

/// Global registry pointer (set during initialization)
var global_registry: ?*const DynamicToolRegistry = null;

/// Set the global registry (called during registerAll)
pub fn setGlobalRegistry(registry: *const DynamicToolRegistry) void {
    global_registry = registry;
}

/// Get the global registry
pub fn getGlobalRegistry() ?*const DynamicToolRegistry {
    return global_registry;
}
