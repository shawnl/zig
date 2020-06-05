const std = @import("std");
const mem = std.mem;
const heap = std.heap;
// Stable in-place sort. O(n) best case, O(pow(n, 2)) worst case. O(1) memory (no allocator required).
// TODO reentrant O(n log n) sort (red-black tree changes the API in ways that are not desirable)
// I do not need a reentrant sort, but this avoids using a global variable to pass state, which is ugly.
// Look at the documentation for qsort_r.
fn insertionSortReentrant(comptime T: type, items: []T, lessThanReentrant: fn (lhs: T, rhs: T, ctx: ?*c_void) bool, ctx: ?*c_void) void {
    var i: usize = 1;
    while (i < items.len) : (i += 1) {
        const x = items[i];
        var j: usize = i;
        while (j > 0 and lessThanReentrant(x, items[j - 1], ctx)) : (j -= 1) {
            items[j] = items[j - 1];
        }
        items[j] = x;
    }
}
const sort = insertionSortReentrant;
const math = std.math;
const assert = std.debug.assert;

const expect = std.testing.expect;

// -------------------------------

pub const KV = extern struct {
    key: [*:0]const u8,
    keyLen: u32,
    value: u32,

    fn init(bytes: [:0]const u8, id: u32) KV {
        return .{
            .key = bytes.ptr,
            .keyLen = @intCast(u32, bytes.len),
            .value = id,
        };
    }

    fn initId(bytes: [:0]const u8, id: Id) KV {
        return .{
            .key = bytes.ptr,
            .keyLen = @intCast(u32, bytes.len),
            .value = @enumToInt(id),
        };
    }
    
    fn getKey(k: *const KV) [:0]const u8 {
        var key: [:0]const u8 = undefined;
        key.ptr = k.key;
        key.len = k.keyLen;
        return key;
    }
};

fn lessThanKV(l: KV, r: KV, ctx: ?*c_void) bool {
    return mem.lessThan(u8, l.getKey(), r.getKey());
}

fn lessThanKVChar(l: KV, r: KV, ctx: ?*c_void) bool {
    const which = @ptrCast(*align(1) isize, ctx).*;
    if (l.keyLen < absOnes(which) or r.keyLen < absOnes(which)) {
        return l.keyLen < r.keyLen;
    }
    const charcmp = blk: {
        if (which >= 0) {
            break :blk math.order(l.key[@intCast(usize, which)], r.key[@intCast(usize, which)]);
        } else {
            const invWhich = ~@bitCast(usize, which) + 1; // plus one because len is one past end
            break :blk math.order(l.getKey()[l.keyLen - invWhich], r.getKey()[r.keyLen - invWhich]);
        }
    };
    if (charcmp == .eq) return mem.lessThan(u8, l.getKey(), r.getKey());
    return charcmp == .lt;
}

fn calculateNextWhich(slice: []const KV) ?isize {
    // we could also cache these from earlier multiways, but it is not necessary
    var whichl: ?usize = 0;
    var whichr: ?usize = 0;
    return calculateNextWhichRecursive(slice, &whichl, &whichr);
}

pub fn maxSlice(comptime T: type, x: []T) T {
    assert(x.len > 0);
    var max: T = x[0];
    var i: usize = 1;
    while (i < x.len) : (i += 1) {
        if (x[i] > max) max = x[i];
    }
    return max;
}

pub fn minSliceWithIndex(comptime T: type, x: []T, outindex: *usize) T {
    assert(x.len > 0);
    var min: T = x[0];
    var i: usize = 1;
    var mini: usize = 0;
    while (i < x.len) : (i += 1) {
        if (x[i] < min) {
            min = x[i];
            mini = i;
        }
    }
    outindex.* = mini;
    return min;
}

