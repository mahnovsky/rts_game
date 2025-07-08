const std = @import("std");
const opengl = @import("opengl.zig");
const atlas = @import("atlas.zig");
const shaders = @import("shaders.zig");
const zm = @import("zm");
const ed = @import("editor.zig");
const glfw = @cImport({
    @cInclude("glfw/glfw3.h");
});
const gl = @cImport({
    @cInclude("glad/glad.h");
});

pub const TextureView = struct {
    const Self = @This();
    rects: []atlas.Rect,
    texture_render: opengl.DrawingObject,
    gpa: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator, atl: *const atlas.Atlas, proj: zm.Mat4f) !Self {
        const rects = try gpa.dupe(atlas.Rect, atl.rects);
        const vertices = try gpa.alloc(opengl.Vertex3T, rects.len * 6);
        defer gpa.free(vertices);
        const texture_size = atl.getTextureSize();
        for (rects, 0..rects.len) |rect, i| {
            const beg = i * 6;
            const end = beg + 6;
            const rect_pos = rect.getPosition();
            rect.makeQuad(
                texture_size.w,
                texture_size.h,
                rect_pos.x,
                rect_pos.y,
                1,
                vertices[beg..end],
            );
        }
        const vbo = opengl.BufferObject.init(opengl.Vertex3T, vertices, opengl.BufferUsage.Static);

        const program = try opengl.Program.init(shaders.map_vshader, shaders.fshader);
        program.use();
        const ident = zm.Mat4f.identity();
        program.setUniformMatrix("Camera", ident);
        program.setUniformMatrix("Model", ident);
        program.setUniformMatrix("Projection", proj);

        return .{
            .rects = rects,
            .texture_render = opengl.DrawingObject.init(
                vbo,
                atl.getTexture(),
                .{ .flags = .init(.{ .Blend = true }), .func_params = .init(.{ .Blend = .TransparentBlend }) },
            ),
            .gpa = gpa,
        };
    }

    pub fn deinit(self: Self) void {
        self.gpa.free(self.rects);
    }

    pub fn draw(self: Self) void {
        self.texture_render.drawBegin();
        self.texture_render.draw();
        self.texture_render.drawEnd();
    }
};

pub const TextureViewWindow = struct {
    const Self = @This();
    window: ?*glfw.GLFWwindow,
    window_size: @Vector(2, u32),
    texture_view: TextureView,
    editor: *ed.Editor,

    pub fn init(gpa: std.mem.Allocator, atl: *const atlas.Atlas, orig: ?*glfw.GLFWwindow, editor: *ed.Editor) !Self {
        glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MAJOR, 3);
        glfw.glfwWindowHint(glfw.GLFW_CONTEXT_VERSION_MINOR, 3);
        const window = glfw.glfwCreateWindow(
            @intCast(atl.texture_width),
            @intCast(atl.texture_height),
            "Texture View",
            null,
            orig,
        );

        glfw.glfwMakeContextCurrent(window);
        try opengl.init(&glfw.glfwGetProcAddress);
        opengl.clearColor(.{ 0.2, 0.3, 0.3 });

        const proj = zm.Mat4f.orthographic(
            0,
            @floatFromInt(atl.texture_width),
            0,
            @floatFromInt(atl.texture_height),
            0,
            100,
        );

        return .{
            .window = window,
            .window_size = .{ atl.texture_width, atl.texture_height },
            .texture_view = try .init(gpa, atl, proj),
            .editor = editor,
        };
    }

    pub fn close(self: *Self) void {
        if (self.window != null) {
            self.texture_view.deinit();
            glfw.glfwDestroyWindow(self.window);
            self.window = null;
        }
    }

    pub fn update(self: *Self) !void {
        if (self.window != null) {
            glfw.glfwMakeContextCurrent(self.window);
            gl.glClear(gl.GL_COLOR_BUFFER_BIT);

            self.texture_view.draw();

            glfw.glfwSwapBuffers(self.window);
            glfw.glfwPollEvents();

            if (glfw.glfwWindowShouldClose(self.window) > 0) {
                self.close();
                return;
            }

            if (glfw.glfwGetMouseButton(self.window, glfw.GLFW_MOUSE_BUTTON_1) == glfw.GLFW_PRESS) {
                var xpos: f64 = undefined;
                var ypos: f64 = undefined;
                glfw.glfwGetCursorPos(self.window, &xpos, &ypos);
                const pos: @Vector(2, u16) = .{ @intFromFloat(xpos), @intFromFloat(ypos) };

                const mouse_y = @as(u16, @intCast(self.window_size[1])) - pos[1];
                const pos_x = pos[0];
                const pos_y = mouse_y;
                //std.log.debug("test click pos {d} : {d}", .{ pos_x, pos_y });
                const rects = self.texture_view.rects;
                for (rects, 0..rects.len) |rect, index| {
                    if (rect.hitTest(pos_x, pos_y)) {
                        try self.editor.pushCommand(.{ .PickTextureIndex = @intCast(index) });
                        break;
                    }
                }
            }
        }
    }
};
