const std = @import("std");
const mem = std.mem;
const builtin = @import("builtin");
const expect = std.testing.expect;

test "implicit cast vector to array - bool" {
    const S = struct {
        fn doTheTest() void {
            const a: @Vector(4, bool) = [_]bool{ true, false, true, false };
            const result_array: [4]bool = a;
            expect(mem.eql(bool, result_array, [4]bool{ true, false, true, false }));
        }
    };
    S.doTheTest();
    comptime S.doTheTest();
}

test "vector wrap operators" {
    const S = struct {
        fn doTheTest() void {
            var v: @Vector(4, i32) = [4]i32{ 2147483647, -2, 30, 40 };
            var x: @Vector(4, i32) = [4]i32{ 1, 2147483647, 3, 4 };
            expect(mem.eql(i32, ([4]i32)(v +% x), [4]i32{ -2147483648, 2147483645, 33, 44 }));
            expect(mem.eql(i32, ([4]i32)(v -% x), [4]i32{ 2147483646, 2147483647, 27, 36 }));
            expect(mem.eql(i32, ([4]i32)(v *% x), [4]i32{ 2147483647, 2, 90, 160 }));
            var z: @Vector(4, i32) = [4]i32{ 1, 2, 3, -2147483648 };
            expect(mem.eql(i32, ([4]i32)(-%z), [4]i32{ -1, -2, -3, -2147483648 }));
        }
    };
    S.doTheTest();
    comptime S.doTheTest();
}

test "vector bin compares with mem.eql" {
    const S = struct {
        fn doTheTest() void {
            var v: @Vector(4, i32) = [4]i32{ 2147483647, -2, 30, 40 };
            var x: @Vector(4, i32) = [4]i32{ 1, 2147483647, 30, 4 };
            expect(mem.eql(bool, ([4]bool)(v == x), [4]bool{ false, false,  true, false}));
            expect(mem.eql(bool, ([4]bool)(v != x), [4]bool{  true,  true, false,  true}));
            expect(mem.eql(bool, ([4]bool)(v  < x), [4]bool{ false,  true, false, false}));
            expect(mem.eql(bool, ([4]bool)(v  > x), [4]bool{  true, false, false,  true}));
            expect(mem.eql(bool, ([4]bool)(v <= x), [4]bool{ false,  true,  true, false}));
            expect(mem.eql(bool, ([4]bool)(v >= x), [4]bool{  true, false,  true,  true}));
        }
    };
    S.doTheTest();
    comptime S.doTheTest();
}

test "vector int operators" {
    const S = struct {
        fn doTheTest() void {
            var v: @Vector(4, i32) = [4]i32{ 10, 20, 30, 40 };
            var x: @Vector(4, i32) = [4]i32{ 1, 2, 3, 4 };
            expect(mem.eql(i32, ([4]i32)(v + x), [4]i32{ 11, 22, 33, 44 }));
            expect(mem.eql(i32, ([4]i32)(v - x), [4]i32{ 9, 18, 27, 36 }));
            expect(mem.eql(i32, ([4]i32)(v * x), [4]i32{ 10, 40, 90, 160 }));
            expect(mem.eql(i32, ([4]i32)(-v), [4]i32{ -10, -20, -30, -40 }));
        }
    };
    S.doTheTest();
    comptime S.doTheTest();
}

test "vector float operators" {
    const S = struct {
        fn doTheTest() void {
            var v: @Vector(4, f32) = [4]f32{ 10, 20, 30, 40 };
            var x: @Vector(4, f32) = [4]f32{ 1, 2, 3, 4 };
            expect(mem.eql(f32, ([4]f32)(v + x), [4]f32{ 11, 22, 33, 44 }));
            expect(mem.eql(f32, ([4]f32)(v - x), [4]f32{ 9, 18, 27, 36 }));
            expect(mem.eql(f32, ([4]f32)(v * x), [4]f32{ 10, 40, 90, 160 }));
            expect(mem.eql(f32, ([4]f32)(-x), [4]f32{ -1, -2, -3, -4 }));
        }
    };
    S.doTheTest();
    comptime S.doTheTest();
}

test "vector bit operators" {
    const S = struct {
        fn doTheTest() void {
            var v: @Vector(4, u8) = [4]u8{ 0b10101010, 0b10101010, 0b10101010, 0b10101010 };
            var x: @Vector(4, u8) = [4]u8{ 0b11110000, 0b00001111, 0b10101010, 0b01010101 };
            expect(mem.eql(u8, ([4]u8)(v ^ x), [4]u8{ 0b01011010, 0b10100101, 0b00000000, 0b11111111 }));
            expect(mem.eql(u8, ([4]u8)(v | x), [4]u8{ 0b11111010, 0b10101111, 0b10101010, 0b11111111 }));
            expect(mem.eql(u8, ([4]u8)(v & x), [4]u8{ 0b10100000, 0b00001010, 0b10101010, 0b00000000 }));
        }
    };
    S.doTheTest();
    comptime S.doTheTest();
}