// This agressively searches for the best character to switch on out of the first 4 and last 4 characters of each string.
// Because it gives up if it cannot eliminate more than half of the entries the running time of the algorithm is still O(n log n)
fn calculateNextWhichRecursive(slice: []const KV, whichl: *?usize, whichr: *?usize) ?isize {
    if (slice.len <= 3) return null;
    var count = mem.zeroes([8][256]u32);
    for (slice) |e| {
        if (whichl.*) |l| {
            count[3][if (e.keyLen >= l + 4) e.key[l + 3] else 0] += 1;
            count[2][if (e.keyLen >= l + 3) e.key[l + 2] else 0] += 1;
            count[1][if (e.keyLen >= l + 2) e.key[l + 1] else 0] += 1;
            count[0][if (e.keyLen >= l + 1) e.key[l + 0] else 0] += 1;
        }
        if (whichr.*) |r| {
            count[7][if (e.keyLen >= r + 4) e.key[e.keyLen - 4] else 0] += 1;
            count[6][if (e.keyLen >= r + 3) e.key[e.keyLen - 3] else 0] += 1;
            count[5][if (e.keyLen >= r + 2) e.key[e.keyLen - 2] else 0] += 1;
            count[4][if (e.keyLen >= r + 1) e.key[e.keyLen - 1] else 0] += 1;
        }
    }
    var big: [8]u32 = undefined;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        big[i] = maxSlice(u32, count[i][0..]);
        // forbid 2-1-2, 3-1-3, 4-1-4, et cetera.
        // This would be a little clearer if it was below, but up here we just invalidate
        // this selection and might still make a profitable selection.
        if (big[i] * 2 + 1 == slice.len) {
            var notZero: u8 = 0;
            for (count[i][0..]) |c| {
                if (c != 0) notZero += 1;
                if (notZero > 3) break;
            }
            if (notZero == 3) {
                big[i] += 1; // This will invalidate this selection, as it is already on edge in the if above.
            }
        }
    }
    var mini: usize = undefined;
    var min = minSliceWithIndex(u32, big[0..], &mini);
    var ret: ?isize = null;
    // Because this is > there must be at least 3 prongs to the switch.
    if ((slice.len - min) * 2 > slice.len) {
        if (mini < 4) {
            ret = @intCast(isize, whichl.*.? + mini);
        } else {
            ret = ~@bitCast(isize, whichr.*.? + mini - 4);
        }
    }
    if (ret) |r| {
        const sign = if (ret.? >= 0) "+" else "-";
        if (printDebug) std.debug.warn("Total: {:2} <{:2} {:2} {:2} {:2}  - {:2} {:2} {:2} {:2}> Best: {}{} ({})\n", .{slice.len, big[0], big[1], big[2], big[3], big[7], big[6], big[5], big[4], sign, absOnes(ret.?), min});
        return ret;
    }
    if (big[3] * 2 >= slice.len) whichl.* = null;
    if (big[7] * 2 >= slice.len) whichr.* = null;
    if (whichl.*) |l| whichl.* = l + 4;
    if (whichr.*) |r| whichr.* = r + 4;
    if (whichl.* == null and whichr.* == null) return null;
    return calculateNextWhichRecursive(slice, whichl, whichr);
}

fn packBitfield(bools: [256]bool) u256 {
    var ret: u256 = 0;
    var i: u8 = 0;
    while (true) : (i += 1) {
        if (bools[i]) ret |= @as(u256, 1) << i;
        if (i == 255) break;
    }
    return ret;
}

// Passed entries are sorted in place. Aside from the output buffer, does not allocate memory!
// Also guaranteed to generate in O(n log n) time! (compare to O(n^3) of gperf)
//
// Will return -ENOSPC if buffers are not big enough
// May also return -E2BIG in some cases
pub fn stage2_string_bisect_generate(ents: [*]KV, entriesLen: usize, resultBuffer: [*]u8, resultBufferLen: usize) callconv(.C) i64 {
    var bump = std.heap.FixedBufferAllocator.init(resultBuffer[0..resultBufferLen]);
    var allocator = &bump.allocator;
    var entries: []KV = undefined;
    entries.ptr = ents;
    entries.len = entriesLen;
    generate(allocator, entries) catch |err| switch (err) {
    error.OutOfRange => return -std.os.E2BIG,
    error.OutOfMemory => return -std.os.ENOSPC,
    error.InvalidValue => return -std.os.EINVAL,
    };
    return @intCast(i64, bump.end_index);
}

