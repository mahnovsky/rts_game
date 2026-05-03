const std = @import("std");

const CompileStep = std.Build.Step.Compile;

pub fn buildGlad(b: *std.Build, _: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *CompileStep {
    const c_flags = [_][]const u8{
        // when compiling this lib in debug mode, it seems to add -fstack-protector so if you want to link it
        // with an exe built with -Dtarget=x86_64-windows-msvc you need the line below or you'll get undefined symbols
        "-fno-stack-protector",
        // don't want to add some functions (__mingw_vsscanf etc.), also needed for building exe with msvc abi
        "-D_STDIO_DEFINED",
        // added to windows builds (https://github.com/glfw/glfw/blob/076bfd55be45e7ba5c887d4b32aa03d26881a1fb/src/CMakeLists.txt#L144)
        "-D_UNICODE",
        "-DUNICODE",
        "-pthread",
        "-fobjc-arc",
    };

    //const lib = b.addStaticLibrary(.{ .target = target, .name = "glad", .optimize = optimize });
    const module = b.createModule(.{
        .link_libc = true,
        .target = target,
        .optimize = optimize,
    });

    switch (target.result.os.tag) {
        .macos => {
            if (b.sysroot) |sysroot| {
                std.log.info("Macos sysroot {s}", .{sysroot});
                system_include_path = .{ .cwd_relative = b.pathJoin(&.{ sysroot, "usr/include" }) };
                system_framework_path = .{ .cwd_relative = b.pathJoin(&.{ sysroot, "System/Library/Frameworks" }) };
                library_path = .{ .cwd_relative = "/usr/lib" }; // ???
            } else if (!target.query.isNative()) {
                std.log.err("'--sysroot' is required when building SDL for non-native macOS targets", .{});
                std.process.exit(1);
            }
        },
        else => {},
    }

    module.addIncludePath(b.path("external/glad/include"));
    module.addCSourceFile(.{ .file = b.path("external/glad/src/glad.c"), .flags = &c_flags });
    const lib = b.addLibrary(.{
        .root_module = module,
        .name = "glad",
        .linkage = .static,
    });

    return lib;
}

pub fn buildGlfw3(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *CompileStep {
    const module = b.createModule(.{
        .link_libc = true,
        .target = target,
        .optimize = optimize,
    });

    module.addIncludePath(b.path("external/glfw/src"));
    module.addIncludePath(b.path("external/glfw/include"));
    module.addIncludePath(b.path("external/glfw/build/src"));
    const windows_c_flags = [_][]const u8{
        "-fno-stack-protector",
        "-D_STDIO_DEFINED",
        "-DWIN32",
        "-D_WINDOWS",
        "-DNDEBUG",
        "-D_GLFW_WIN32",
        "-DUNICODE",
        "-D_UNICODE",
        "-D_CRT_SECURE_NO_WARNINGS",
    };

    const mac_c_flags = [_][]const u8{
        "-fno-stack-protector",
        "-D_STDIO_DEFINED",
        "-DUNICODE",
        "-D_UNICODE",
        "-D_CRT_SECURE_NO_WARNINGS",
        "-D_GLFW_COCOA",
    };

    const common_sources = [_][]const u8{
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
    };

    const windows_sources = [_][]const u8{
        //"win32_time.h",
        //"win32_thread.h",
        "win32_module.c",
        "win32_time.c",
        "win32_thread.c",
        "win32_init.c",
        "win32_joystick.c",
        "win32_monitor.c",
        "win32_window.c",
        "wgl_context.c",
    };

    const mac_sources = [_][]const u8{
        "cocoa_time.c",
        "posix_module.c",
        "posix_thread.c",
        "cocoa_init.m",
        "cocoa_joystick.m",
        "cocoa_monitor.m",
        "cocoa_window.m",
        "nsgl_context.m",
    };

    const src_dir = "external/glfw/src/";
    if (windows) {
        inline for (common_sources ++ windows_sources) |src| {
            module.addCSourceFile(.{ .file = b.path(src_dir ++ src), .flags = &windows_c_flags });
        }
    } else if (macos) {
        if (system_include_path) |path| {
            module.addSystemIncludePath(path);
        }
        if (system_framework_path) |path| {
            module.addSystemFrameworkPath(path);
        }
        if (library_path) |path| {
            module.addLibraryPath(path);
        }
        module.linkSystemLibrary("objc", .{});
        module.linkFramework("CoreFoundation", .{});
        module.linkFramework("AppKit", .{});
        module.linkFramework("CoreServices", .{});
        module.linkFramework("Metal", .{});
        module.linkFramework("CoreGraphics", .{});
        module.linkFramework("IOKit", .{});
        module.linkFramework("Foundation", .{});
        inline for (common_sources ++ mac_sources) |src| {
            module.addCSourceFile(.{ .file = b.path(src_dir ++ src), .flags = &mac_c_flags });
        }
    }

    const lib = b.addLibrary(.{
        .root_module = module,
        .name = "glfw3",
        .linkage = .static,
    });

    return lib;
}

fn collectFiles(b: *std.Build, path: []const u8, ext: []const u8) ![]const []const u8 {
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(b.allocator);

    // The directory to scan for C files
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| {
        std.log.err("file open err", .{});
        return err;
    };
    var it = dir.iterate();

    std.log.info("Collection files {s} begin: {s}", .{ ext, path });
    while (try it.next()) |file| {
        if (file.kind == .file and std.mem.eql(u8, ext, std.fs.path.extension(file.name))) {
            // Construct the full path and append it
            try files.append(b.allocator, file.name);
            std.log.info("Add src file: {s}", .{file.name});
        }
    }
    std.log.info("Collection files end", .{});
    return files.toOwnedSlice(b.allocator);
}

fn buildImgui(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *CompileStep {
    const module = b.createModule(.{
        .link_libcpp = true,
        .link_libc = true,
        .target = target,
        .optimize = optimize,
    });
    module.addCMacro("CIMGUI_USE_GLFW", "1");
    module.addCMacro("CIMGUI_USE_OPENGL3", "1");

    const root_path = "external/cimgui";
    const im_path = root_path ++ "/imgui";
    const backends = im_path ++ "/backends";

    module.addIncludePath(b.path(root_path));
    module.addIncludePath(b.path(im_path));
    module.addIncludePath(b.path(backends));
    module.addIncludePath(b.path("external/glfw/include"));
    module.addCSourceFile(.{ .file = b.path(backends ++ "/imgui_impl_glfw.cpp"), .language = .cpp });
    module.addCSourceFile(.{ .file = b.path(backends ++ "/imgui_impl_opengl3.cpp"), .language = .cpp });

    module.addCSourceFile(.{ .file = b.path(root_path ++ "/cimgui.cpp") });
    module.addCSourceFile(.{ .file = b.path(root_path ++ "/cimgui_impl.cpp") });

    module.addCSourceFile(.{ .file = b.path(im_path ++ "/imgui_widgets.cpp"), .language = .cpp });
    module.addCSourceFile(.{ .file = b.path(im_path ++ "/imgui.cpp"), .language = .cpp });
    module.addCSourceFile(.{ .file = b.path(im_path ++ "/imgui_tables.cpp"), .language = .cpp });
    module.addCSourceFile(.{ .file = b.path(im_path ++ "/imgui_demo.cpp"), .language = .cpp });
    module.addCSourceFile(.{ .file = b.path(im_path ++ "/imgui_draw.cpp"), .language = .cpp });

    return b.addLibrary(.{
        .root_module = module,
        .name = "cimgui",
        .linkage = .static,
    });
}

var system_include_path: ?std.Build.LazyPath = null;
var system_framework_path: ?std.Build.LazyPath = null;
var library_path: ?std.Build.LazyPath = null;
var windows = false;
var macos = false;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .os_tag = std.Target.Os.Tag.windows, .abi = std.Target.Abi.msvc } });
    // .default_target = .{ .os_tag = std.Target.Os.Tag.windows, .abi = std.Target.Abi.msvc } });
    const optimize = b.standardOptimizeOption(.{});

    switch (target.result.os.tag) {
        .windows => {
            windows = true;
        },
        .macos => {
            macos = true;
            if (b.sysroot) |sysroot| {
                system_include_path = .{ .cwd_relative = b.pathJoin(&.{ sysroot, "usr/include" }) };
                system_framework_path = .{ .cwd_relative = b.pathJoin(&.{ sysroot, "System/Library/Frameworks" }) };
                library_path = .{ .cwd_relative = "/usr/lib" }; // ???
                std.log.info("Mac os", .{});
            } else if (!target.query.isNative()) {
                std.log.err("'--sysroot' is required when building SDL for non-native macOS targets", .{});
                std.process.exit(1);
            }
        },

        else => {
            std.log.info("target {s}", .{@tagName(target.result.os.tag)});
        },
    }
    const glfw3 = buildGlfw3(b, target, optimize);
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const glad = buildGlad(b, root_module, target, optimize);
    //const cimgui = buildImgui(b, target, optimize);

    root_module.addIncludePath(b.path("external/glad/include"));
    root_module.addIncludePath(b.path("external/glfw/include"));
    root_module.addIncludePath(b.path("external/glfw/src"));
    root_module.addLibraryPath(b.path("external/glfw/build/src/Release"));
    root_module.addIncludePath(b.path("external/cimgui"));
    root_module.addLibraryPath(b.path("external/cimgui"));

    root_module.linkLibrary(glad);
    root_module.linkLibrary(glfw3);
    //root_module.link_libcpp = true;

    //root_module.linkLibrary(cimgui);
    //root_module.linkSystemLibrary("glfw3", .{});
    if (windows) {
        root_module.linkSystemLibrary("opengl32", .{});
        root_module.linkSystemLibrary("kernel32", .{});
        root_module.linkSystemLibrary("user32", .{});
        root_module.linkSystemLibrary("gdi32", .{});
        root_module.linkSystemLibrary("winspool", .{});
        root_module.linkSystemLibrary("shell32", .{});
        root_module.linkSystemLibrary("ole32", .{});
        root_module.linkSystemLibrary("oleaut32", .{});
        root_module.linkSystemLibrary("uuid", .{});
        root_module.linkSystemLibrary("comdlg32", .{});
        root_module.linkSystemLibrary("advapi32", .{});
        root_module.linkSystemLibrary("cimgui", .{ .preferred_link_mode = .static });
        //root_module.addObjectFile(b.path("external/cimgui/cimgui.lib"));
    }
    if (macos) {
        std.log.info("add frameworks", .{});
        // -framework Cocoa -framework OpenGL -framework IOKit
        root_module.linkSystemLibrary("objc", .{});
        root_module.linkSystemLibrary("cimgui", .{});
        //root_module.addObjectFile(b.path("external/cimgui/cimgui.dylib"));
        root_module.linkFramework("CoreFoundation", .{});
        root_module.linkFramework("AppKit", .{});
        root_module.linkFramework("CoreServices", .{});
        root_module.linkFramework("Metal", .{});
        root_module.linkFramework("CoreGraphics", .{});
        root_module.linkFramework("IOKit", .{});
        root_module.linkFramework("Foundation", .{});
    }

    const zm = b.dependency("zm", .{});

    const exe = b.addExecutable(.{
        .name = "rts_game",
        .root_module = root_module,
    });
    exe.root_module.addImport("zm", zm.module("zm"));

    const zigimg_dependency = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zigimg", zigimg_dependency.module("zigimg"));

    const tt = b.dependency("TrueType", .{});
    exe.root_module.addImport("TrueType", tt.module("TrueType"));

    const yaml = b.dependency("zig_yaml", .{
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
