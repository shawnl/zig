const std = @import("std.zig");
const builtin = @import("builtin");
const AtomicOrder = builtin.AtomicOrder;
const AtomicRmwOp = builtin.AtomicRmwOp;
const testing = std.testing;
const SpinLock = std.SpinLock;
const linux = std.os.linux;
const windows = std.os.windows;

/// Lock may be held only once. If the same thread
/// tries to acquire the same mutex twice, it deadlocks.
/// This type must be initialized at runtime, and then deinitialized when no
/// longer needed, to free resources.
/// If you need static initialization, use std.StaticallyInitializedMutex.
/// The Linux implementation is based on mutex3 from
/// https://www.akkadia.org/drepper/futex.pdf
/// When an application is built in single threaded release mode, all the functions are
/// no-ops. In single threaded debug mode, there is deadlock detection.
pub const Mutex = if (builtin.single_threaded)
    struct {
        lock: @typeOf(lock_init),

        const lock_init = if (std.debug.runtime_safety) false else {};

        pub const Held = struct {
            mutex: *Mutex,

            pub fn release(self: Held) void {
                if (std.debug.runtime_safety) {
                    self.mutex.lock = false;
                }
            }
        };
        pub fn init() Mutex {
            return Mutex{ .lock = lock_init };
        }
        pub fn deinit(self: *Mutex) void {}

        pub fn acquire(self: *Mutex) Held {
            if (std.debug.runtime_safety and self.lock) {
                @panic("deadlock detected");
            }
            return Held{ .mutex = self };
        }
    }
else switch (builtin.os) {
    builtin.Os.linux => struct {
        /// 0: unlocked
        /// 1: locked, no waiters
        /// 2: locked, one or more waiters
        lock: i32,

        pub const Held = struct {
            mutex: *Mutex,

            pub fn release(self: Held) void {
                const c = @atomicRmw(i32, &self.mutex.lock, AtomicRmwOp.Sub, 1, AtomicOrder.Release);
                if (c != 1) {
                    _ = @atomicRmw(i32, &self.mutex.lock, AtomicRmwOp.Xchg, 0, AtomicOrder.SeqCst);
                    const rc = linux.futex_wake(&self.mutex.lock, linux.FUTEX_WAKE | linux.FUTEX_PRIVATE_FLAG, 1);
                    switch (linux.getErrno(rc)) {
                        0 => {},
                        linux.EINVAL => unreachable,
                        else => unreachable,
                    }
                }
            }
        };

        pub fn init() Mutex {
            return Mutex{ .lock = 0 };
        }

        pub fn deinit(self: *Mutex) void {}

        pub fn acquire(self: *Mutex) Held {
            var c = @cmpxchgWeak(i32, &self.lock, 0, 1, AtomicOrder.Acquire, AtomicOrder.Monotonic) orelse
                return Held{ .mutex = self };
            if (c != 2)
                c = @atomicRmw(i32, &self.lock, AtomicRmwOp.Xchg, 2, AtomicOrder.Acquire);
            while (c != 0) {
                const rc = linux.futex_wait(&self.lock, linux.FUTEX_WAIT | linux.FUTEX_PRIVATE_FLAG, 2, null);
                switch (linux.getErrno(rc)) {
                    0, linux.EINTR, linux.EAGAIN => {},
                    linux.EINVAL => unreachable,
                    else => unreachable,
                }
                c = @atomicRmw(i32, &self.lock, AtomicRmwOp.Xchg, 2, AtomicOrder.Acquire);
            }
            return Held{ .mutex = self };
        }
    },
    // TODO once https://github.com/ziglang/zig/issues/287 (copy elision) is solved, we can make a
    // better implementation of this. The problem is we need the init() function to have access to
    // the address of the CRITICAL_SECTION, and then have it not move.
    builtin.Os.windows => std.StaticallyInitializedMutex,
    else => struct {
        /// TODO better implementation than spin lock.
        /// When changing this, one must also change the corresponding
        /// std.StaticallyInitializedMutex code, since it aliases this type,
        /// under the assumption that it works both statically and at runtime.
        lock: SpinLock,

        pub const Held = struct {
            mutex: *Mutex,

            pub fn release(self: Held) void {
                SpinLock.Held.release(SpinLock.Held{ .spinlock = &self.mutex.lock });
            }
        };

        pub fn init() Mutex {
            return Mutex{ .lock = SpinLock.init() };
        }

        pub fn deinit(self: *Mutex) void {}

        pub fn acquire(self: *Mutex) Held {
            _ = self.lock.acquire();
            return Held{ .mutex = self };
        }
    },
};