// stringBisectOnly is because the multi-way interpreter relies heavily on popcnt, and
// architectures without popcnt might want to just use a simpler 2-way bisection,
// instead of the fancier multi-way character bisection.
                // Actually FixedBufferAllocator.
fn generateReal(allocator: *mem.Allocator, entries: []KV, twoWayBisectOnly: bool) !void {
    var out1 = try allocator.alloc(u8, @sizeOf(InterpHeader));
    var hdr = @ptrCast(*align(1) InterpHeader, out1.ptr);
    var maxval: u32 = 0;
    for (entries) |e| {
        if (e.value == 0) return error.InvalidValue;
        if (maxval < e.value) maxval = e.value;
    }
    if (maxval < 128) {
        hdr.valueSize = 1;
    } else if (maxval < 128 * 128) {
        hdr.valueSize = 2;
    } else if (maxval < 128 * 128 * 128) {
        hdr.valueSize = 3;
    } else if (maxval < 128 * 128 * 128 * 128) {
        hdr.valueSize = 4;
    } else if (maxval < 128 * 128 * 128 * 128 * 128) {
        hdr.valueSize = 5;
    } else {
        return error.OutOfRange;
    }
    if (twoWayBisectOnly) {
        _ = try genBisect(allocator, entries, hdr.valueSize);
    } else {
        _ = try genMultiway(allocator, entries, true, hdr.valueSize);
    }
    var bump = @fieldParentPtr(heap.FixedBufferAllocator, "allocator", allocator);
    hdr.length = htole(u32, @intCast(u32, bump.end_index));
}

fn generate(allocator: *mem.Allocator, entries: []KV) !void {
    return generateReal(allocator, entries, false);
}

fn genBisect(allocator: *mem.Allocator, entries: []KV, valueSize: u8) !void {
    sort(KV, entries, lessThanKV, null); // TODO check duplicate values
    if (printDebug) {
        std.debug.warn("bisect: ", .{});
        for (entries) |e| {
                std.debug.warn("{} ", .{e.key});
        }
        std.debug.warn("\n", .{});
    }
    var l: u32 = 0;
    for (entries) |kv| {
        l += valueSize + kv.keyLen + 1;
    }
    var fulll = l + @sizeOf(StringBisectHeader);
    var out = try allocator.alloc(u8,  fulll);
    var cur = out[0..];
    var bhdr = @ptrCast(*align(1) StringBisectHeader, cur.ptr);
    bhdr.length = l + 1;
    bhdr.typ = .StringBisect;
    bhdr.zerobyte = '\x00';
    cur = cur[@sizeOf(StringBisectHeader)..];
    for (entries) |kv| {
        var value = kv.value;
        var i: usize = 0;
        assert(valueSize <= 5);
        while (i < valueSize) : (i += 1) {
            cur[i] = 0x80 + @as(u8, @truncate(u7, value));
            value = value >> 7;
        }
        assert(value == 0);
        cur = cur[i..];
        mem.copy(u8, cur, kv.key[0..kv.keyLen + 1]);
        cur = cur[kv.keyLen + 1..];
    }
    return;
}

fn genString(allocator: *mem.Allocator, entry: KV, valueSize: u8) !void {
    var typ = try allocator.alignedAlloc(SectionType, 1, 1);
    typ[0] = .String;
    assert(valueSize <= 5);
    var size = try allocator.alloc(u8, valueSize);
    var value = entry.value;
    var i: usize = 0;
    while (i < valueSize) : (i += 1) {
        size[i] = 0x80 + @as(u8, @truncate(u7, value));
        value = value >> 7;
    }
    assert(value == 0);
    var key = try allocator.alloc(u8, entry.keyLen + 1);
    mem.copy(u8, key, entry.key[0..entry.keyLen + 1]);
}

