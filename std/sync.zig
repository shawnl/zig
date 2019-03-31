pub const Mutex = @import("sync/mutex.zig").Mutex;
pub const StaticallyInitializedMutex = @import("sync/statically_initialized_mutex.zig").StaticallyInitializedMutex;
pub const Stack = @import("sync/stack.zig").Stack;
pub const Queue = @import("sync/queue.zig").Queue;
pub const Int = @import("sync/int.zig").Int;
pub const Spinlock = @import("sync/spinlock.zig").Spinlock;

test "std.sync" {
    _ = @import("sync/mutex.zig");
    _ = @import("sync/statically_initialized_mutex.zig");
    _ = @import("sync/stack.zig");
    _ = @import("sync/queue.zig");
    _ = @import("sync/int.zig");
    _ = @import("sync/spinlock.zig");
}
