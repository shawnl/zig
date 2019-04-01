const std = @import("../std.zig");
const builtin = @import("builtin");
const assert = std.debug.assert;
const testing = std.testing;
const AtomicRmwOp = builtin.AtomicRmwOp;
const AtomicOrder = builtin.AtomicOrder;
const Loop = std.event.Loop;
const Queue = std.sync.Queue;

/// many producer, many consumer, thread-safe, runtime configurable buffer size
/// when buffer is empty, consumers suspend and are resumed by producers
/// when buffer is full, producers suspend and are resumed by consumers
pub fn Channel(comptime T: type) type {
    return struct {
        loop: *Loop,

        getters: Queue(GetNode),
        or_null_queue: Queue(*Queue(GetNode).Node),
        putters: Queue(PutNode),
        get_count: usize,
        put_count: usize,
        dispatch_lock: u8, // TODO make this a bool
        need_dispatch: u8, // TODO make this a bool

        // simple fixed size ring buffer
        buffer_nodes: []T,
        buffer_index: usize,
        buffer_len: usize,

        const SelfChannel = @This();
        const GetNode = struct {
            tick_node: *Loop.NextTickNode,
            data: Data,

            const Data = union(enum) {
                Normal: Normal,
                OrNull: OrNull,
            };

            const Normal = struct {
                ptr: *T,
            };

            const OrNull = struct {
                ptr: *?T,
                or_null: *Queue(*Queue(GetNode).Node).Node,
            };
        };
        const PutNode = struct {
            data: T,
            tick_node: *Loop.NextTickNode,
        };

        /// call destroy when done
        pub fn create(loop: *Loop, capacity: usize) !*SelfChannel {
            const buffer_nodes = try loop.allocator.alloc(T, capacity);
            errdefer loop.allocator.free(buffer_nodes);

            const self = try loop.allocator.create(SelfChannel);
            self.* = SelfChannel{
                .loop = loop,
                .buffer_len = 0,
                .buffer_nodes = buffer_nodes,
                .buffer_index = 0,
                .dispatch_lock = 0,
                .need_dispatch = 0,
                .getters = Queue(GetNode).init(),
                .putters = Queue(PutNode).init(),
                .or_null_queue = Queue(*Queue(GetNode).Node).init(),
                .get_count = 0,
                .put_count = 0,
            };
            errdefer loop.allocator.destroy(self);

            return self;
        }

        /// must be called when all calls to put and get have suspended and no more calls occur
        pub fn destroy(self: *SelfChannel) void {
            while (self.getters.get()) |get_node| {
                cancel get_node.data.tick_node.data;
            }
            while (self.putters.get()) |put_node| {
                cancel put_node.data.tick_node.data;
            }
            self.loop.allocator.free(self.buffer_nodes);
            self.loop.allocator.destroy(self);
        }

        /// puts a data item in the channel. The promise completes when the value has been added to the
        /// buffer, or in the case of a zero size buffer, when the item has been retrieved by a getter.
        pub async fn put(self: *SelfChannel, data: T) void {
            // TODO fix this workaround
            suspend {
                resume @handle();
            }

            var my_tick_node = Loop.NextTickNode.init(@handle());
            var queue_node = Queue(PutNode).Node.init(PutNode{
                .tick_node = &my_tick_node,
                .data = data,
            });

            // TODO test canceling a put()
            errdefer {
                _ = @atomicRmw(usize, &self.put_count, AtomicRmwOp.Sub, 1, AtomicOrder.SeqCst);
                const need_dispatch = !self.putters.remove(&queue_node);
                self.loop.cancelOnNextTick(&my_tick_node);
                if (need_dispatch) {
                    // oops we made the put_count incorrect for a period of time. fix by dispatching.
                    _ = @atomicRmw(usize, &self.put_count, AtomicRmwOp.Add, 1, AtomicOrder.SeqCst);
                    self.dispatch();
                }
            }
            suspend {
                self.putters.put(&queue_node);
                _ = @atomicRmw(usize, &self.put_count, AtomicRmwOp.Add, 1, AtomicOrder.SeqCst);

                self.dispatch();
            }
        }

        /// await this function to get an item from the channel. If the buffer is empty, the promise will
        /// complete when the next item is put in the channel.
        pub async fn get(self: *SelfChannel) T {
            // TODO fix this workaround
            suspend {
                resume @handle();
            }

            // TODO integrate this function with named return values
            // so we can get rid of this extra result copy
            var result: T = undefined;
            var my_tick_node = Loop.NextTickNode.init(@handle());
            var queue_node = Queue(GetNode).Node.init(GetNode{
                .tick_node = &my_tick_node,
                .data = GetNode.Data{
                    .Normal = GetNode.Normal{ .ptr = &result },
                },
            });

            // TODO test canceling a get()
            errdefer {
                _ = @atomicRmw(usize, &self.get_count, AtomicRmwOp.Sub, 1, AtomicOrder.SeqCst);
                const need_dispatch = !self.getters.remove(&queue_node);
                self.loop.cancelOnNextTick(&my_tick_node);
                if (need_dispatch) {
                    // oops we made the get_count incorrect for a period of time. fix by dispatching.
                    _ = @atomicRmw(usize, &self.get_count, AtomicRmwOp.Add, 1, AtomicOrder.SeqCst);
                    self.dispatch();
                }
            }

            suspend {
                self.getters.put(&queue_node);
                _ = @atomicRmw(usize, &self.get_count, AtomicRmwOp.Add, 1, AtomicOrder.SeqCst);

                self.dispatch();
            }
            return result;
        }

        //pub async fn select(comptime EnumUnion: type, channels: ...) EnumUnion {
        //    assert(@memberCount(EnumUnion) == channels.len); // enum union and channels mismatch
        //    assert(channels.len != 0); // enum unions cannot have 0 fields
        //    if (channels.len == 1) {
        //        const result = await (async channels[0].get() catch unreachable);
        //        return @unionInit(EnumUnion, @memberName(EnumUnion, 0), result);
        //    }
        //}

        /// Await this function to get an item from the channel. If the buffer is empty and there are no
        /// puts waiting, this returns null.
        /// Await is necessary for locking purposes. The function will be resumed after checking the channel
        /// for data and will not wait for data to be available.
        pub async fn getOrNull(self: *SelfChannel) ?T {
            // TODO fix this workaround
            suspend {
                resume @handle();
            }

            // TODO integrate this function with named return values
            // so we can get rid of this extra result copy
            var result: ?T = null;
            var my_tick_node = Loop.NextTickNode.init(@handle());
            var or_null_node = Queue(*Queue(GetNode).Node).Node.init(undefined);
            var queue_node = Queue(GetNode).Node.init(GetNode{
                .tick_node = &my_tick_node,
                .data = GetNode.Data{
                    .OrNull = GetNode.OrNull{
                        .ptr = &result,
                        .or_null = &or_null_node,
                    },
                },
            });
            or_null_node.data = &queue_node;

            // TODO test canceling getOrNull
            errdefer {
                _ = self.or_null_queue.remove(&or_null_node);
                _ = @atomicRmw(usize, &self.get_count, AtomicRmwOp.Sub, 1, AtomicOrder.SeqCst);
                const need_dispatch = !self.getters.remove(&queue_node);
                self.loop.cancelOnNextTick(&my_tick_node);
                if (need_dispatch) {
                    // oops we made the get_count incorrect for a period of time. fix by dispatching.
                    _ = @atomicRmw(usize, &self.get_count, AtomicRmwOp.Add, 1, AtomicOrder.SeqCst);
                    self.dispatch();
                }
            }

            suspend {
                self.getters.put(&queue_node);
                _ = @atomicRmw(usize, &self.get_count, AtomicRmwOp.Add, 1, AtomicOrder.SeqCst);
                self.or_null_queue.put(&or_null_node);

                self.dispatch();
            }
            return result;
        }

        fn dispatch(self: *SelfChannel) void {
            // set the "need dispatch" flag
            _ = @atomicRmw(u8, &self.need_dispatch, AtomicRmwOp.Xchg, 1, AtomicOrder.SeqCst);

            lock: while (true) {
                // set the lock flag
                const prev_lock = @atomicRmw(u8, &self.dispatch_lock, AtomicRmwOp.Xchg, 1, AtomicOrder.SeqCst);
                if (prev_lock != 0) return;

                // clear the need_dispatch flag since we're about to do it
                _ = @atomicRmw(u8, &self.need_dispatch, AtomicRmwOp.Xchg, 0, AtomicOrder.SeqCst);

                while (true) {
                    one_dispatch: {
                        // later we correct these extra subtractions
                        var get_count = @atomicRmw(usize, &self.get_count, AtomicRmwOp.Sub, 1, AtomicOrder.SeqCst);
                        var put_count = @atomicRmw(usize, &self.put_count, AtomicRmwOp.Sub, 1, AtomicOrder.SeqCst);

                        // transfer self.buffer to self.getters
                        while (self.buffer_len != 0) {
                            if (get_count == 0) break :one_dispatch;

                            const get_node = &self.getters.get().?.data;
                            switch (get_node.data) {
                                GetNode.Data.Normal => |info| {
                                    info.ptr.* = self.buffer_nodes[self.buffer_index -% self.buffer_len];
                                },
                                GetNode.Data.OrNull => |info| {
                                    _ = self.or_null_queue.remove(info.or_null);
                                    info.ptr.* = self.buffer_nodes[self.buffer_index -% self.buffer_len];
                                },
                            }
                            self.loop.onNextTick(get_node.tick_node);
                            self.buffer_len -= 1;

                            get_count = @atomicRmw(usize, &self.get_count, AtomicRmwOp.Sub, 1, AtomicOrder.SeqCst);
                        }

                        // direct transfer self.putters to self.getters
                        while (get_count != 0 and put_count != 0) {
                            const get_node = &self.getters.get().?.data;
                            const put_node = &self.putters.get().?.data;

                            switch (get_node.data) {
                                GetNode.Data.Normal => |info| {
                                    info.ptr.* = put_node.data;
                                },
                                GetNode.Data.OrNull => |info| {
                                    _ = self.or_null_queue.remove(info.or_null);
                                    info.ptr.* = put_node.data;
                                },
                            }
                            self.loop.onNextTick(get_node.tick_node);
                            self.loop.onNextTick(put_node.tick_node);

                            get_count = @atomicRmw(usize, &self.get_count, AtomicRmwOp.Sub, 1, AtomicOrder.SeqCst);
                            put_count = @atomicRmw(usize, &self.put_count, AtomicRmwOp.Sub, 1, AtomicOrder.SeqCst);
                        }

                        // transfer self.putters to self.buffer
                        while (self.buffer_len != self.buffer_nodes.len and put_count != 0) {
                            const put_node = &self.putters.get().?.data;

                            self.buffer_nodes[self.buffer_index] = put_node.data;
                            self.loop.onNextTick(put_node.tick_node);
                            self.buffer_index +%= 1;
                            self.buffer_len += 1;

                            put_count = @atomicRmw(usize, &self.put_count, AtomicRmwOp.Sub, 1, AtomicOrder.SeqCst);
                        }
                    }

                    // undo the extra subtractions
                    _ = @atomicRmw(usize, &self.get_count, AtomicRmwOp.Add, 1, AtomicOrder.SeqCst);
                    _ = @atomicRmw(usize, &self.put_count, AtomicRmwOp.Add, 1, AtomicOrder.SeqCst);

                    // All the "get or null" functions should resume now.
                    var remove_count: usize = 0;
                    while (self.or_null_queue.get()) |or_null_node| {
                        remove_count += @boolToInt(self.getters.remove(or_null_node.data));
                        self.loop.onNextTick(or_null_node.data.data.tick_node);
                    }
                    if (remove_count != 0) {
                        _ = @atomicRmw(usize, &self.get_count, AtomicRmwOp.Sub, remove_count, AtomicOrder.SeqCst);
                    }

                    // clear need-dispatch flag
                    const need_dispatch = @atomicRmw(u8, &self.need_dispatch, AtomicRmwOp.Xchg, 0, AtomicOrder.SeqCst);
                    if (need_dispatch != 0) continue;

                    const my_lock = @atomicRmw(u8, &self.dispatch_lock, AtomicRmwOp.Xchg, 0, AtomicOrder.SeqCst);
                    assert(my_lock != 0);

                    // we have to check again now that we unlocked
                    if (@atomicLoad(u8, &self.need_dispatch, AtomicOrder.SeqCst) != 0) continue :lock;

                    return;
                }
            }
        }
    };
}