fn genMultiway(allocator: *mem.Allocator, entries: []KV, verify: bool, valueSize: u8) !void {
    var bump = @fieldParentPtr(heap.FixedBufferAllocator, "allocator", allocator);
    const bumpbase = bump.end_index;
    var typ: SectionType = if (verify) .MultiwayWithVerify else .MultiwayWithoutVerify;
    var which_maybe = calculateNextWhich(entries);
    if (which_maybe == null) {
        return try genBisect(allocator, entries, valueSize);
    }
    var which = which_maybe.?;
    sort(KV, entries, lessThanKVChar, &which);
    var bitfield: [256]bool = [_]bool{false} ** 256;
    var singleStrsLen: usize = 0;
    var numPtrs: usize = 0;
    var i: usize = 0;
    var gotnull = false;
    while (entries.len > i) {
        var k: usize = i;
        if (gotnull == false and entries[i].keyLen < absOnes(which)) {
            gotnull = true;
            bitfield[0] = true;
            numPtrs += 1;
            i += 1;
            continue;
        }
        if (which >= 0) {
            while (entries.len > k + 1 and entries[i].key[@intCast(usize, which)] == entries[k + 1].key[@intCast(usize, which)]) : (k += 1) {}
            bitfield[entries[i].key[@intCast(usize, which)]] = true;
        } else {
            const invWhich = ~@bitCast(usize, which) + 1; // Plus one because len is one past end
            while (entries.len > k + 1 and entries[i].key[entries[i].keyLen - invWhich] == entries[k + 1].key[entries[k + 1].keyLen - invWhich]) : (k += 1) {}
            bitfield[entries[i].key[entries[i].keyLen - invWhich]] = true;
        }
        numPtrs += 1;
        i = k + 1;
    }
    var ptrSize: u8 = 2;
    const ptrType: type = u16;
    const strOff: usize = @sizeOf(MultiwayHeader) + ptrSize * numPtrs;
    var strCur = strOff;
    const out = try allocator.alloc(u8, strOff);
    const hdr = @ptrCast(*align(1) MultiwayHeader, out);
    const ptrs = @ptrCast([*]align(1) ptrType, out[@sizeOf(MultiwayHeader)..]);
    hdr.ptrSize = .SizeTwo;
    hdr.typ = typ;
    hdr.which = @intCast(i16, which);
    hdr.bitfield = packBitfield(bitfield);
    i = 0;
    var u: usize = 0;
    while (entries.len > i) : (u += 1) {
        var k: usize = i;
        while (entries.len > k + 1) {
            if (entries[i].keyLen < absOnes(which)) {
                if (entries[i].keyLen < absOnes(which) and entries[k + 1].keyLen < absOnes(which)) {
                    k += 1;
                    continue;
                }
                break;
            }
            if (entries[k + 1].keyLen < absOnes(which)) {
                break;
            }
            if ((which >= 0 and (entries[i].key[@bitCast(usize, which)] == entries[k + 1].key[@bitCast(usize, which)])) or
                (which < 0 and (entries[i].key[entries[i].keyLen - (absOnes(which) + 1)] == entries[k + 1].key[entries[k + 1].keyLen - (absOnes(which) + 1)]))) {
                k += 1;
                continue;
            }
            break;
        }
        if (k == i) {
            if (verify) {
                if (math.maxInt(ptrType) < bump.end_index - bumpbase) return error.OutOfRange;
                ptrs[u] = @intCast(ptrType, bump.end_index - bumpbase);
                try genString(allocator, entries[i], valueSize);
            } else {
                if (math.maxInt(ptrType) < entries[i].value) return error.OutOfRange; // might be off by one
                ptrs[u] = @intCast(ptrType, entries[i].value);
            }
        } else if (k - i <= 3) {
            if (math.maxInt(ptrType) < bump.end_index - bumpbase) return error.OutOfRange;
            ptrs[u] = @intCast(ptrType, bump.end_index - bumpbase);
            try genBisect(allocator, entries[i..k+1], valueSize);
        } else {
            if (math.maxInt(ptrType) < bump.end_index - bumpbase) return error.OutOfRange;
            ptrs[u] = @intCast(ptrType, bump.end_index - bumpbase);
            genMultiway(allocator, entries[i..k+1], verify, valueSize) catch unreachable;
        }
        i = k + 1;
    }
}


