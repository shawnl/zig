// This file is in a package which has the root source file exposed as "@root".
// It is included in the compilation unit when exporting an executable.

const root = @import("@root");
const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

comptime {
    const strong_linkage = builtin.GlobalLinkage.Strong;
    if (builtin.link_libc) {
        @export("main", main, strong_linkage);
    } else if (builtin.os == builtin.Os.windows) {
        @export("WinMainCRTStartup", WinMainCRTStartup, strong_linkage);
    } else {
        @export("_start", _start, strong_linkage);
    }
}

nakedcc fn _start() noreturn {
    switch (builtin.arch) {
        builtin.Arch.x86_64 => {
            std.os.posix_argv_maybe = asm ("lea (%%rsp), %[argc]"
                : [argc] "=r" (-> ?[*]?[*]u8)
            );
        },
        builtin.Arch.i386 => {
            std.os.posix_argv_maybe = asm ("lea (%%esp), %[argc]"
                : [argc] "=r" (-> ?[*]?[*]u8)
            );
        },
        builtin.Arch.aarch64, builtin.Arch.aarch64_be => {
            std.os.posix_argv_maybe = asm ("mov %[argc], sp"
                : [argc] "=r" (-> ?[*]?[*]u8)
            );
        },
        else => @compileError("unsupported arch"),
    }

    // If LLVM inlines stack variables into _start, they will overwrite
    // the program initilization state.
    @noInlineCall(callMainAndExit);
}

extern fn WinMainCRTStartup() noreturn {
    @setAlignStack(16);
    if (!builtin.single_threaded) {
        _ = @import("bootstrap_windows_tls.zig");
    }
    std.os.windows.ExitProcess(callMain());
}

noinline fn posixInitilize() void {
    if (builtin.os == builtin.Os.freebsd) {
        @setAlignStack(16);
    }
    const argc = @ptrCast(*usize, std.os.posix_argv_maybe.?).*;
    // The _start code actually sets this to argc_ptr, in order to pass it
    // It has to be passed in a global variable because LLVM doesn't understand
    // the contraints of _start(), and clobbers the initilization state.
    std.os.posix_argv_maybe = @ptrCast(?[*]?[*]u8, std.os.posix_argv_maybe.? + 1);
    const argv = @ptrCast([*]usize, std.os.posix_argv_maybe);
    const envp = argv + argc + 1;
    std.os.posix_environ_maybe = @ptrCast([*]?[*]u8, envp);
    var envp_count: usize = 0;
    while (envp[envp_count] != 0) : (envp_count += 1) {}
    if (builtin.os == builtin.Os.linux) {
        // Scan auxiliary vector.
        const auxv = @ptrCast([*]std.elf.Auxv, envp + envp_count + 1);
        std.os.linux.elf_aux_maybe = auxv;
        var i: usize = 0;
        var at_phdr: usize = 0;
        var at_phnum: usize = 0;
        var at_phent: usize = 0;
        while (auxv[i].a_un.a_val != 0) : (i += 1) {
            switch (auxv[i].a_type) {
                std.elf.AT_PAGESZ => assert(auxv[i].a_un.a_val == std.os.page_size),
                std.elf.AT_PHDR => at_phdr = auxv[i].a_un.a_val,
                std.elf.AT_PHNUM => at_phnum = auxv[i].a_un.a_val,
                std.elf.AT_PHENT => at_phent = auxv[i].a_un.a_val,
                // This not needed by TLS initilization, but is useful to store now
                std.elf.AT_SYSINFO_EHDR => std.os.linux.vdso_addr_maybe = @intToPtr(?*std.elf.Ehdr, auxv[i].a_un.a_val),
                std.elf.AT_SECURE => {
                    if (auxv[i].a_un.a_val > 0) {
                        std.os.linux.secure_mode = true;
                    }
                },
                else => {},
            }
        }
        if (!builtin.single_threaded) linuxInitializeThreadLocalStorage(at_phdr, at_phnum, at_phent);
    }
}

