const builtin = @import("builtin");

pub fn all(vector: var) bool {
    if (@typeId(@typeOf(vector)) != builtin.TypeId.Vector or @typeId(@typeOf(vector[0])) != builtin.TypeId.Bool) {
        @compileError("all() can only be used on vectors of bools, got '" + @typeName(vector) + "'");
    }
    comptime var len = @typeOf(vector).len;
    comptime var i: usize = 0;
    var result: bool = true;
    inline while (i < len) : (i += 1) {
        result = result and vector[i];
    }
    return result;
}

pub fn any(vector: var) bool {
    if (@typeId(@typeOf(vector)) != builtin.TypeId.Vector or @typeId(@typeOf(vector[0])) != builtin.TypeId.Bool) {
        @compileError("any() and none() can only be used on vectors of bools, got '" + @typeName(vector) + "'");
    }
    comptime var len = @typeOf(vector).len;
    comptime var i: usize = 0;
    var result: bool = false;
    inline while (i < len) : (i += 1) {
        result = result or vector[i];
    }
    return result;
}

pub fn none(vector: var) bool {
    return !any(vector);
}

test "std.vector.any,all,none" {
    const expect = @import("std").testing.expect;
    var a: @Vector(2, bool) = [_]bool{false, false};
    var b: @Vector(2, bool) = [_]bool{false, true};
    var c: @Vector(2, bool) = [_]bool{true, true};
    expect(none(a));
    expect(any(b));
    expect(all(c));
    expect(!none(b));
    expect(!any(a));
    expect(!all(b));
}
