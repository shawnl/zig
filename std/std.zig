pub const AlignedArrayList = @import("array_list.zig").AlignedArrayList;
pub const ArrayList = @import("array_list.zig").ArrayList;
pub const AutoHashMap = @import("hash_map.zig").AutoHashMap;
pub const BufMap = @import("buf_map.zig").BufMap;
pub const BufSet = @import("buf_set.zig").BufSet;
pub const Buffer = @import("buffer.zig").Buffer;
pub const BufferOutStream = @import("io.zig").BufferOutStream;
pub const DynLib = @import("dynamic_library.zig").DynLib;
pub const HashMap = @import("hash_map.zig").HashMap;
pub const LinkedList = @import("linked_list.zig").LinkedList;
pub const PriorityQueue = @import("priority_queue.zig").PriorityQueue;
pub const SegmentedList = @import("segmented_list.zig").SegmentedList;
pub const SpinLock = @import("spinlock.zig").SpinLock;

pub const base64 = @import("base64.zig");
pub const build = @import("build.zig");
pub const c = @import("c.zig");
pub const coff = @import("coff.zig");
pub const crypto = @import("crypto.zig");
pub const cstr = @import("cstr.zig");
pub const debug = @import("debug.zig");
pub const dwarf = @import("dwarf.zig");
pub const elf = @import("elf.zig");
pub const event = @import("event.zig");
pub const fmt = @import("fmt.zig");
pub const hash = @import("hash.zig");
pub const hash_map = @import("hash_map.zig");
pub const heap = @import("heap.zig");
pub const io = @import("io.zig");
pub const json = @import("json.zig");
pub const lazyInit = @import("lazy_init.zig").lazyInit;
pub const macho = @import("macho.zig");
pub const math = @import("math.zig");
pub const mem = @import("mem.zig");
pub const meta = @import("meta.zig");
pub const net = @import("net.zig");
pub const os = @import("os.zig");
pub const pdb = @import("pdb.zig");
pub const rand = @import("rand.zig");
pub const rb = @import("rb.zig");
pub const sort = @import("sort.zig");
pub const sync = @import("sync.zig");
pub const ascii = @import("ascii.zig");
pub const testing = @import("testing.zig");
pub const unicode = @import("unicode.zig");
pub const valgrind = @import("valgrind.zig");
pub const zig = @import("zig.zig");

test "std" {
    // run tests from these
    _ = @import("array_list.zig");
    _ = @import("buf_map.zig");
    _ = @import("buf_set.zig");
    _ = @import("buffer.zig");
    _ = @import("hash_map.zig");
    _ = @import("linked_list.zig");
    _ = @import("segmented_list.zig");
    _ = @import("spinlock.zig");
    _ = @import("sync.zig");

    _ = @import("ascii.zig");
    _ = @import("base64.zig");
    _ = @import("build.zig");
    _ = @import("c.zig");
    _ = @import("coff.zig");
    _ = @import("crypto.zig");
    _ = @import("cstr.zig");
    _ = @import("debug.zig");
    _ = @import("dwarf.zig");
    _ = @import("dynamic_library.zig");
    _ = @import("elf.zig");
    _ = @import("event.zig");
    _ = @import("fmt.zig");
    _ = @import("hash.zig");
    _ = @import("heap.zig");
    _ = @import("io.zig");
    _ = @import("json.zig");
    _ = @import("lazy_init.zig");
    _ = @import("macho.zig");
    _ = @import("math.zig");
    _ = @import("mem.zig");
    _ = @import("meta.zig");
    _ = @import("net.zig");
    _ = @import("os.zig");
    _ = @import("pdb.zig");
    _ = @import("priority_queue.zig");
    _ = @import("rand.zig");
    _ = @import("sort.zig");
    _ = @import("testing.zig");
    _ = @import("unicode.zig");
    _ = @import("valgrind.zig");
    _ = @import("zig.zig");
}