// This Mutex can be shared between process, and even between processes of differn't
// architectures. Also, use of this Mutex registers the handle with the kernel so
// that locks will still be released if the process unexpectedly dies, or calls execve().
pub const Shared = switch (builtin.os) {
    builtin.Os.linux => extern struct {
        // IMPORTANT!!!!!! The offset between next and lock is ABI, and is shared to the kernel
        // with set_robust_list(). It is -4.
        count: u32, // Allows recursive locking
        /// (& ~FUTEX_OWNER_DIED) == 0: unlocked
        /// (& FUTEX_WAITERS) == 0 and (& FUTEX_TID_MASK) > 0: locked, no waiters
        /// 2: locked, one or more waiters
        lock: i32,
        next: *linux_robust_list_member, // <======= These point here on the same or other shared locks
        prev: *linux.robust_list_member,

        pub const Held = struct {
            mutex: *Shared,
            owner_died: bool,

            pub fn release(self: Held) void {
                if (self.mutex.count > 0) {
                    self.mutex.count -= 1;
                    return;
                }
                const c = @atomicRmw(i32, &self.mutex.lock, AtomicRmwOp.Or, ~linux.FUTEX_TID_MASK, AtomicOrder.Release);
                if ((c & linux.FUTEX_WAITERS) > 0) {
                    _ = @atomicRmw(i32, &self.mutex.lock, AtomicRmwOp.Xchg, 0, AtomicOrder.SeqCst);
                    const rc = linux.futex_wake(&self.mutex.lock, linux.FUTEX_WAKE | linux.FUTEX_PRIVATE_FLAG, 1);
                    switch (linux.getErrno(rc)) {
                        0 => {},
                        linux.EINVAL => unreachable,
                        else => unreachable,
                    }
                }
                var thread = linux.thread_self();
                // We have to do this atomically so that the kernel never sees a corrupt list
                // if we die (with SIGKILL) in the middle of this instruction
                if (@cmpxchgStrong(*Shared, self.mutex.prev.next, self.mutex, self.next, AtomicOrder.SeqCst, AtomicOrder.SeqCst)) {
                    if ((self.mutex.robust_futex_field & linux.FUTEX_TID_MASK) == linux.thread_self().tid) {
                        @panic("corruption"); // Corrupt robust futex list
                    } else if (builtin.mode == builtin.Mode.Debug) {
                        // Not harmful, so only crash in debug mode
                        @panic("Corrupt robust futex list. Most likely caused by lock held accross fork() and this is the child.");
                    }
                }
                self.mutex.next.prev = self.prev;
            }
        };

        pub fn init() Shared {
            var shared: Shared = undefined;
            shared.lock = 0;
            shared.next.big = 0;
            shared.prev.big = 0;
            shared.count = 0;
            return shared;
        }

        pub fn deinit(self: *Shared) void {}

        pub fn acquire(self: *Shared) Held {
            const tid = linux.thread_self().tid;
            acquire_lock: {
                var c = @cmpxchgWeak(i32, &self.lock, 0, tid, .Acquire, .Monotonic) orelse
                    break :acquire_lock;
                if (c == linux.thread_self.tid) {
                    // We already have this lock
                    self.count += 1;
                    return Held{
                        .mutex = self,
                        .owner_died = false,
                    };
                }
                if (c & linux.FUTEX_WAITERS > 0)
                    c = @atomicRmw(i32, &self.lock, AtomicRmwOp.And, linux.FUTEX_WAITERS, .Acquire);
                while (c != 0) {
                    const rc = linux.futex_wait(&self.lock, linux.FUTEX_WAIT | linux.FUTEX_PRIVATE_FLAG, 2, null);
                    switch (linux.getErrno(rc)) {
                        0, linux.EINTR, linux.EAGAIN => {},
                        linux.EINVAL => unreachable,
                        else => unreachable,
                    }
                    c = @atomicRmw(i32, &self.lock, .Xchg, (tid & linux.FUTEX_TID_MASK) | linux.FUTEX_WAITERS, .Acquire);
                }
            }
            var thread = linux.thread_self();
            _ = @atomicRmw(*void, &thread.list_op_pending, .Xchg, &self.next, .SeqCst);
            _ = @atomicRmw(*void, &self.next, .Xchg, thread.head, .SeqCst);
            _ = @atomicRmw(*void, &@fieldParentPtr(thread.head.prev, .Xchg, self, .SeqCst);
            _ = @atomicRmw(*void, &thread.head, .Xchg, self, .SeqCst);
            _ = @atomicRmw(*void, &thread.list_op_pending, .Xchg, null, .SeqCst);
            return Held{
                .mutex = self,
                .owner_died = (linux.FUTEX_OWNER_DIED & self.robust_futex_field) != 0,
            };
        }
    },
    else => @panic("unimplemented"),
};

const TestContext = struct {
    mutex: *Mutex,
    data: i128,

    const incr_count = 10000;
};

test "std.Mutex" {
    var direct_allocator = std.heap.DirectAllocator.init();
    defer direct_allocator.deinit();

    var plenty_of_memory = try direct_allocator.allocator.alloc(u8, 300 * 1024);
    defer direct_allocator.allocator.free(plenty_of_memory);

    var fixed_buffer_allocator = std.heap.ThreadSafeFixedBufferAllocator.init(plenty_of_memory);
    var a = &fixed_buffer_allocator.allocator;

    var mutex = Mutex.init();
    defer mutex.deinit();

    var context = TestContext{
        .mutex = &mutex,
        .data = 0,
    };

    if (builtin.single_threaded) {
        worker(&context);
        testing.expect(context.data == TestContext.incr_count);
    } else {
        const thread_count = 10;
        var threads: [thread_count]*std.os.Thread = undefined;
        for (threads) |*t| {
            t.* = try std.os.spawnThread(&context, worker);
        }
        for (threads) |t|
            t.wait();

        testing.expect(context.data == thread_count * TestContext.incr_count);
    }
}

fn worker(ctx: *TestContext) void {
    var i: usize = 0;
    while (i != TestContext.incr_count) : (i += 1) {
        const held = ctx.mutex.acquire();
        defer held.release();

        ctx.data += 1;
    }
}
