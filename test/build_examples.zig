const tests = @import("tests.zig");
const builtin = @import("builtin");
const is_windows = builtin.os == builtin.Os.windows;

pub fn addCases(cases: *tests.BuildExamplesContext) void {
    cases.add("example/hello_world/hello.zig");
    cases.addC("example/hello_world/hello_libc.zig");
    cases.add("example/cat/main.zig");
    cases.add("example/guess_number/main.zig");
    cases.addBuildFile("test/standalone/main_pkg_path/build.zig");
    cases.addBuildFile("example/shared_library/build.zig");
    cases.addBuildFile("example/mix_o_files/build.zig");
    cases.addBuildFile("test/standalone/static_c_lib/build.zig");
    cases.addBuildFile("test/standalone/issue_339/build.zig");
    cases.addBuildFile("test/standalone/issue_794/build.zig");
    cases.addBuildFile("test/standalone/pkg_import/build.zig");
    cases.addBuildFile("test/standalone/use_alias/build.zig");
    cases.addBuildFile("test/standalone/brace_expansion/build.zig");
    cases.addBuildFile("test/standalone/empty_env/build.zig");
    if (builtin.os == builtin.Os.linux) {
        // TODO hook up the DynLib API for windows using LoadLibraryA
        // TODO figure out how to make this work on darwin - probably libSystem has dlopen/dlsym in it
        cases.addBuildFile("test/standalone/load_dynamic_library/build.zig");
    }

    cases.addBuildFile("test/stage1/c_abi/build.zig");
}