test "implicit cast vector to array" {
    const S = struct {
        fn doTheTest() void {
            var a: @Vector(4, i32) = [_]i32{ 1, 2, 3, 4 };
            var result_array: [4]i32 = a;
            result_array = a;
            expect(mem.eql(i32, result_array, [4]i32{ 1, 2, 3, 4 }));
        }
    };
    S.doTheTest();
    comptime S.doTheTest();
}

test "array to vector" {
    var foo: f32 = 3.14;
    var arr = [4]f32{ foo, 1.5, 0.0, 0.0 };
    var vec: @Vector(4, f32) = arr;
}

test "vector upcast" {
    const S = struct {
        fn doTheTest() void {
            {
              const v: @Vector(4, i16) = [4]i16{ 21, -2, 30, 40};
              const x: @Vector(4, i32) = @Vector(4, i32)(v);
              expect(x[0] == 21);
              expect(x[1] == -2);
              expect(x[2] == 30);
              expect(x[3] == 40);
            }

            {
              const v: @Vector(4, u16) = [4]u16{ 21, 2, 30, 40};
              const x: @Vector(4, u32) = @Vector(4, u32)(v);
              expect(x[0] == 21);
              expect(x[1] == 2);
              expect(x[2] == 30);
              expect(x[3] == 40);
            }

            {
              const v: @Vector(4, f16) = [4]f16{ 21, -2, 30, 40};
              const x: @Vector(4, f32) = @Vector(4, f32)(v);
              expect(x[0] == 21);
              expect(x[1] == -2);
              expect(x[2] == 30);
              expect(x[3] == 40);
            }
        }
    };
    S.doTheTest();
    comptime S.doTheTest();
}

test "vector truncate" {
    const S = struct {
        fn doTheTest() void {
            const v: @Vector(4, i32) = [4]i32{ 21, -2, 30, 40};
            const x: @Vector(4, i16) = @truncate(@Vector(4, i16), v);
            expect(x[0] == 21);
            expect(x[1] == -2);
            expect(x[2] == 30);
            expect(x[3] == 40);
        }
    };
    S.doTheTest();
    comptime S.doTheTest();
}

test "vector casts of sizes not divisable by 8" {
    const S = struct {
        fn doTheTest() void {
            {
                var v: @Vector(4, u3) = [4]u3{ 5, 2,  3, 0};
                var x: [4]u3 = v;
                expect(mem.eql(u3, x, ([4]u3)(v)));
            }
            {
                var v: @Vector(4, u2) = [4]u2{ 1, 2,  3, 0};
                var x: [4]u2 = v;
                expect(mem.eql(u2, x, ([4]u2)(v)));
            }
            {
                var v: @Vector(4, u1) = [4]u1{ 1, 0,  1, 0};
                var x: [4]u1 = v;
                expect(mem.eql(u1, x, ([4]u1)(v)));
            }
            {
                var v: @Vector(4, bool) = [4]bool{ false, false,  true, false};
                var x: [4]bool = v;
                expect(mem.eql(bool, x, ([4]bool)(v)));
            }
        }
    };
    S.doTheTest();
    comptime S.doTheTest();
}

test "implicit cast vector to array - bool" {
    const S = struct {
        fn doTheTest() void {
            const a: @Vector(4, bool) = [_]bool{ true, false, true, false };
            const result_array: [4]bool = a;
            expect(mem.eql(bool, result_array, [4]bool{ true, false, true, false }));
        }
    };
    S.doTheTest();
    comptime S.doTheTest();
}

test "vector bin compares with mem.eql" {
    const S = struct {
        fn doTheTest() void {
            var v: @Vector(4, i32) = [4]i32{ 2147483647, -2, 30, 40 };
            var x: @Vector(4, i32) = [4]i32{ 1, 2147483647, 30, 4 };
            expect(mem.eql(bool, ([4]bool)(v == x), [4]bool{ false, false,  true, false}));
            expect(mem.eql(bool, ([4]bool)(v != x), [4]bool{  true,  true, false,  true}));
            expect(mem.eql(bool, ([4]bool)(v  < x), [4]bool{ false,  true, false, false}));
            expect(mem.eql(bool, ([4]bool)(v  > x), [4]bool{  true, false, false,  true}));
            expect(mem.eql(bool, ([4]bool)(v <= x), [4]bool{ false,  true,  true, false}));
            expect(mem.eql(bool, ([4]bool)(v >= x), [4]bool{  true, false,  true,  true}));
        }
    };
    S.doTheTest();
    comptime S.doTheTest();
}

