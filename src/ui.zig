const std = @import("std");
const opengl = @import("opengl.zig");
const atlas = @import("atlas.zig");
const utils = @import("utils.zig");
const Window = @import("Window.zig");
const zigimg = @import("zigimg");

pub const UIRect = struct {
    const Self = @This();
    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn hitTest(self: Self, pos: @Vector(2, i32)) bool {
        const x = @as(f32, @floatFromInt(pos[0]));
        const y = @as(f32, @floatFromInt(pos[1]));
        return x > self.x and x < (self.x + self.w) and y > self.y and y < (self.y + self.h);
    }
};

pub const UIEvent = union(enum) {
    Pressed: void,
};

pub const UIElement = struct {
    const Self = @This();
    rect: UIRect,
    events: std.ArrayList(UIEvent),

    fn init(gpa: std.mem.Allocator, rect: UIRect) Self {
        return .{
            .rect = rect,
            .events = .init(gpa),
        };
    }

    fn deinit(self: Self) void {
        self.events.deinit();
    }

    fn processInput(self: *Self, window: *Window) !void {
        const pos = window.getCursorPos();
        if (self.rect.hitTest(pos)) {
            try self.events.append(.{.Pressed});
        }
    }
};

pub const UILayer = struct {
    const Self = @This();
    vertices: []opengl.Vertex3T,
    render: opengl.DrawingObject,
    atl: atlas.Atlas,

    elements: std.ArrayList(UIElement),

    pub fn init(gpa: std.mem.Allocator, capacity: u32, atlas_path: []const u8) !Self {
        var image = try zigimg.Image.fromFilePath(gpa, atlas_path);
        defer image.deinit();

        const vertices = try gpa.alloc(opengl.Vertex3T, capacity);
        const vbo = opengl.BufferObject.init(opengl.Vertex3T, vertices, .Dynamic);
        const atl = atlas.Atlas.initGreed(gpa, &image, 32, 32);
        return .{
            .render = .init(
                vbo,
                atl.getTexture(),
                .{ .flags = .init(.{ .Blend = true }), .func_params = .init(.{ .Blend = .TransparentBlend }) },
            ),
            .elements = .init(gpa),
            .atl = atl,
        };
    }

    //pub fn update(self: Self) void {}
    pub fn draw(self: Self) void {
        self.render.drawBegin();
        self.render.draw();
        self.render.drawEnd();
    }
};
