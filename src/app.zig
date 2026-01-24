const std = @import("std");
const zigimg = @import("zigimg");
const TrueType = @import("TrueType");
const Atlas = @import("atlas.zig").Atlas;
const tr = @import("text_render.zig");
const Game = @import("Game.zig");
const shaders = @import("shaders.zig");
const Editor = @import("editor.zig").Editor;
const Window = @import("Window.zig");
const Utils = @import("utils.zig");
const ObjectStorage = @import("ObjectStorage.zig");
var buffer: [1024 * 8]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
const context_allocator = fba.allocator();
pub var context: ObjectStorage = .init(context_allocator);

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
    panic("Error: {s}\n", .{description});
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

    pub const glsl_version: [*c]const u8 = "#version 150";
    window: *Window,
    width: u32,
    height: u32,
    allocator: std.mem.Allocator,
    text_render: tr.TextRender,
    frame_info: FrameInfo,
    editor: Editor,
    game: *Game,

    pub fn init(width: u32, height: u32, allocator: std.mem.Allocator) AppInitError!*Self {
        _ = glfw.glfwSetErrorCallback(errorCallback);

        if (glfw.glfwInit() == glfw.GL_FALSE) {
            warn("Failed to initialize GLFW\n", .{});
            return error.FailedInitGLFW;
        }

        glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 3);
        glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 2);
        glfw.glfwWindowHint(glfw.GLFW_OPENGL_PROFILE, glfw.GLFW_OPENGL_CORE_PROFILE); // 3.2+ only
        glfw.glfwWindowHint(glfw.GLFW_OPENGL_FORWARD_COMPAT, glfw.GL_TRUE); // Required on Mac

        const window = try Window.create(allocator, width, height, "Application");
        try opengl.init(&glfw.glfwGetProcAddress);

        opengl.clearColor(.{ 0.2, 0.3, 0.3 });

        var file = std.fs.cwd().openFile("./data/GoNotoCurrent-Regular.ttf", .{}) catch |err| {
            warn("error {s}", .{@errorName(err)});
            return error.FailedInitOpenGL;
        };

        defer file.close();

        const bytes = try Utils.readFileData(allocator, "./data/GoNotoCurrent-Regular.ttf");
        defer allocator.free(bytes);

        var font_atlas = try Atlas.initFromFont(allocator, 32, 96, bytes);
        defer font_atlas.deinit(allocator);

        var fonts: std.ArrayList([]u8) = .empty;
        defer {
            for (fonts.items) |font_name| {
                allocator.free(font_name);
            }
            fonts.deinit(allocator);
        }

        try fonts.append(allocator, try allocator.dupe(u8, "GoNotoCurrent-Regular.ttf"));
        const text_render = try tr.TextRender.init(
            allocator,
            fonts,
        );

        if (text_render.getFontId("GoNotoCurrent-Regular.ttf")) |font_id| {
            std.log.debug("font id {d}", .{font_id.index});
        }

        var game = try Game.init(allocator, width, height);
        try game.postInit(window);

        try context.addResource(Self, Self{
            .window = window,
            .width = width,
            .height = height,
            .allocator = allocator,
            .text_render = text_render,
            .frame_info = .{},
            .editor = Editor.init(allocator),
            .game = game,
        });

        return context.getResource(Self).?;
    }

    pub fn deinit(self: *Self) void {
        self.game.deinit(self.allocator);
        self.text_render.deinit(self.allocator);
        self.editor.deinit();
        self.window.destroy(self.allocator);
    }

    pub fn run(self: *Self) !void {
        while (!self.window.isWindowShouldClose()) {
            self.frame_info.frameBegin();
            self.window.frameBegin();

            try self.game.update(self.window, self.frame_info.frame_time);

            gl.glClear(gl.GL_COLOR_BUFFER_BIT);

            self.game.draw();

            self.window.frameEnd();

            try self.editor.update(self, self.game);

            self.frame_info.frameEnd();
        }
    }
};
