const std = @import("std");
const linux = std.os.linux;
const math = std.math;
const rb = std.rb;
const Allocator = mem.Allocator;
const assert = std.debug.assert;
const builtin = @import("builtin");

/// Lockless circular buffer of power of 2 size, up to 2 ** 29 bytes or 512MiB
/// Only having one writer and one reader makes this fairly simple,
/// and allows to use solely AtomicOrder.SeqCst.
pub const CircBuf = struct {
    circle: [*]u8, // No point making this a slice, as that would only encourage incorrect non-circular usage
    size_log_2: u5,

    /// To signal EOF the writer marks "written" as having waiters.
    /// TODO makes these refer to 4KiB blocks, but then EOF gets more complicated, as the exact size must be preserved.
    read: *i32,
    writen: *i32,

    pub fn getRead(self: *CircBuf, comptime T: type) T {
        assert(@typeInfo(T).Type == builtin.TypeId.Int);
        assert(@typeInfo(T).Int.bits == self.size_log_2);
        assert(@typeInfo(T).Int.is_signed == false);

        var read = @atomicLoad(i32, &self.read, .SeqCst);
        assert(!(read < 0));
        return @truncate(T, read);
    }

    pub fn updateAsWriter(self: *CircBuf, comptime T: type, writen: T, is_eof: bool) T {
        assert(@typeInfo(T).Type == builtin.TypeId.Int);
        assert(@typeInfo(T).Int.bits == self.size_log_2);
        assert(@typeInfo(T).Int.is_signed == false);

        // Read this before waiting
        var read = @atomicLoad(i32, &self.read, .SeqCst);
        assert(!(read < 0));

        // No point waking anyone up if the buffer is empty
        if (@truncate(T, read) == writen) return @truncate(T, read);

        var waiter_bit: i32 = if (is_eof) math.minInt(i32) else 0;

        const old_writen = @atomicRmw(i32, &self.writen, .Xchg, i32(writen) | waiter_bit, .SeqCst);
        if (old_writen < 0) linux.futex_wake(&self.writen, linux.FUTEX_WAKE | linux.FUTEX_PRIVATE_FLAG, 1);
        if (writen -% 1 == @truncate(T, read)) {
            // Buffer is full
            while (true) {
                const new_read = @atomicRmw(i32, &self.read, .Or, math.minInt(i32), .SeqCst);
                if (@truncate(T, new_read) > @truncate(T, read)) {
                    // Read made forward progress during this call, and could have tried to wake us up after we set the
                    // waited flag, but before taking the lock. If we lock now we could deadlock.
                    return @truncate(T, new_read);
                }
                var ret = linux.getErrno(linux.futex_wait(&self.read, linux.FUTEX_WAIT | linux.FUTEX_PRIVATE_FLAG, new_read, null));
                if (ret != 0) {
                    if (ret != linux.EINVAL) @panic("unexpected error");
                    // self.read changed before sleeping
                    continue;
                }
                // Got wake up
                return @atomicRmw(i32, &self.read, .SeqCst);
            }
        }
        return @truncate(T, read);
    }

    /// On EOF will return read (immediately).
    pub fn updateAsReader(self: *CircBuf, comptime T: type, read: T) T {
        assert(@typeInfo(T).Type == builtin.TypeId.Int);
        assert(@typeInfo(T).Int.bits == self.size_log_2);
        assert(@typeInfo(T).Int.is_signed == false);

        // Read this before waiting
        var writen = @atomicLoad(i32, &self.writen, .SeqCst);
        // EOF
        if (writen < 0) return @truncate(T, writen);
        // No point waking anyone up when the buffer is full
        if (@truncate(T, writen) -% 1 == read) return @truncate(T, writen);

        const old_read = @atomicRmw(i32, &self.read, .Xchg, i32(read), .SeqCst);
        if (old_read < 0) linux.futex_wake(&self.read, linux.FUTEX_WAKE | linux.FUTEX_PRIVATE_FLAG, 1);
        if (read == @truncate(T, writen)) {
            // Buffer is empty
            while (true) {
                const new_written = @atomicRmw(i32, &self.written, .Or, math.minInt(i32), .SeqCst);
                if (@truncate(T, new_written) > @truncate(T, written)) {
                    // Write made forward progress during this call, and could have tried to wake us up after we set the
                    // waited flag, but before taking the lock. If we lock now we could deadlock.
                    return @truncate(T, new_written);
                }
                var ret = linux.getErrno(linux.futex_wait(&self.writen, linux.FUTEX_WAIT | linux.FUTEX_PRIVATE_FLAG, new_writen, null));
                if (ret != 0) {
                    if (ret != linux.EINVAL) @panic("unexpected error");
                    // self.writen changed before sleeping
                    continue;
                }
                // Got wake up
                return @atomicRmw(i32, &self.writen, .SeqCst);
            }
        }
        return @truncate(T, writen);
    }

    pub fn free(self: *CircBuf, allocator: *Allocator) void {
        allocator.free(self.buf);
    }

    /// Caller must free by calling .free(allocator)
    /// 12:       4KiB
    /// 13:       8KiB
    /// 14:      16KiB
    /// 15:      32KiB
    /// 16:      64KiB
    /// 17:     128KiB
    /// 18:     256KiB
    /// 19:     512KiB
    /// 20:    1   MiB
    /// 21:    2   MiB
    /// 22:    4   MiB
    /// 23:    8   MiB
    /// 24:   16   MiB
    /// 25:   32   MiB
    /// 26:   64   MiB
    /// 27:  128   MiB
    /// 28:  256   MiB
    /// 29:  512   MiB
    /// 30: 1      GiB // Must use initRaw() due to a LLVM limitation
    pub fn init(allocator: *Allocator, size: u5) !CircBuf {
        assert(size <= 29); // This is a limitation of LLVM, and thus the allocator interface
        return initRaw(try allocator.alloc(2 ** size, 2 ** size), size);
    }

    pub fn initRaw(buf: []u8, size: u5) CircBuf {
        assert(size >= 1);
        assert(size <= 30);
        assert(buf.len == 2 ** u32(size));
        assert((@ptrToInt(buf.ptr) % (2 ** u32(size))) == 0);

        return CircBuf{
            .circle = buf.ptr,
            .size_log_2 = size,
            .read = 0,
            .writen = 0,
        };
    }

    /// This is for when your reader takes a *sync.CircBuf, but you already have the whole input.
    /// Caller assures buf has sufficient alignment for reader
    /// updateAsReader() may only be called once, and updateAsWriter() may not be called.
    pub fn initFake(buf: []const u8) CircBuf {
        return CircBuf{
            .circle = buf.ptr,
            .size_log_2 = 30,
            .read = 0,
            .writen = buf.len - 1,
        };
    }
};