////// Tests
    const Id = enum {
        Keyword_align = 1,
        Keyword_allowzero,
        Keyword_and,
        Keyword_asm,
        Keyword_async,
        Keyword_await,
        Keyword_break,
        Keyword_callconv,
        Keyword_catch,
        Keyword_comptime,
        Keyword_const,
        Keyword_continue,
        Keyword_defer,
        Keyword_else,
        Keyword_enum,
        Keyword_errdefer,
        Keyword_error,
        Keyword_export,
        Keyword_extern,
        Keyword_false,
        Keyword_fn,
        Keyword_for,
        Keyword_if,
        Keyword_inline,
        Keyword_noalias,
        Keyword_noinline,
        Keyword_nosuspend,
        Keyword_null,
        Keyword_or,
        Keyword_orelse,
        Keyword_packed,
        Keyword_anyframe,
        Keyword_pub,
        Keyword_resume,
        Keyword_return,
        Keyword_linksection,
        Keyword_struct,
        Keyword_suspend,
        Keyword_switch,
        Keyword_test,
        Keyword_threadlocal,
        Keyword_true,
        Keyword_try,
        Keyword_undefined,
        Keyword_union,
        Keyword_unreachable,
        Keyword_usingnamespace,
        Keyword_var,
        Keyword_volatile,
        Keyword_while,
    };
const tests = [_][]KV{test1[0..], test2[0..], test3[0..], test4[0..]};
var test1 = [_]KV{
            KV.init("zipline", 3),
            KV.init("zip", 4),
        };
var test2 = [_]KV{
        KV.init("ab", 4),
        KV.init("foo", 1),
        KV.init("world", 2),
        KV.init("zip", 3),
        };
var test3 = [_]KV{
        KV.init("ab", 5),
        KV.init("foo", 1),
        KV.init("world", 2),
        KV.init("zip", 3),
        KV.init("zipline", 4),
        };
var test4 = [_]KV{
        KV.initId("align", .Keyword_align),
        KV.initId("allowzero", .Keyword_allowzero),
        KV.initId("and", .Keyword_and),
        KV.initId("anyframe", .Keyword_anyframe),
        KV.initId("asm", .Keyword_asm),
        KV.initId("async", .Keyword_async),
        KV.initId("await", .Keyword_await),
        KV.initId("break", .Keyword_break),
        KV.initId("callconv", .Keyword_callconv),
        KV.initId("catch", .Keyword_catch),
        KV.initId("comptime", .Keyword_comptime),
        KV.initId("const", .Keyword_const),
        KV.initId("continue", .Keyword_continue),
        KV.initId("defer", .Keyword_defer),
        KV.initId("else", .Keyword_else),
        KV.initId("enum", .Keyword_enum),
        KV.initId("errdefer", .Keyword_errdefer),
        KV.initId("error", .Keyword_error),
        KV.initId("export", .Keyword_export),
        KV.initId("extern", .Keyword_extern),
        KV.initId("false", .Keyword_false),
        KV.initId("fn", .Keyword_fn),
        KV.initId("for", .Keyword_for),
        KV.initId("if", .Keyword_if),
        KV.initId("inline", .Keyword_inline),
        KV.initId("noalias", .Keyword_noalias),
        KV.initId("noasync", .Keyword_nosuspend), // TODO: remove this
        KV.initId("noinline", .Keyword_noinline),
        KV.initId("nosuspend", .Keyword_nosuspend),
        KV.initId("null", .Keyword_null),
        KV.initId("or", .Keyword_or),
        KV.initId("orelse", .Keyword_orelse),
        KV.initId("packed", .Keyword_packed),
        KV.initId("pub", .Keyword_pub),
        KV.initId("resume", .Keyword_resume),
        KV.initId("return", .Keyword_return),
        KV.initId("linksection", .Keyword_linksection),
        KV.initId("struct", .Keyword_struct),
        KV.initId("suspend", .Keyword_suspend),
        KV.initId("switch", .Keyword_switch),
        KV.initId("test", .Keyword_test),
        KV.initId("threadlocal", .Keyword_threadlocal),
        KV.initId("true", .Keyword_true),
        KV.initId("try", .Keyword_try),
        KV.initId("undefined", .Keyword_undefined),
        KV.initId("union", .Keyword_union),
        KV.initId("unreachable", .Keyword_unreachable),
        KV.initId("usingnamespace", .Keyword_usingnamespace),
        KV.initId("var", .Keyword_var),
        KV.initId("volatile", .Keyword_volatile),
        KV.initId("while", .Keyword_while),
    };

