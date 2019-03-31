const std = @import("std");
const builtin = @import("builtin");
const AtomicOrder = builtin.AtomicOrder;
const AtomicRmwOp = builtin.AtomicRmwOp;
const testing = std.testing;
const linux = std.os.linux;
