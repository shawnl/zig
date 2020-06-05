// This is a *very* fast non-cryptographic hash that is used in ELF files for the bloom filter,
// (DT_GNU_HASH) and it is well suited for your fast bloom filters too.

const std = @import("std");
const assert = std.debug.assert;

pub fn gnuHashZ(_name: [*:0]const u8) u32 {
    var h: u32 = 5381;

    var name: [*:0]const u8 = _name;
    while (name[0] != 0) : (name += 1) {
        h = (h << 5) +% h +% name[0];
    }

    return h;
}

pub fn gnuHash(name: []const u8) u32 {
    var h: u32 = 5381;

    var i: usize = 0;
    while (i < name.len) : (i += 1) {
        h = (h << 5) +% h +% name[i];
    }

    return h;
}

fn htole(comptime T: type, orig: T) T {
    return switch (std.builtin.endian) {
        .Little => orig,
        .Big => @byteSwap(T, orig),
    };
}

pub const GnuHash = struct {
    const Self = @This();
    pub const block_length = 1;
    pub const digest_length = 4;

    s: u32,

    pub fn init() Self {
        var d: Self = undefined;
        d.reset();
        return d;
    }

    pub fn reset(d: *Self) void {
        d.s = 5381;
    }

    pub fn hash(b: []const u8, out: []u8) void {
        var d = GnuHash.init();
        d.update(b);
        d.final(out);
    }

    pub fn update(d: *Self, b: []const u8) void {
        for (b) |c| {
            d.s = (d.s << 5) +% d.s +% c;
        }
    }

    pub fn final(d: *Self, out: []u8) void {
        assert(out.len == 4);
        var outPtr = @ptrCast(*align(1) u32, out.ptr);
        outPtr.* = htole(u32, d.s);
    }
};

const htest = @import("test.zig");

test "gnuhash single" {
    var printf: [:0]const u8 = "printf"[0..:0];

    assert(gnuHashZ(printf.ptr) == 0x156b2bb8);
    assert(gnuHash(printf) == 0x156b2bb8);

    htest.assertEqualHash(GnuHash, "05150000", "");
    htest.assertEqualHash(GnuHash, "b82b6b15", "printf");
    htest.assertEqualHash(GnuHash, "3f7e967c", "exit");
    htest.assertEqualHash(GnuHash, "a012c2ba", "syscall");
    htest.assertEqualHash(GnuHash, "8ef1e98a", "flapenguin.me");
}

test "gnuhash streaming" {
    var h = GnuHash.init();
    var out: [4]u8 = undefined;

    h.final(out[0..]);
    htest.assertEqual("05150000", out[0..]);

    h.reset();
    h.update("exit");
    h.final(out[0..]);
    htest.assertEqual("3f7e967c", out[0..]);

    h.reset();
    h.update("sys");
    h.update("ca");
    h.update("ll");
    h.final(out[0..]);

    htest.assertEqual("a012c2ba", out[0..]);
}

test "gnuhash aligned final" {
    var block = [_]u8{0} ** GnuHash.block_length;
    var out: [GnuHash.digest_length]u8 = undefined;

    var h = GnuHash.init();
    h.update(&block);
    h.final(out[0..]);
}