const printDebug = false;

test "construct varius bisections" {
    var buf: [40960]u8 = undefined;
    var bump = std.heap.FixedBufferAllocator.init(buf[0..]);
    var allocator = &bump.allocator;
    for (tests) |t, i| {
        try generate(allocator, t);
        var file = bump.buffer[0..bump.end_index];
        if (printDebug) hexDump("result", file);
        for (t) |search| {
            var res = interp_start(file, search.getKey());
            if (res) |r| {
                expect(r == search.value);
            } else {
                return error.NotFound;
            }
        }
        bump.end_index = 0;
    }
}

const array = false; // This is for constructing something that can be copied into a source file as an array of bytes.

pub fn hexDump(name: []const u8, buf: []const u8) void {
    std.debug.warn("{}:\n", .{name});
    var off: usize = 0;
    while (off < buf.len) : (off += 16) {
        var this: usize = 0;
        if (!array) std.debug.warn("{x:0<4}  ", .{off});
        while (this < 16) : (this += 1) {
            if (buf.len <= off+this) {
                std.debug.warn("   ", .{});
                continue;
            }
            var thischar = buf[off+this];
            std.debug.warn(if (array) "0x{x:0<2}, " else "{x:0<2} ", .{thischar});
        }
        this = 0;
        while (!array and this < 16) : (this += 1) {
            if (buf.len <= off+this) {
                std.debug.warn(" ", .{});
                continue;
            }
            var thischar = buf[off+this];
            if (std.ascii.isPrint(thischar)) {
                std.debug.warn("{c}", .{thischar});
            } else {
                std.debug.warn(".", .{});
            }
        }
        std.debug.warn("\n", .{});
    }
}

//////////////////////////////////////////////////

const InterpHeader = packed struct {
    length: u32,
    valueSize: u8, // Width of values in StringBisect sections. Values cannot contain null bytes. base-128, 0x80-0xff.
};

const SectionType = enum(u8) {
    String = 0,
    StringBisect = 1,
    MultiwayWithVerify = 2,
    MultiwayWithoutVerify = 3,
};

const StringBisectHeader = packed struct {
    typ: SectionType = .StringBisect,
    length: u32,
    zerobyte: u8 = 0,
};

const PointerSize = enum(u8) {
    SizeTwo = 1, // Currently we are only generating .SizeTwo
    SizeFour = 2,
};

const MultiwayHeader = packed struct {
    typ: SectionType,
    ptrSize: PointerSize,
    which: i16,
    bitfield: u256,
    // blah....
};

fn letoh(comptime T: type, orig: T) T {
    return switch (std.builtin.endian) {
        .Little => orig,
        .Big => @byteSwap(T, orig),
    };
}

fn htole(comptime T: type, orig: T) T {
    return switch (std.builtin.endian) {
        .Little => orig,
        .Big => @byteSwap(T, orig),
    };
}

