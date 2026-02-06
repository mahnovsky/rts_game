const std = @import("std");
const sr = @import("serializer.zig");

pub const Type = enum {
    Water,
    Groud,
    Grass,
    Stone,
    Wood,
};

pub const Orient = enum(u32) {
    Center = 0,
    Left = 1 << 0,
    Right = 1 << 1,
    Top = 1 << 2,
    Bottom = 1 << 3,
};

pub const TileInfo = struct {
    index: u32,
    type: Type,
    orient: Orient,
};

pub const Tileset = struct {
    const Self = @This();
    const Serializer = sr.Serializer(Tileset).init(sr.CurrentSerializer(Tileset));
    texture: []const u8,
    x_axis_count: u32,
    y_axis_count: u32,
    tile_data: []TileInfo,

    pub fn init(gpa: std.mem.Allocator, x_count: u32, y_count: u32) Self {
        return .{
            .x_axis_count = x_count,
            .y_axis_count = y_count,
            .tile_data = gpa.alloc(TileInfo, x_count * y_count),
        };
    }

    pub fn deinit(self: *const Self, gpa: std.mem.Allocator) void {
        gpa.free(self.tile_data);
        gpa.free(self.texture);
    }

    pub fn load(gpa: std.mem.Allocator, data: []const u8) Self {
        return Serializer.load(gpa, data);
    }

    pub fn save(self: *const Self, gpa: std.mem.Allocator) []u8 {
        return Serializer.save(gpa, self);
    }
};
