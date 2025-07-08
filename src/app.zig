const std = @import("std");
const zigimg = @import("zigimg");
const TrueType = @import("TrueType");
const Atlas = @import("atlas.zig").Atlas;
const tr = @import("text_render.zig");
const Game = @import("Game.zig");
const shaders = @import("shaders.zig");
const Editor = @import("editor.zig").Editor;
const Window = @import("Window.zig");

const gl = @cImport({
    @cInclude("glad/glad.h");
});

const glfw = @cImport({
    @cInclude("glfw/glfw3.h");
});

const opengl = @import("opengl.zig");
const zm = @import("zm");

const c_cast = std.zig.c_translation.cast;
const warn = std.log.warn;
const panic = std.debug.panic;

export fn errorCallback(err: c_int, description: [*c]const u8) void {
    _ = err;
    panic("Error: {*}\n", .{description});
}

const AppInitError = error{
    FailedInitGLFW,
    FailedInitOpenGL,
} || anyerror;

const FrameInfo = struct {
    const Self = @This();
    begin_frame_time: f64 = 0,
    frame_time: f64 = 0,
    time: f64 = 0,
    prev_time: f64 = 0,
    fps: u32 = 0,
    fps_counter: u32 = 0,

    fn frameBegin(self: *Self) void {
        self.begin_frame_time = glfw.glfwGetTime();
    }

    fn frameEnd(self: *Self) void {
        self.frame_time = glfw.glfwGetTime() - self.begin_frame_time;
        self.time += self.frame_time;

        self.fps_counter += 1;
        if ((self.time - self.prev_time) >= 1.0) {
            self.fps = self.fps_counter;
            self.prev_time = self.time;
        }
    }
};

pub const App = struct {
    const Self = @This();

    window: *Window,
    width: u32,
    height: u32,
    allocator: std.mem.Allocator,
    text_render: tr.TextRender,
    frame_info: FrameInfo,
    editor: Editor,

    pub fn init(width: u32, height: u32, allocator: std.mem.Allocator) AppInitError!Self {
        _ = glfw.glfwSetErrorCallback(errorCallback);

        if (glfw.glfwInit() == glfw.GL_FALSE) {
            warn("Failed to initialize GLFW\n", .{});
            return error.FailedInitGLFW;
        }

        const window = try Window.create(allocator, width, height, "Application");

        opengl.clearColor(.{ 0.2, 0.3, 0.3 });

        var file = std.fs.cwd().openFile("./data/GoNotoCurrent-Regular.ttf", .{}) catch |err| {
            warn("error {s}", .{@errorName(err)});
            return error.FailedInitOpenGL;
        };

        defer file.close();
        var stream = std.io.StreamSource{ .file = file };
        const bytes = stream.reader().readAllAlloc(allocator, std.math.maxInt(usize)) catch |err| {
            warn("error {s}", .{@errorName(err)});
            return error.FailedInitOpenGL;
        };
        defer allocator.free(bytes);

        var font_atlas = try Atlas.initFromFont(allocator, 32, 96, bytes);
        defer font_atlas.deinit(allocator);

        var fonts = std.ArrayList([]u8).init(allocator);
        defer {
            for (fonts.items) |font_name| {
                allocator.free(font_name);
            }
            fonts.deinit();
        }

        try fonts.append(try allocator.dupe(u8, "GoNotoCurrent-Regular.ttf"));
        const text_render = try tr.TextRender.init(
            allocator,
            fonts,
        );

        if (text_render.getFontId("GoNotoCurrent-Regular.ttf")) |font_id| {
            std.log.debug("font id {d}", .{font_id.index});
        }

        return Self{
            .window = window,
            .width = width,
            .height = height,
            .allocator = allocator,
            .text_render = text_render,
            .frame_info = .{},
            .editor = Editor.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.text_render.deinit(self.allocator);
        self.editor.deinit();
        self.window.destroy();
    }

    pub fn run(self: *Self, game: *Game) !void {
        while (!self.window.isWindowShouldClose()) {
            self.frame_info.frameBegin();
            self.window.frameBegin();

            try game.update(self.frame_info.frame_time);

            gl.glClear(gl.GL_COLOR_BUFFER_BIT);

            game.draw();

            self.window.frameEnd();

            try self.editor.update(self, game);

            self.frame_info.frameEnd();
        }
    }
};