fn interp_recursive(file: []const u8, search: [:0]const u8, valueSize: u8) ?u32 {
    var typ: SectionType = @intToEnum(SectionType, file[0]);
    {switch (typ) {
    .MultiwayWithVerify => {
        var hdr = @ptrCast(*align(1) const MultiwayHeader, file.ptr);
        assert(hdr.typ == .MultiwayWithVerify);
        var which = letoh(i16, hdr.which);
        var char: u8 = undefined;
        var bitfield: u256 = letoh(u256, hdr.bitfield);

        if (search.len < absOnes(@intCast(isize, which))) {
            char = 0;
        } else {
            if (which >= 0) {
                char = search[@intCast(usize, which)];
            } else {
                char = search[(search.len - 1) - absOnes(@intCast(isize, which))];
            }
        }

        if (((@as(u256, 1) << @intCast(u8, char)) & bitfield) == 0) {
            return null;
        }

        var mask = @as(u256, 0xffffffff_ffffffff_ffffffff_ffffffff_ffffffff_ffffffff_ffffffff_ffffffff) >> 255 - char;
        var ptrWhich = @popCount(u256, mask & bitfield);
        ptrWhich -= 1; // this is one-indexed, convert to zero-indexed
        var ptrField = file[@sizeOf(MultiwayHeader)..];
        var ptrOff: usize = @as(u32, ptrWhich) << @intCast(u5, @enumToInt(hdr.ptrSize));
        var jump = letoh(u32, @ptrCast(*align(1) const u32, ptrField[ptrOff..].ptr).*);
        if (hdr.ptrSize == .SizeTwo) jump = jump & 0xffff;
        //std.debug.warn("ptrWhich {} {x} {x} {x} {x} {x} {x} {x} {x} {x}\n", .{ptrWhich, jump, mask[0], mask[1], mask[2], mask[3], bitfield[0], bitfield[1], bitfield[2], bitfield[3]});
        return interp_recursive(file[@intCast(usize, jump)..], search, valueSize);
    },
    .MultiwayWithoutVerify => unreachable,
    .StringBisect => {
        var hdr = @ptrCast(*align(1) const StringBisectHeader, file.ptr);
        assert(hdr.length + @sizeOf(StringBisectHeader) - 1 <= file.len);
       // std.debug.warn("hdr.length: {}\n",.{hdr.length});
       // hexDump("bisect", file[@sizeOf(StringBisectHeader) - 1..@sizeOf(StringBisectHeader) + hdr.length - 1]);
        var res = bisectWay(valueSize, file[@sizeOf(StringBisectHeader)-1..@sizeOf(StringBisectHeader)-1 + hdr.length], search);
        if (res) |r| {
            var value: u64 = 0;
            var string: []const u8 = undefined;
            var n: u6 = 0;
            while (n < valueSize) : (n += 1) {
                value |= @as(u64, r[n] & 0x7f) << (n * 7);
            }
            string = r[valueSize..];
            assert(std.mem.eql(u8, string, search));
            return @truncate(u32, value);
        }
        return null;
    },
    .String => {
        assert(file[0] == @enumToInt(SectionType.String));
        //hexDump("string", file);
        var value: u64 = 0;
        var r = file[1..];
        var string: []const u8 = r[valueSize..];
        var len = port_strlen(string.ptr);
        //std.debug.warn("{} {} {}\n", .{len, search.len, search});
        if (len == search.len and port_memcmp(string.ptr, search.ptr, len + 1) == 0) {
            var n: u6 = 0;
            while (n < valueSize) : (n += 1) {
                value |= @as(u64, r[n] & 0x7f) << (n * 7);
            }
            return @truncate(u32, value);
        } else {
            return null;
        }
    },
    }}
}

pub fn interp_start(file: []const u8, search: [:0]const u8) ?u32 {
    var hdr = @ptrCast(*align(1) const InterpHeader, file.ptr);
    assert(hdr.length == file.len);
    return interp_recursive(file[@sizeOf(InterpHeader)..], search, hdr.valueSize);
}

// Libraries

/// Returns the absolute value of the ones-complement integer parameter.
/// Result is an unsigned integer.
pub fn absOnes(x: isize) usize {
    if (x < 0) {
        return ~@bitCast(usize, x);
    } else {
        return @bitCast(usize, x);
    }
}

// The following algorithm comes from http://pts.github.io/pts-line-bisect/line_bisect_evolution.html
// It bisects sorted strings, packed together with a '\x00' delimeter, and a prefix of a set number of bytes.
// Note that strings that are a subset of other strings come *before*.

const use_strlen = false;
const use_memcmp = true; // LLVM needs this, so we can rely on it being there.

extern fn memcmp([*]allowzero const u8, [*]allowzero const u8, usize) c_int;
extern fn strlen([*]allowzero const u8) usize;