fn callMainAndExit() noreturn {
    posixInitilize();

    // Prevent the optimizer from merging initialization code and user code
    asm ("" : "+r"(stage2) : : "memory" );
    std.os.posix.exit(callMain());
}

extern fn main(c_argc: i32, c_argv: [*][*]u8, c_envp: [*]?[*]u8) i32 {
    std.os.posix_argv_maybe = @ptrCast(?[*]?[*]u8, c_argv);
    std.os.posix_environ_maybe = @ptrCast([*]?[*]u8, c_envp);
    std.os.posix.exit(callMain());
}

// This is marked inline because for some reason LLVM in release mode fails to inline it,
// and we want fewer call frames in stack traces.
inline fn callMain() u8 {
    switch (@typeId(@typeOf(root.main).ReturnType)) {
        builtin.TypeId.NoReturn => {
            root.main();
        },
        builtin.TypeId.Void => {
            root.main();
            return 0;
        },
        builtin.TypeId.Int => {
            if (@typeOf(root.main).ReturnType.bit_count != 8) {
                @compileError("expected return type of main to be 'u8', 'noreturn', 'void', or '!void'");
            }
            return root.main();
        },
        builtin.TypeId.ErrorUnion => {
            root.main() catch |err| {
                std.debug.warn("error: {}\n", @errorName(err));
                if (builtin.os != builtin.Os.zen) {
                    if (@errorReturnTrace()) |trace| {
                        std.debug.dumpStackTrace(trace.*);
                    }
                }
                return 1;
            };
            return 0;
        },
        else => @compileError("expected return type of main to be 'u8', 'noreturn', 'void', or '!void'"),
    }
}

var tls_end_addr: usize = undefined;
const main_thread_tls_align = 32;
var main_thread_tls_bytes: [64]u8 align(main_thread_tls_align) = [1]u8{0} ** 64;

fn linuxInitializeThreadLocalStorage(at_phdr: usize, at_phnum: usize, at_phent: usize) void {
    var phdr_addr = at_phdr;
    var n = at_phnum;
    var base: usize = 0;
    while (n != 0) : ({
        n -= 1;
        phdr_addr += at_phent;
    }) {
        const phdr = @intToPtr(*std.elf.Phdr, phdr_addr);
        // TODO look for PT_DYNAMIC when we have https://github.com/ziglang/zig/issues/1917
        switch (phdr.p_type) {
            std.elf.PT_PHDR => base = at_phdr - phdr.p_vaddr,
            std.elf.PT_TLS => std.os.linux_tls_phdr = phdr,
            else => continue,
        }
    }
    const tls_phdr = std.os.linux_tls_phdr orelse return;
    std.os.linux_tls_img_src = @intToPtr([*]const u8, base + tls_phdr.p_vaddr);
    assert(main_thread_tls_bytes.len >= tls_phdr.p_memsz); // not enough preallocated Thread Local Storage
    assert(main_thread_tls_align >= tls_phdr.p_align); // preallocated Thread Local Storage not aligned enough
    @memcpy(&main_thread_tls_bytes, std.os.linux_tls_img_src, tls_phdr.p_filesz);
    tls_end_addr = @ptrToInt(&main_thread_tls_bytes) + tls_phdr.p_memsz;
    linuxSetThreadArea(@ptrToInt(&tls_end_addr));
}

fn linuxSetThreadArea(addr: usize) void {
    switch (builtin.arch) {
        builtin.Arch.x86_64 => {
            const ARCH_SET_FS = 0x1002;
            const rc = std.os.linux.syscall2(std.os.linux.SYS_arch_prctl, ARCH_SET_FS, addr);
            // acrh_prctl is documented to never fail
            assert(rc == 0);
        },
        else => @compileError("Unsupported architecture"),
    }
}
