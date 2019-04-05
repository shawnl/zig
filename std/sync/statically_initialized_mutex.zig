const std = @import("../std.zig");
const builtin = @import("builtin");
const AtomicOrder = builtin.AtomicOrder;
const AtomicRmwOp = builtin.AtomicRmwOp;
const assert = std.debug.assert;
const expect = std.testing.expect;
const windows = std.os.windows;

/// According to the documentation this is a recursive mutex:
/// https://docs.microsoft.com/en-us/windows/desktop/api/synchapi/nf-synchapi-entercriticalsection
/// This type is intended to be initialized statically. If you don't
/// require static initialization, use std.sync.Mutex.
/// On Windows, this mutex allocates resources when it is
/// first used, and the resources cannot be freed.
/// On Linux, this is an alias of std.sync.Mutex
pub const RecursiveStaticallyInitializedMutex = switch (builtin.os) {
    builtin.Os.windows => StaticallyInitializedMutex,
    else => std.sync.RecursiveMutex,
};

pub const StaticallyInitializedMutex = switch (builtin.os) {
    builtin.Os.linux => std.sync.Mutex,
    builtin.Os.windows => struct {
        lock: windows.CRITICAL_SECTION,
        init_once: windows.RTL_RUN_ONCE,

        pub const Held = struct {
            mutex: *StaticallyInitializedMutex,

            pub fn release(self: Held) void {
                windows.LeaveCriticalSection(&self.mutex.lock);
            }
        };

        pub fn init() StaticallyInitializedMutex {
            return StaticallyInitializedMutex{
                .lock = undefined,
                .init_once = windows.INIT_ONCE_STATIC_INIT,
            };
        }

        extern fn initCriticalSection(
            InitOnce: *windows.RTL_RUN_ONCE,
            Parameter: ?*c_void,
            Context: ?*c_void,
        ) windows.BOOL {
            const lock = @ptrCast(*windows.CRITICAL_SECTION, @alignCast(@alignOf(windows.CRITICAL_SECTION), Parameter));
            windows.InitializeCriticalSection(lock);
            return windows.TRUE;
        }

        /// TODO: once https://github.com/ziglang/zig/issues/287 is solved and std.sync.Mutex has a better
        /// implementation of a runtime initialized mutex, remove this function.
        pub fn deinit(self: *StaticallyInitializedMutex) void {
            assert(windows.InitOnceExecuteOnce(&self.init_once, initCriticalSection, &self.lock, null) != 0);
            windows.DeleteCriticalSection(&self.lock);
        }

        pub fn acquire(self: *StaticallyInitializedMutex) Held {
            assert(windows.InitOnceExecuteOnce(&self.init_once, initCriticalSection, &self.lock, null) != 0);
            windows.EnterCriticalSection(&self.lock);
            return Held{ .mutex = self };
        }
    },
    else => std.sync.Mutex,
};

test "std.StaticallyInitializedMutex" {
    const TestContext = struct {
        data: i128,

        const TestContext = @This();
        const incr_count = 10000;

        var mutex = StaticallyInitializedMutex.init();

        fn worker(ctx: *TestContext) void {
            var i: usize = 0;
            while (i != TestContext.incr_count) : (i += 1) {
                const held = mutex.acquire();
                defer held.release();

                ctx.data += 1;
            }
        }
    };

    var direct_allocator = std.heap.DirectAllocator.init();
    defer direct_allocator.deinit();

    var plenty_of_memory = try direct_allocator.allocator.alloc(u8, 300 * 1024);
    defer direct_allocator.allocator.free(plenty_of_memory);

    var fixed_buffer_allocator = std.heap.ThreadSafeFixedBufferAllocator.init(plenty_of_memory);
    var a = &fixed_buffer_allocator.allocator;

    var context = TestContext{ .data = 0 };

    if (builtin.single_threaded) {
        TestContext.worker(&context);
        expect(context.data == TestContext.incr_count);
    } else {
        const thread_count = 10;
        var threads: [thread_count]*std.os.Thread = undefined;
        for (threads) |*t| {
            t.* = try std.os.spawnThread(&context, TestContext.worker);
        }
        for (threads) |t|
            t.wait();

        expect(context.data == thread_count * TestContext.incr_count);
    }
}
