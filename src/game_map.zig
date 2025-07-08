const std = @import("std");
const yaml = @import("yaml");
const Yaml = @import("yaml").Yaml;
const Atlas = @import("atlas.zig").Atlas;
const Rect = @import("atlas.zig").Rect;
const zigimg = @import("zigimg");
const opengl = @import("opengl.zig");
const shaders = @import("shaders.zig");
const zm = @import("zm");
const TextureView = @import("texture_view.zig").TextureView;

const TileScale: f32 = 2;
const Cell = struct {
    const Self = @This();
};

fn appendQuad(gpa: std.mem.Allocator, buffer: *std.ArrayListUnmanaged(opengl.Vertex3T), rect: Rect, atlas: *const Atlas, pos_x: *f32, y_offset: f32, scale: f32) !void {
    const rect_size = rect.getSize();
    const x0: f32 = pos_x.*;
    const y0: f32 = y_offset * rect_size.h * scale;

    const texture_size = atlas.getTextureSize();
    var quad: [6]opengl.Vertex3T = undefined;
    rect.makeQuad(texture_size.w, texture_size.h, x0, y0, TileScale, &quad);
    try buffer.appendSlice(gpa, &quad);

    pos_x.* += (rect_size.w * scale);
}

fn makeVertexData(gpa: std.mem.Allocator, buffer: *std.ArrayListUnmanaged(opengl.Vertex3T), indices: []const u16, atlas: *const Atlas, w: f32) ![]opengl.Vertex3T {
    var x: f32 = 0;
    var y: f32 = 0;
    for (indices, 0..indices.len) |c, pos| {
        const index = std.math.clamp(@as(u32, c), 0, atlas.rects.len - 1);
        const next_y = @floor(@as(f32, @floatFromInt(pos)) / w);
        std.log.debug("makeVertexData index={d} y = {d}", .{ pos, y });
        if (next_y > y) {
            x = 0;
            y = next_y;
        }

        try appendQuad(
            gpa,
            buffer,
            atlas.rects[index],
            atlas,
            &x,
            y,
            TileScale,
        );
    }

    return buffer.items;
}

const Allocator = std.mem.Allocator;

pub const Serializer = struct {
    const Self = @This();
    saveFunc: ?*const fn (Allocator, *const MapData) []u8 = null,
    loadFunc: ?*const fn (Allocator, []u8) MapData = null,

    pub fn init(comptime T: type) Serializer {
        const gen = struct {
            fn save(arena: Allocator, map_data: *const MapData) []u8 {
                return T.save(arena, map_data);
            }

            fn load(arena: Allocator, data: []u8) MapData {
                return T.load(arena, data);
            }
        };

        return .{
            .saveFunc = gen.save,
            .loadFunc = gen.load,
        };
    }

    fn save(self: Self, gpa: Allocator, map_data: *const MapData) []u8 {
        if (self.saveFunc) |saveFunc| {
            return saveFunc(gpa, map_data);
        }
        unreachable;
    }

    fn load(self: Self, gpa: Allocator, data: []u8) MapData {
        if (self.loadFunc) |loadFunc| {
            return loadFunc(gpa, data);
        }
        unreachable;
    }
};

pub const YamlSerializer = struct {
    const Self = @This();

    fn load(gpa: Allocator, data: []u8) MapData {
        var doc = Yaml{ .source = data };

        doc.load(gpa) catch {
            return MapData.empty;
        };

        const map_data = doc.parse(gpa, MapData) catch MapData.empty;

        return map_data;
    }

    fn save(gpa: Allocator, map_data: *const MapData) []u8 {
        var list = std.ArrayList(u8).init(gpa);
        yaml.stringify(gpa, map_data.*, list.writer()) catch return &.{};

        return list.toOwnedSlice() catch &.{};
    }
};

pub const MapData = struct {
    const Self = @This();
    const TileSize: f32 = 32 * TileScale;
    const empty: Self = .{ .width = 0, .height = 0, .tile_data = &.{} };

    width: u32,
    height: u32,
    tile_data: []u16,

    pub fn load(gpa: std.mem.Allocator, data: []u8, s: Serializer) !MapData {
        const map_data = s.load(gpa, data);

        return .{
            .width = map_data.width,
            .height = map_data.height,
            .tile_data = try gpa.dupe(u16, map_data.tile_data),
        };
    }

    pub fn save(self: Self, gpa: std.mem.Allocator, s: Serializer) ![]u8 {
        return s.save(gpa, &self);
    }

    pub fn deinit(self: Self, gpa: std.mem.Allocator) void {
        gpa.free(self.tile_data);
    }

    pub fn getTile(self: Self, x: u32, y: u32) ?u16 {
        if (x < self.width and y < self.height) {
            const index = x + y * self.width;
            return self.tile_data[index];
        }
        return null;
    }

    pub fn setTile(self: Self, x: u32, y: u32, tile: u16) void {
        if (x < self.width and y < self.height) {
            const index = x + y * self.width;
            self.tile_data[index] = tile;
        }
    }
};

