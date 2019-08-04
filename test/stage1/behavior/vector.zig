const std = @import("std");
const mem = std.mem;
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