test "std.event.Channel" {
    // https://github.com/ziglang/zig/issues/1908
    if (builtin.single_threaded) return error.SkipZigTest;

    var da = std.heap.DirectAllocator.init();
    defer da.deinit();

    const allocator = &da.allocator;

    var loop: Loop = undefined;
    // TODO make a multi threaded test
    try loop.initSingleThreaded(allocator);
    defer loop.deinit();

    const channel = try Channel(i32).create(&loop, 0);
    defer channel.destroy();

    const handle = try async<allocator> testChannelGetter(&loop, channel);
    defer cancel handle;

    const putter = try async<allocator> testChannelPutter(channel);
    defer cancel putter;

    loop.run();
}

async fn testChannelGetter(loop: *Loop, channel: *Channel(i32)) void {
    errdefer @panic("test failed");

    const value1_promise = try async channel.get();
    const value1 = await value1_promise;
    testing.expect(value1 == 1234);

    const value2_promise = try async channel.get();
    const value2 = await value2_promise;
    testing.expect(value2 == 4567);

    const value3_promise = try async channel.getOrNull();
    const value3 = await value3_promise;
    testing.expect(value3 == null);

    const last_put = try async testPut(channel, 4444);
    const value4 = await try async channel.getOrNull();
    testing.expect(value4.? == 4444);
    await last_put;
}

async fn testChannelPutter(channel: *Channel(i32)) void {
    await (async channel.put(1234) catch @panic("out of memory"));
    await (async channel.put(4567) catch @panic("out of memory"));
}

async fn testPut(channel: *Channel(i32), value: i32) void {
    await (async channel.put(value) catch @panic("out of memory"));
}