const MapRenderData = struct {
    const Self = @This();
    atlas: Atlas,
    vertices: []opengl.Vertex3T,
    vbo: opengl.BufferObject,

    fn init(gpa: std.mem.Allocator, map_data: MapData, atlas_image: *zigimg.Image) !Self {
        const atl = try Atlas.initGreed(gpa, atlas_image, 32, 32);

        var buffer: std.ArrayListUnmanaged(opengl.Vertex3T) = .empty;
        defer buffer.deinit(gpa);

        const vertices = try makeVertexData(
            gpa,
            &buffer,
            map_data.tile_data,
            &atl,
            @floatFromInt(map_data.width),
        );

        return .{
            .atlas = atl,
            .vertices = try gpa.dupe(opengl.Vertex3T, vertices),
            .vbo = opengl.BufferObject.init(opengl.Vertex3T, vertices, .Dynamic),
        };
    }

    fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        gpa.free(self.vertices);
        self.atlas.deinit(gpa);
    }

    pub fn update_texture_coords(self: Self, map_data: *const MapData, x: u32, y: u32, tile_index: u32) void {
        const rect = self.atlas.rects[tile_index];
        const texture_size = self.atlas.getTextureSize();
        const rect_size = rect.getSize();
        const pos_x = @as(f32, @floatFromInt(x)) * rect_size.w * TileScale;
        const pos_y = @as(f32, @floatFromInt(y)) * rect_size.h * TileScale;
        const vertex_offset = (x + y * map_data.width) * 6;

        var quad: [6]opengl.Vertex3T = undefined;
        rect.makeQuad(texture_size.w, texture_size.h, pos_x, pos_y, TileScale, &quad);

        for (0..6) |i| {
            //std.log.debug("prev pos {d}:{d}", .{ self.vertices[vertex_offset + i].x, self.vertices[vertex_offset + i].y });
            self.vertices[vertex_offset + i] = quad[i];
        }

        self.vbo.update(
            opengl.Vertex3T,
            &quad,
            vertex_offset * @sizeOf(opengl.Vertex3T),
        );
    }
};

pub const GameMap = struct {
    const Self = @This();
    render_data: MapRenderData,
    map_data: MapData,
    shader: opengl.Program,
    map_render: opengl.DrawingObject,

    pub fn init(gpa: std.mem.Allocator, atlas_path: []const u8, map_data: MapData, proj: zm.Mat4f) !Self {
        var image = try zigimg.Image.fromFilePath(gpa, atlas_path);
        defer image.deinit();

        const program = try opengl.Program.init(shaders.map_vshader, shaders.fshader);
        program.use();
        const ident = zm.Mat4f.identity();
        program.setUniformMatrix("Camera", ident);
        program.setUniformMatrix("Model", ident);
        program.setUniformMatrix("Projection", proj);

        const render_data = try MapRenderData.init(gpa, map_data, &image);

        return .{
            .render_data = render_data,
            .map_data = map_data,
            .shader = program,
            .map_render = opengl.DrawingObject.init(
                render_data.vbo,
                render_data.atlas.getTexture(),
                .{ .flags = .init(.{ .Blend = true }), .func_params = .init(.{ .Blend = .TransparentBlend }) },
            ),
        };
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        self.render_data.deinit(gpa);
        self.map_data.deinit(gpa);
    }

    pub fn draw(self: Self, camera: *const zm.Mat4f) void {
        self.shader.use();
        self.shader.setUniformMatrix("Camera", camera.*);
        self.map_render.drawBegin();
        self.map_render.draw();
        self.map_render.drawEnd();
    }

    pub fn tryReplaceTile(self: Self, x: u32, y: u32, tile: u16) void {
        if (self.map_data.getTile(x, y)) |current| {
            if (tile != current) {
                self.map_data.setTile(x, y, tile);
                self.render_data.update_texture_coords(&self.map_data, x, y, tile);
            }
        }
    }

    pub fn isCoordsValid(self: Self, x: f32, y: f32) bool {
        const w = @as(f32, @floatFromInt(self.map_data.width)) * MapData.TileSize;
        const h = @as(f32, @floatFromInt(self.map_data.height)) * MapData.TileSize;

        return x >= 0 and x <= w and y >= 0 and y <= h;
    }

    pub fn convertScreen2TileCoords(self: Self, x: f32, y: f32) ?@Vector(2, u32) {
        if (!self.isCoordsValid(x, y)) {
            return null;
        }

        return .{
            @intFromFloat(@floor(x / MapData.TileSize)),
            @intFromFloat(@floor(y / MapData.TileSize)),
        };
    }
};
