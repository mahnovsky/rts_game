const std = @import("std");
const Atlas = @import("atlas.zig").Atlas;
const Rect = @import("atlas.zig").Rect;
const opengl = @import("opengl.zig");
const tt = @import("TrueType");

const warn = std.log.warn;

pub const MaxFontSize = 256;

pub const Error = error{} || anyerror;

pub const FontId = struct { index: u32 };
const FontData = struct {
    atlas: Atlas,
    name: []u8,
};

fn appendQuad(gpa: std.mem.Allocator, buffer: *std.ArrayListUnmanaged(opengl.Vertex3T), rect: Rect, atlas: *const Atlas, pos_x: *f32, pos_y: *f32) !void {
    const tw = @as(f32, @floatFromInt(atlas.texture_width));
    const th = @as(f32, @floatFromInt(atlas.texture_height));
    const w = @as(f32, @floatFromInt(rect.w));
    const h = @as(f32, @floatFromInt(rect.h));
    const tx = @as(f32, @floatFromInt(rect.x));
    const ty = @as(f32, @floatFromInt(rect.y));
    const off_x = @as(f32, @floatFromInt(rect.off_x));
    const off_y = @as(f32, @floatFromInt(rect.off_y));

    const ou = tx / tw;
    const ov = ty / th;
    const u = ou + (w / tw);
    const v = ov + (h / th);
    const x0 = std.math.floor((pos_x.* + off_x) + 0.5);
    const y1 = @abs(std.math.floor((pos_y.* + off_y) + 0.5));

    const x1 = x0 + w;
    const y0 = y1 - h;
    std.log.debug("*** x0: {d}; x1: {d}; y0: {d}; y1: {d}", .{ x0, x1, y0, y1 });

    const data = [_]opengl.Vertex3T{
        .{ .x = x0, .y = y0, .z = 0.0, .u = ou, .v = v },
        .{ .x = x1, .y = y0, .z = 0.0, .u = u, .v = v },
        .{ .x = x1, .y = y1, .z = 0.0, .u = u, .v = ov },

        .{ .x = x0, .y = y0, .z = 0.0, .u = ou, .v = v },
        .{ .x = x1, .y = y1, .z = 0.0, .u = u, .v = ov },
        .{ .x = x0, .y = y1, .z = 0.0, .u = ou, .v = ov },
    };
    try buffer.appendSlice(gpa, &data);
    const adv: f32 = @floatFromInt(rect.hmet.advance_width);
    pos_x.* += (adv * rect.scale);
}

pub const TextRender = struct {
    const Self = @This();

    fonts: std.ArrayListUnmanaged(FontData),

    pub fn init(gpa: std.mem.Allocator, font_names: std.ArrayList([]u8)) anyerror!Self {
        var fonts: std.ArrayListUnmanaged(FontData) = .empty;

        const base_path = "./data/";
        for (font_names.items) |font_name| {
            const file_path = try gpa.alloc(u8, base_path.len + font_name.len);
            defer gpa.free(file_path);

            std.mem.copyForwards(u8, file_path, base_path);
            std.mem.copyForwards(u8, file_path[base_path.len..], font_name);
            std.log.debug("file_path {s}", .{file_path});
            var file = try std.fs.cwd().openFile(file_path, .{});
            defer file.close();

            var stream = std.io.StreamSource{ .file = file };
            const bytes = try stream.reader().readAllAlloc(gpa, std.math.maxInt(usize));
            defer gpa.free(bytes);

            const font_atlas = try Atlas.initFromFont(gpa, 32, 96, bytes);

            try fonts.append(gpa, .{
                .atlas = font_atlas,
                .name = font_name,
            });
        }
        return Self{ .fonts = fonts };
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        for (self.fonts.items) |*font_data| {
            font_data.atlas.deinit(gpa);
        }
        self.fonts.deinit(gpa);
    }

    pub fn getFontId(self: Self, font_name: []const u8) ?FontId {
        for (self.fonts.items, 0..) |font_data, i| {
            if (std.mem.eql(u8, font_data.name, font_name)) {
                return FontId{ .index = @intCast(i) };
            }
        }
        return null;
    }

    pub fn addFont(self: *Self, gpa: std.mem.Allocator, font_name: []u8, font_data: []u8) !void {
        const font_atlas = try Atlas.initFromFont(gpa, 32, 96, font_data);
        self.fonts.append(gpa, .{
            .atlas = font_atlas,
            .name = font_name,
        });
    }

    pub fn makeString(self: Self, gpa: std.mem.Allocator, font_id: FontId, str: []const u8) !opengl.DrawingObject {
        const atlas = &self.fonts.items[font_id.index].atlas;
        var data = try std.ArrayListUnmanaged(opengl.Vertex3T).initCapacity(gpa, str.len);
        defer data.deinit(gpa);

        var pos_x: f32 = 0;
        var pos_y: f32 = 0;
        for (str) |s| {
            const rect = atlas.getSymbolRect(s);

            try appendQuad(gpa, &data, rect, atlas, &pos_x, &pos_y);
            std.log.debug("x {d}", .{pos_x});
        }
        const buffer = opengl.BufferObject.init(opengl.Vertex3T, data.items, opengl.BufferUsage.Dynamic);

        return opengl.DrawingObject.init(
            buffer,
            atlas.getTexture(),
            .{
                .flags = .init(.{ .Blend = true }),
                .func_params = .init(.{ .Blend = opengl.RenderStateFlags.TransparentBlend }),
            },
        );
    }

    //pub fn updateString(self: Self, str_obj: *opengl.DrawingObject, str: []u8) void {}
};
