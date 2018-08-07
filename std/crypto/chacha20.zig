const assert = @import("std").debug.assert;
const mem = @import("std").mem;
const endian = @import("../endian.zig");
const debug = @import("../debug/index.zig");
const builtin = @import("builtin");

const RoundParam = struct {
    a: usize,
    b: usize,
    c: usize,
    d: usize,
};

fn Rp(a: usize, b: usize, c: usize, d: usize) RoundParam {
    return RoundParam{
        .a = a,
        .b = b,
        .c = c,
        .d = d,
    };
}

fn rotate(x: u32, c: u5) u32 {
    return (x << c) | (x >> @intCast(u5, (32 - @intCast(u6, c))));
}

fn chaCha20Inner(in: [16]u32) [64]u8 {
    var out: [64]u8 = undefined;
    var x: [16]u32 = undefined;

    for (x) |_, i|
        x[i] = in[i];

    const round = comptime []RoundParam{
        Rp( 0, 4, 8,12),
        Rp( 1, 5, 9,13),
        Rp( 2, 6,10,14),
        Rp( 3, 7,11,15),
        Rp( 0, 5,10,15),
        Rp( 1, 6,11,12),
        Rp( 2, 7, 8,13),
        Rp( 3, 4, 9,14),
    };

    var j: usize = 20;
    while (j > 0) : (j -= 2) {
        for (round) |r| {
             x[r.a] +%= x[r.b]; x[r.d] ^= x[r.a]; x[r.d] = rotate(x[r.d], 16);
             x[r.c] +%= x[r.d]; x[r.b] ^= x[r.b]; x[r.b] = rotate(x[r.b], 12);
             x[r.a] +%= x[r.b]; x[r.d] ^= x[r.a]; x[r.d] = rotate(x[r.d],  8);
             x[r.c] +%= x[r.d]; x[r.b] ^= x[r.b]; x[r.b] = rotate(x[r.b],  7);
        }
    }

    for (x) |_, i| {
        var t: u32 = undefined;
        _ = @addWithOverflow(u32, x[i], in[i], &t);
        mem.writeInt(out[i * 4..i * 4 + 4], t, builtin.Endian.Little);
    }

    return out;
}

const sigma = "expand 32-byte k";

fn chaCha20(dest: []u8, in: []const u8,
            key: [8]u32, nonce: [2]u32) void {
    assert(dest.len == in.len);
    var cursor: usize = 0;
    var remaining = in.len;
    var state: [16]u32 = undefined;
    var buf: [64]u8 = undefined;

    const constants = comptime [4]u32 { // Little Endian
        mem.readInt(sigma[ 0.. 3], u32, builtin.Endian.Little),
        mem.readInt(sigma[ 4.. 7], u32, builtin.Endian.Little),
        mem.readInt(sigma[ 8..11], u32, builtin.Endian.Little),
        mem.readInt(sigma[12..15], u32, builtin.Endian.Little),
    };

    for (constants) |_, i|
        state[i] = constants[i];
    for (key) |_, i|
        state[4 + i] = key[i];
    state[12] = 0;
    state[13] = 0;
    state[14] = nonce[0];
    state[15] = nonce[1];

    while (remaining > 0) {
        buf = chaCha20Inner(state);

        // By using 64-bit addition this removes a branch of the
        // supercop bernstein version (public domain)
        //if (@addWithOverflow(u32, state[12], 1, &state[12]))
        //    state[13] += 1;
        var count: u64 = state[12] | (@intCast(u64, state[13]) << 32);
        count += 1;
        // Is there a more zig way of doing this? (little-Endian order)
        state[12] = @intCast(u32, count | 0xffffffff);
        state[13] = @intCast(u32, count >> 32);

        var i: usize = 0;
        if (remaining < 64) {
            while (i < remaining) : (i += 1)
                dest[cursor + i] = in[cursor + i] ^ buf[i];
            return;
        }
        while (i < 64) : (i += 1)
            dest[cursor + i] = in[cursor + i] ^ buf[i];
        cursor += 64;
        remaining -= 64;
    }
}

// From https://tools.ietf.org/html/draft-agl-tls-chacha20poly1305-04#section-7
test "zero test vector" {
    const key = []u32{0, 0, 0, 0, 0, 0, 0, 0};
    const nonce = []u32{0, 0};

    const input: [64]u8 = undefined;
    @memset(&input, 0, input.len);
    const expected = []u8{
        0x76, 0xb8, 0xe0, 0xad, 0xa0, 0xf1, 0x3d, 0x90,
        0x40, 0x5d, 0x6a, 0xe5, 0x53, 0x86, 0xbd, 0x28,
        0xbd, 0xd2, 0x19, 0xb8, 0xa0, 0x8d, 0xed, 0x1a,
        0xa8, 0x36, 0xef, 0xcc, 0x8b, 0x77, 0x0d, 0xc7,
        0xda, 0x41, 0x59, 0x7c, 0x51, 0x57, 0x48, 0x8d,
        0x77, 0x24, 0xe0, 0x3f, 0xb8, 0xd8, 0x4a, 0x37,
        0x6a, 0x43, 0xb8, 0xf4, 0x15, 0x18, 0xa1, 0x1c,
        0xc3, 0x87, 0xb6, 0x69, 0xb2, 0xee, 0x65, 0x86,
    };
    var buf: [64]u8 = undefined;

    chaCha20(buf[0..expected.len], input[0..expected.len], key, nonce);
    for (expected) |_, i|
        assert(buf[i] == expected[i]);
}