// We don't really want this anyways because our strings are generally quite short.
fn port_strlen(str: [*]allowzero const u8) usize {
    if (use_strlen) {
        return strlen(str);
    } else {
        var res: usize = 0;
        // this is bounded by the sanity check that the last byte is null in bisectSearch
        while (true) : (res += 1) {
            if (str[res] == '\x00') break;
        }
        return res;
    }
}

fn port_memcmp(vl: [*]allowzero const u8, vr: [*]allowzero const u8, n: usize) c_int {
    if (use_memcmp) {
        return memcmp(vl, vr, n);
    } else {
        var l = vl;
        var r = vr;
        while (n > 0 and l.* == r.*) : (n -= 1) {
            l = l + 1;
            r = r + 1;
        }
        if (n > 0) return l.* -% r.*;
        return 0;
    }
}

fn getFofs(file: []const u8, _off: usize) usize {
    var off = _off;
    if (off <= 0) return 0;
    if (off > file.len) return file.len;
    off -= 1;
    var strl = port_strlen(file[off..].ptr);
    off += strl;
    return off + 1;
}

fn compareLine(file: []const u8, _off: usize, search: [:0]const u8) c_int {
    var off = _off;
    if (file.len <= off + 2) return 1; // EOF
    const compareLen = if (search.len < file.len - off) search.len else file.len - off;
    return port_memcmp(file.ptr + off, search.ptr, compareLen + 1);
}

fn bisectWay(valueLn: usize, file: []const u8, search: [:0]const u8) ?[]const u8 {
    var lo: usize = 0;
    var hi = file.len;
    var mid: usize = undefined;
    if (hi > file.len) hi = file.len;
    if (lo >= hi) {
        var off = getFofs(file, lo);
        return file[off..off + search.len];
    }
    var lastwasgt: bool = false; // the optimizer should use this to weave the control flow
    var lastfofs: usize = @bitCast(usize, @as(isize, -1));
    while (true) {
        mid = (lo + hi) >> 1;
        var fofs = getFofs(file, mid);
        // This algorithm comes from http://pts.github.io/pts-line-bisect/line_bisect_evolution.html
        // but this next line is an improvement as we are generally dealing with small bisections,
        // and we always start with a null.
        // Check to avoid comparing the same string (generally the first) more than once,
        // saving a few memcmp() calls.
        if (lastwasgt and fofs == lastfofs) {
            assert(fofs > 1); // should never hit the first string twice
            var newfofs = fofs - 2;
            while (true) {
                if (file[newfofs] == 0) break;
                fofs = newfofs;
                newfofs -= 1;
            }
        }
        lastfofs = fofs;
        const midf = fofs + valueLn;
        const cmp = compareLine(file, midf, search); // EOF is GreaterThan
//        var cmpstring: []const u8 = "EQ";
//        if (cmp > 0) cmpstring = "GT";
//        if (cmp < 0) cmpstring = "LT";
//std.debug.warn("cmp {} {}, {} {} {} {} {}\n", .{cmpstring, fofs, mid, midf, lo, hi, search});
        if (cmp > 0) {
            lastwasgt = true;
            hi = mid;
        } else if (cmp < 0) {
            lastwasgt = false;
            lo = mid + 1;
        } else { // equal
            var off = midf;
            return file[off - valueLn..off + search.len];
        }
        if (lo < hi) continue;
        break;
    }
    return null;
}

fn bisectSearch(file: []const u8, search: [:0]const u8) !?[]const u8 {
    if (file[file.len - 1] != '\x00') return error.EINVAL;
    return bisectWay(0, file, search);
}

// The else prong resolves to 0 (!)
export fn __string_bisect_interp(file: [*]const u8, search: [*:0]const u8, searchLen: usize) callconv(.C) u32 {
    var hdr = @ptrCast(*align(1) const InterpHeader, file);
    var res = interp_recursive(file[@sizeOf(InterpHeader)..letoh(u32, hdr.length)], search[0..searchLen:0], hdr.valueSize);
    if (res) |r| {
        return r;
    } else {
        return 0; // !
    }
}
