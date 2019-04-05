const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;
const mem = std.mem;
const Allocator = mem.Allocator;

/// Generic doubly linked list, take 2.
///
/// Why this instead of the old linked list?
/// 1. It's use of @fieldParentPtr makes it considerably simpler
/// 2. Wraps around, which is useful in a number of algorithms,
///    and also makes it much simpler
/// 3. Doesn't keep track of length which makes the old version
///    unsuitable in some cases, and also makes this version simpler
/// 4. Is never null
/// 5. Concatanation is much simpler.
/// 6. I need to have the next pointer be the first element in the structure
/// 7. Nothing fancy like @This();
/// 8. It is sufficiently crash-proof for set_robust_list() on Linux. It is not
///    thread-safe, even in the forward direction. Don't be confused by the use
///    of atomics. As soon as you remove an item it will blow up if you assume
///    otherwise.
///
/// Reminder: the last node is head.prev. You can use a head or not use one. This
/// implementation doesn't care.
///
/// Insert this into your struct that you want to add to a doubly-linked list.
/// Do not use a pointer. Turn the *linked_list2.List results of the functions here
/// (after resolving optionals) to your structure using @fieldParentPtr(). Example:
///
/// const Number = struct {
///     list: List,
///     value: i32,
/// };
/// fn number(list: *linked_list2.List) Number {
///     return @fieldParentPtr(Number, "list", list);
/// }

pub const List = extern struct {
    next: *List, /// set_robust_list Linux ABI, as Zig uses it, depends on this being the first element in this struct
    prev: *List,

    /// Must call this before inserting elements
    pub fn init(self: *List) void {
        self.prev = self;
        self.next = self;
    }

    /// Insert a new node at the beginning of the list
    ///
    /// Arguments:
    ///     new_node: Pointer to the new node to insert.
    pub fn insertAfter(self: *List, new_node: *List) void {
        _ = @atomicRmw(*list, &new_node.prev, .Xchg, self, .Monotonic);
        var self_next = self.next;
        _ = @atomicRmw(*list, &new_node.next, .Xchg, self_next, .Monotonic);
        _ = @atomicRmw(*List, &self.next, .Xchg, new_node, .Monotonic);
        _ = @atomicRmw(*List, &self_next.prev, .Xchg, new_node, .Monotonic);
    }

    /// Insert a new node at the end of the list
    ///
    /// Arguments:
    ///     new_node: Pointer to the new node to insert.
    pub fn insertBefore(self: *List, new_node: *List) void {
        _ = @atomicRmw(*List, &new_node.prev, .Xchg, self.prev, .Monotonic);
        _ = @atomicRmw(*List, &new_node.next, .Xchg, self, .Monotonic);
        _ = @atomicRmw(*List, &self.prev.next, .Xchg, new_node, .Monotonic);
        _ = @atomicRmw(*List, &self.prev, .Xchg, new_node, .Monotonic);
    }

    /// Same as insertBefore()
    pub fn push(self: *List, new_node: *List) void {
        return insertBefore(self, new_node);
    }

    /// Returns the length of the list
    ///
    /// If the length is longer than max, returns null
    /// Includes the head node, if any.
    pub fn len(self: *List, max: usize) ?usize {
        var cursor: *List = self;
        var i: usize = 1;
        while (i < max) : (i += 1) {
            cursor = cursor.next;
            if (self == cursor) return i;
        }
        return null;
    }

    /// Concatenate list2 onto list1.
    ///
    /// Arguments:
    ///     list1: the first list
    ///     list2: the second list
    pub fn concat(list1: *List, list2: *List) void {
        // Do the backwards direction first because this doesn't break the list,
        // and then forward reading cannot spin on a loop they were not prepared for
        // (that doesn't go back to their start point) while this is in operation.
        // If list2 is a head, it needs to be removed before this, and the first element inserted.
        var l2prev = list2.prev;
        var l1prev = @atomicRmw(*List, &list1.prev, .Xchg, list2.prev, .Monotonic);
        _ = @atomicRmw(*List, &list2.prev, .Xchg, l1prev, .Monotonic);
        _ = @atomicRmw(*List, &l1prev.next, .Xchg, list2, .Monotonic);
        _ = @atomicRmw(*List, &l2prev.next, .Xchg, list1, .Monotonic);
    }

    /// Remove a node from the list.
    ///
    pub fn remove(self: *List) void {
        return removeThrow(self) catch unreachable;
    }

    /// Remove a node from the list.
    ///
    /// Throw an error if list corruption is detected.
    pub fn removeThrow(self: *List) error{Corruption}!void {
        if (@cmpxchgStrong(*List, &self.prev.next, self, self.next, .Monotonic, .Monotonic)) |err|
            return error.Corruption;
        if (@cmpxchgStrong(*List, &self.next.prev, self, self.prev, .Monotonic, .Monotonic)) |err|
            return error.Corruption;
        self.next = self;
        self.prev = self;
    }

    /// Returns true if this is the this is the only node in the list
    pub fn isAlone(self: *List) bool {
        return self.next == self;
    }

    /// Remove and return the last node in the list.
    ///
    /// Warning: returns null if this is the last node
    ///
    /// Returns:
    ///     A pointer to the last node in the list.
    pub fn pop(list: *List) !?*List {
        if (list.isAlone()) return null;
        var l = list.prev;
        _ = try l.remove();
        return l;
    }

    pub fn last(list: *List) *List {
        return list.prev;
    }

    pub fn first(list: *List) *List {
        return list.next;
    }
};

