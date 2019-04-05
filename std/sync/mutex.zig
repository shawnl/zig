const std = @import("../std.zig");
const builtin = @import("builtin");
const testing = std.testing;
const SpinLock = std.sync.SpinLock;
const linux = std.os.linux;
const windows = std.os.windows;
const os = std.os;

/// Lock may be held only once. If the same thread
/// tries to acquire the same mutex twice, it deadlocks.
/// (RecursiveMutex avoids this deadlock)
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
                const c = @atomicRmw(i32, &self.mutex.lock, .Sub, 1, .Release);
                if (c != 1) {
                    _ = @atomicRmw(i32, &self.mutex.lock, .Xchg, 0, .Monotonic);
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
            var c = @cmpxchgWeak(i32, &self.lock, 0, 1, .Acquire, .Monotonic) orelse
                return Held{ .mutex = self };
            if (c != 2)
                c = @atomicRmw(i32, &self.lock, .Xchg, 2, .Acquire);
            while (c != 0) {
                const rc = linux.futex_wait(&self.lock, linux.FUTEX_WAIT | linux.FUTEX_PRIVATE_FLAG, 2, null);
                switch (linux.getErrno(rc)) {
                    0, linux.EINTR, linux.EAGAIN => {},
                    linux.EINVAL => unreachable,
                    else => unreachable,
                }
                c = @atomicRmw(i32, &self.lock, .Xchg, 2, .Acquire);
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

/// Lock may be held up to 2**32 times, after which acquire() returns EAGAIN.
/// This type must be initialized at runtime, and then deinitialized when no
/// longer needed, to free resources.
/// If you need static initialization, use std.RecursiveStaticallyInitializedMutex.
/// The Linux implementation is based on mutex3 from
/// https://www.akkadia.org/drepper/futex.pdf
/// When an application is built in single threaded release mode, all the functions are
/// no-ops.
pub const RecursiveMutex = if (builtin.single_threaded)
    struct {
        pub const Held = struct {
            mutex: *Mutex,

            pub fn release(self: Held) void {}
        };
        pub fn init() Mutex {
            return Mutex{};
        }
        pub fn deinit(self: *Mutex) void {}

        pub fn acquire(self: *Mutex) Held {
            return Held{ .mutex = self };
        }
    }
else switch (builtin.os) {
    builtin.Os.linux => struct {
        count: u32, // recursive count
        /// (& ~FUTEX_OWNER_DIED) == 0: unlocked
        /// (& FUTEX_WAITERS) == 0 and (& FUTEX_TID_MASK) > 0: locked, no waiters
        /// (& FUTEX_WAITERS): locked, one or more waiters
        lock: i32,

        pub const Held = struct {
            mutex: *RecursiveMutex,

            pub fn release(self: Held) void {
                if (self.mutex.count > 0) {
                    self.mutex.count -= 1;
                    return;
                }
                const c = @atomicRmw(i32, &self.mutex.lock, .Or, ~i32(linux.FUTEX_TID_MASK), .Release);
                if (@bitCast(u32, c) & linux.FUTEX_WAITERS != 0) {
                    _ = @atomicRmw(i32, &self.mutex.lock, .Xchg, 0, .Monotonic);
                    const rc = linux.futex_wake(&self.mutex.lock, linux.FUTEX_WAKE | linux.FUTEX_PRIVATE_FLAG, 1);
                    switch (linux.getErrno(rc)) {
                        0 => {},
                        linux.EINVAL => unreachable,
                        else => unreachable,
                    }
                }
            }
        };

        pub fn init() RecursiveMutex {
            return RecursiveMutex{
                .lock = 0,
                .count = 0,
            };
        }

        pub fn deinit(self: *RecursiveMutex) void {}

        pub fn acquire(self: *RecursiveMutex) Held {
            var tid = os.Thread.getCurrentId();
            var c = @cmpxchgWeak(i32, &self.lock, 0, tid, .Acquire, .Monotonic) orelse
                return Held{ .mutex = self };
            if (c & linux.FUTEX_TID_MASK == tid) {
                // We already have the lock
                self.count += 1;
                return Held{ .mutex = self };
            } else if (@bitCast(u32, c) & linux.FUTEX_WAITERS != 0) {
                c = @atomicRmw(i32,
                        &self.lock,
                        .Xchg,
                        @bitCast(i32, (@bitCast(u32, tid) & u32(linux.FUTEX_TID_MASK)) | linux.FUTEX_WAITERS),
                        .Acquire
                );
            }
            while (c != 0) {
                const rc = linux.futex_wait(
                    &self.lock,
                    linux.FUTEX_WAIT | linux.FUTEX_PRIVATE_FLAG,
                    @bitCast(i32, @bitCast(u32, tid) & linux.FUTEX_WAITERS),
                    null);
                switch (linux.getErrno(rc)) {
                    0, linux.EINTR, linux.EAGAIN => {},
                    linux.EINVAL => unreachable,
                    else => unreachable,
                }
                c = @atomicRmw(i32,
                        &self.lock,
                        .Xchg,
                        @bitCast(i32, (@bitCast(u32, tid) & u32(linux.FUTEX_TID_MASK)) | linux.FUTEX_WAITERS),
                        .Acquire
                );
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

const TestContext = struct {
    mutex: *Mutex,
    data: u64,

    const incr_count = 10000;
};

test "std.Mutex" {
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
        ctx.data += 1;
        defer held.release();
    }
}

const TestContextRecursive = struct {
    mutex: *RecursiveMutex,
    data: u64,

    const incr_count = 100000;
};


test "std.RecursiveMutex" {
    var mutex = RecursiveMutex.init();
    defer mutex.deinit();

    var context = TestContextRecursive{
        .mutex = &mutex,
        .data = 0,
    };

    if (builtin.single_threaded) {
        workerRecursive(&context);
        testing.expect(context.data == TestContext.incr_count);
    } else {
        const thread_count = 10;
        var threads: [thread_count]*std.os.Thread = undefined;
        for (threads) |*t| {
            t.* = try std.os.spawnThread(&context, workerRecursive);
        }
        for (threads) |t|
            t.wait();

        testing.expect(context.data == thread_count * TestContext.incr_count);
    }
}

fn workerRecursive(ctx: *TestContext) void {
    var i: usize = 0;
    while (i != TestContext.incr_count) : (i += 1) {
        const held = ctx.mutex.acquire();
        const held2 = ctx.mutex.acquire();
        const held3 = ctx.mutex.acquire();
        defer held3.release();
        defer held2.release();
        defer held.release();

        _ = @atomicRmw(u64, &ctx.data, .Add, 1, .SeqCst);
    }
}
