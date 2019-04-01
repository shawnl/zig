const std = @import("../std.zig");
const builtin = @import("builtin");
const Lock = std.event.Lock;
const Loop = std.event.Loop;
const AtomicRmwOp = builtin.AtomicRmwOp;
const AtomicOrder = builtin.AtomicOrder;
const testing = std.testing;

/// ReturnType must be `void` or `E!void`
pub fn Group(comptime ReturnType: type) type {
    return struct {
        coro_stack: Stack,
        alloc_stack: Stack,
        lock: Lock,

        const Self = @This();

        const Error = switch (@typeInfo(ReturnType)) {
            builtin.TypeId.ErrorUnion => |payload| payload.error_set,
            else => void,
        };
        const Stack = std.sync.Stack(promise->ReturnType);

        pub fn init(loop: *Loop) Self {
            return Self{
                .coro_stack = Stack.init(),
                .alloc_stack = Stack.init(),
                .lock = Lock.init(loop),
            };
        }

        /// Cancel all the outstanding promises. Can be called even if wait was already called.
        pub fn deinit(self: *Self) void {
            while (self.coro_stack.pop()) |node| {
                cancel node.data;
            }
            while (self.alloc_stack.pop()) |node| {
                cancel node.data;
                self.lock.loop.allocator.destroy(node);
            }
        }

        /// Add a promise to the group. Thread-safe.
        pub fn add(self: *Self, handle: promise->ReturnType) (error{OutOfMemory}!void) {
            const node = try self.lock.loop.allocator.create(Stack.Node);
            node.* = Stack.Node{
                .next = undefined,
                .data = handle,
            };
            self.alloc_stack.push(node);
        }

        /// Add a node to the group. Thread-safe. Cannot fail.
        /// `node.data` should be the promise handle to add to the group.
        /// The node's memory should be in the coroutine frame of
        /// the handle that is in the node, or somewhere guaranteed to live
        /// at least as long.
        pub fn addNode(self: *Self, node: *Stack.Node) void {
            self.coro_stack.push(node);
        }

        /// This is equivalent to an async call, but the async function is added to the group, instead
        /// of returning a promise. func must be async and have return type ReturnType.
        /// Thread-safe.
        pub fn call(self: *Self, comptime func: var, args: ...) (error{OutOfMemory}!void) {
            const S = struct {
                async fn asyncFunc(node: **Stack.Node, args2: ...) ReturnType {
                    // TODO this is a hack to make the memory following be inside the coro frame
                    suspend {
                        var my_node: Stack.Node = undefined;
                        node.* = &my_node;
                        resume @handle();
                    }

                    // TODO this allocation elision should be guaranteed because we await it in
                    // this coro frame
                    return await (async func(args2) catch unreachable);
                }
            };
            var node: *Stack.Node = undefined;
            const handle = try async<self.lock.loop.allocator> S.asyncFunc(&node, args);
            node.* = Stack.Node{
                .next = undefined,
                .data = handle,
            };
            self.coro_stack.push(node);
        }

        /// Wait for all the calls and promises of the group to complete.
        /// Thread-safe.
        /// Safe to call any number of times.
        pub async fn wait(self: *Self) ReturnType {
            // TODO catch unreachable because the allocation can be grouped with
            // the coro frame allocation
            const held = await (async self.lock.acquire() catch unreachable);
            defer held.release();

            while (self.coro_stack.pop()) |node| {
                if (Error == void) {
                    await node.data;
                } else {
                    (await node.data) catch |err| {
                        self.deinit();
                        return err;
                    };
                }
            }
            while (self.alloc_stack.pop()) |node| {
                const handle = node.data;
                self.lock.loop.allocator.destroy(node);
                if (Error == void) {
                    await handle;
                } else {
                    (await handle) catch |err| {
                        self.deinit();
                        return err;
                    };
                }
            }
        }
    };
}

test "std.event.Group" {
    // https://github.com/ziglang/zig/issues/1908
    if (builtin.single_threaded) return error.SkipZigTest;

    var da = std.heap.DirectAllocator.init();
    defer da.deinit();

    const allocator = &da.allocator;

    var loop: Loop = undefined;
    try loop.initMultiThreaded(allocator);
    defer loop.deinit();

    const handle = try async<allocator> testGroup(&loop);
    defer cancel handle;

    loop.run();
}

async fn testGroup(loop: *Loop) void {
    var count: usize = 0;
    var group = Group(void).init(loop);
    group.add(async sleepALittle(&count) catch @panic("memory")) catch @panic("memory");
    group.call(increaseByTen, &count) catch @panic("memory");
    await (async group.wait() catch @panic("memory"));
    testing.expect(count == 11);

    var another = Group(anyerror!void).init(loop);
    another.add(async somethingElse() catch @panic("memory")) catch @panic("memory");
    another.call(doSomethingThatFails) catch @panic("memory");
    testing.expectError(error.ItBroke, await (async another.wait() catch @panic("memory")));
}

async fn sleepALittle(count: *usize) void {
    std.os.time.sleep(1 * std.os.time.millisecond);
    _ = @atomicRmw(usize, count, AtomicRmwOp.Add, 1, AtomicOrder.SeqCst);
}

async fn increaseByTen(count: *usize) void {
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        _ = @atomicRmw(usize, count, AtomicRmwOp.Add, 1, AtomicOrder.SeqCst);
    }
}

async fn doSomethingThatFails() anyerror!void {}
async fn somethingElse() anyerror!void {
    return error.ItBroke;
}