const test_linked_list = struct {
    node: List,
    int: ?u32,
};

pub fn int(node: *List) *test_linked_list {
    return @fieldParentPtr(test_linked_list, "node", node);
}

extern fn get_test_linked_list(node: *List) *test_linked_list {
    return @fieldParentPtr(test_linked_list, "node", node);
}

test "basic linked list 2 test" {
    var head: test_linked_list = undefined;
    var one: test_linked_list = undefined;
    var two: test_linked_list = undefined;
    var three: test_linked_list = undefined;
    var four: test_linked_list = undefined;
    var five: test_linked_list = undefined;
    var six: test_linked_list = undefined;

    head.int = null;
    one.int = 1;
    two.int = 2;
    three.int = 3;
    four.int = 4;
    five.int = 5;
    six.int = 6;

    head.node.init();

    var f = get_test_linked_list(&head.node);

    head.node.insertBefore(&one.node); // {2}
    head.node.insertBefore(&two.node); // {2, 5}
    head.node.insertBefore(&three.node); // {1, 2, 5}
    head.node.insertBefore(&four.node); // {1, 2, 4, 5}
    head.node.insertBefore(&five.node); // {1, 2, 3, 4, 5}
    head.node.insertBefore(&six.node); // {1, 2, 3, 4, 5}

    // Traverse forwards.
    {
        var hn = &head.node;
        var node: *List = hn.next;
        var index: u32 = 1;
        while (node != hn) : (node = node.next) {
            testing.expect(int(node).int.? == index);
            index += 1;
        }
    }

    // Traverse backwards.
    {
        var hn = &head.node;
        var node: *List = hn.prev;
        var index: u32 = 0;
        while (node != hn) : (node = node.prev) {
            testing.expect(@fieldParentPtr(test_linked_list, "node", node).int.? == (6 - index));
            index += 1;
        }
    }
}

test "linked list concatenation" {
    var head: test_linked_list = undefined;
    var head2: test_linked_list = undefined;
    var one: test_linked_list = undefined;
    var two: test_linked_list = undefined;
    var three: test_linked_list = undefined;
    var four: test_linked_list = undefined;
    var five: test_linked_list = undefined;
    var six: test_linked_list = undefined;

    int(&head.node).int = null;
    int(&head2.node).int = null;
    int(&one.node).int = 1;
    int(&two.node).int = 2;
    int(&three.node).int = 3;
    int(&four.node).int = 4;
    int(&five.node).int = 5;

    head.node.init();
    head2.node.init();

    head.node.insertBefore(&one.node);
    head.node.insertBefore(&two.node);
    head2.node.insertBefore(&three.node);
    head2.node.insertBefore(&four.node);
    head2.node.insertBefore(&five.node);

    var h2 = int(head2.node.next);
    head2.node.remove();
    head.node.concat(&h2.node);

    testing.expect(int(head.node.last()).int.? == int(&five.node).int.?);
    testing.expect(head.node.len(500).? == 6);

    // Traverse forwards.
    {
        var he = &head.node;
        var node = he.next;
        var index: u32 = 1;
        while (node != he) : (node = node.next) {
            testing.expect(int(node).int.? == index);
            index += 1;
        }
    }

    // Traverse backwards.
    {
        var he = &head.node;
        var node = he.last();
        var index: u32 = 5;
        while (he != node) : (node = node.prev) {
            testing.expect(int(node).int.? == index);
            index -= 1;
        }
    }
}
