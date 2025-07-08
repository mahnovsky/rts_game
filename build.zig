const std = @import("std");

const CompileStep = std.Build.Step.Compile;

pub fn buildGlad(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *CompileStep {
    const c_flags = [_][]const u8{
        // when compiling this lib in debug mode, it seems to add -fstack-protector so if you want to link it
        // with an exe built with -Dtarget=x86_64-windows-msvc you need the line below or you'll get undefined symbols
        "-fno-stack-protector",
        // don't want to add some functions (__mingw_vsscanf etc.), also needed for building exe with msvc abi
        "-D_STDIO_DEFINED",
        // added to windows builds (https://github.com/glfw/glfw/blob/076bfd55be45e7ba5c887d4b32aa03d26881a1fb/src/CMakeLists.txt#L144)
        "-D_UNICODE",
        "-DUNICODE",
    };

    const lib = b.addStaticLibrary(.{ .target = target, .name = "glad", .optimize = optimize });
    lib.linkLibC();

    lib.addIncludePath(b.path("external/glad/include"));
    lib.addCSourceFile(.{ .file = b.path("external/glad/src/glad.c"), .flags = &c_flags });

    return lib;
}

pub fn buildGlfw3(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *CompileStep {
    const lib = b.addStaticLibrary(.{ .target = target, .name = "glfw3", .optimize = optimize });
    lib.linkLibC();
    lib.addIncludePath(.{ .path = "./external/glfw/src" });
    lib.addIncludePath(.{ .path = "./external/glfw/include" });
    lib.addIncludePath(.{ .path = "./external/glfw/build/src" });

    const c_flags = [_][]const u8{ "-fno-stack-protector", "-D_STDIO_DEFINED", "-DWIN32", "-D_WINDOWS", "-DNDEBUG", "-D_GLFW_WIN32", "-DUNICODE", "-D_UNICODE", "-D_CRT_SECURE_NO_WARNINGS" };

    const sources = [_][]const u8{
        "context.c",
        "init.c",
        "input.c",
        "monitor.c",
        "platform.c",
        "vulkan.c",
        "window.c",
        "egl_context.c",
        "osmesa_context.c",
        "null_init.c",
        "null_monitor.c",
        "null_window.c",
        "null_joystick.c",
        "win32_time.h",
        "win32_thread.h",
        "win32_module.c",
        "win32_time.c",
        "win32_thread.c",
        "win32_init.c",
        "win32_joystick.c",
        "win32_monitor.c",
        "win32_window.c",
        "wgl_context.c",
    };

    const src_dir = "./external/glfw/src/";
    inline for (sources) |src| {
        lib.addCSourceFile(.{ .file = .{ .path = src_dir ++ src }, .flags = &c_flags });
    }

    return lib;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .os_tag = std.Target.Os.Tag.windows, .abi = std.Target.Abi.msvc } });
    const optimize = b.standardOptimizeOption(.{});

    const glad = buildGlad(b, target, optimize);
    //const glfw3 = buildGlfw3(b, target, optimize);

    const exe = b.addExecutable(.{
        .name = "tanks",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.addIncludePath(b.path("external/glad/include"));
    exe.addIncludePath(b.path("external/glfw/include"));
    exe.addIncludePath(b.path("external/glfw/src"));
    exe.addLibraryPath(b.path("external/glfw/build/src/Release"));

    exe.linkLibC();
    exe.linkLibrary(glad);
    //exe.linkLibrary(glfw3);
    exe.linkSystemLibrary("glfw3");
    exe.linkSystemLibrary("opengl32");
    exe.linkSystemLibrary("kernel32");
    exe.linkSystemLibrary("user32");
    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("winspool");
    exe.linkSystemLibrary("shell32");
    exe.linkSystemLibrary("ole32");
    exe.linkSystemLibrary("oleaut32");
    exe.linkSystemLibrary("uuid");
    exe.linkSystemLibrary("comdlg32");
    exe.linkSystemLibrary("advapi32");

    const zm = b.dependency("zm", .{});
    exe.root_module.addImport("zm", zm.module("zm"));

    const zigimg_dependency = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zigimg", zigimg_dependency.module("zigimg"));

    const tt = b.dependency("TrueType", .{});
    exe.root_module.addImport("TrueType", tt.module("TrueType"));

    const yaml = b.dependency("yaml", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("yaml", yaml.module("yaml"));

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