test "vector member field access" {
    const S = struct {
        fn doTheTest() void {
            const q: @Vector(4, u32) = undefined;
            expect(q.len == 4);
            const v = @Vector(4, i32);
            expect(v.len == 4);
            expect(v.bit_count == 32);
            expect(v.is_signed == true);
            const k = @Vector(2, bool);
            expect(k.len == 2);
            const x = @Vector(3, f32);
            expect(x.len == 3);
            expect(x.bit_count == 32);
            const z = @Vector(3, *align(4) u32);
            expect(z.len == 3);
            expect(z.Child == u32);
            // FIXME is this confusing? However vector alignment requirements are entirely
            // dependant on their size, and can be gotten with @alignOf().
            expect(z.alignment == 4);
        }
    };
    S.doTheTest();
    comptime S.doTheTest();
}

test "vector access elements - load" {
    {
        var a: @Vector(4, i32) = [_]i32{ 1, 2, 3, undefined };
        var i: u32 = 2;
        expect(a[i] == 3);
        expect(3 == a[2]);
        i -= 1;
        expect(a[i] == i32(2));
    }

    comptime {
        comptime var a: @Vector(4, i32) = [_]i32{ 1, 2, 3, undefined };
        var i: u32 = 0;
        expect(a[0] == 1);
        i += 1;
        expect(a[i] == i32(2));
        i += 1;
        expect(3 == a[i]);
    }
}

test "vector access elements - store" {
    {
        var a: @Vector(4, i32) = [_]i32{ 1, 5, 3, undefined };
        var i: u32 = 2;
        a[i] = 1;
        expect(a[1] == 5);
        expect(a[2] == i32(1));
        i += 1;
        a[i] = -364;
        expect(-364 == a[3]);
    }

    comptime {
        comptime var a: @Vector(4, i32) = [_]i32{ 1, 2, 3, undefined };
        var i: u32 = 2;
        a[i] = 5;
        expect(a[2] == i32(5));
        i += 1;
        a[i] = -364;
        expect(-364 == a[3]);
    }
}

test "vector @splat" {
    const S = struct {
        fn doTheTest() void {
            var v: u32 = 5;
            var x = @splat(4, v);
            expect(@typeOf(x) == @Vector(4, u32));
            expect(x[0] == 5);
            expect(x[1] == 5);
            expect(x[2] == 5);
            expect(x[3] == 5);
        }
    };
    S.doTheTest();
    comptime S.doTheTest();
}

test "vector @bitCast" {
    const S = struct {
        fn doTheTest() void {
            {
                const math = @import("std").math;
                const v: @Vector(4, u32) = [4]u32{ 0x7F800000, 0x7F800001, 0xFF800000, 0};
                const x: @Vector(4, f32) = @bitCast(f32, v);
                expect(x[0] == math.inf(f32));
                expect(x[1] != x[1]); // NaN
                expect(x[2] == -math.inf(f32));
                expect(x[3] == 0);
            }
            {
                const math = @import("std").math;
                const v: @Vector(2, u64) = [2]u64{ 0x7F8000017F800000, 0xFF800000};
                const x: @Vector(4, f32) = @bitCast(@Vector(4, f32), v);
                expect(x[0] == math.inf(f32));
                expect(x[1] != x[1]); // NaN
                expect(x[2] == -math.inf(f32));
                expect(x[3] == 0);
            }
            {
                const v: @Vector(4, u8) = [_]u8{2, 1, 2, 1};
                const x: u32 = @bitCast(u32, v);
                expect(x == 0x01020102);
                const z: @Vector(4, u8) = @bitCast(@Vector(4, u8), x);
                expect(z[0] == 2);
                expect(z[1] == 1);
                expect(z[2] == 2);
                expect(z[3] == 1);
            }
            {
                const v: @Vector(4, i8) = [_]i8{2, 1, 0, -128};
                const x: u32 = @bitCast(u32, v);
                expect(x == 0x80000102);
            }
            {
                const v: @Vector(4, u1) = [_]u1{1, 1, 0, 1};
                const x: u4 = @bitCast(u4, v);
                expect(x == 0b1011);
            }
            {
                const v: @Vector(4, u3) = [_]u3{0b100, 0b111, 0, 1};
                const x: u12 = @bitCast(u12, v);
                expect(x == 0b001000111100);
                const z: @Vector(4, u3) = @bitCast(@Vector(4, u3), x);
                expect(z[0] == 0b100);
                expect(z[1] == 0b111);
                expect(z[2] == 0);
                expect(z[3] == 1);
            }
            {
                const v: @Vector(2, u9) = [_]u9{2, 1};
                const x: u18 = @bitCast(u18, v);
                expect(x == 0b000000001000000010);
                const z: @Vector(2, u9) = @bitCast(@Vector(2, u9), x);
                expect(z[0] == 2);
                expect(z[1] == 1);
            }
            {
                const v: @Vector(4, bool) = [_]bool{false, true, false, true};
                const x: u4 = @bitCast(u4, v);
                expect(x == 0b1010);
                const z: @Vector(4, bool) = @bitCast(@Vector(4, bool), x);
                expect(z[0] == false);
                expect(z[1] == true);
                expect(z[2] == false);
                expect(z[3] == true);
            }
        }
    };
    S.doTheTest();
    comptime S.doTheTest();
}
