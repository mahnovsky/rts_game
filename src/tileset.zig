const std = @import("std");
const sr = @import("serializer.zig");
const imgui = @import("imgui.zig");
const app = @import("app.zig");
const Assets = @import("Assets.zig");
const Atlas = @import("atlas.zig").Atlas;

pub const Group = enum {
    Dirt,
    Grass,
    Trees,
    Water,
};

pub const CollisionLayer = enum {
    NoCollision,
    Water,
    Ground,
};

pub const Orient = enum(u32) {
    Center = 0,
    Top,
    TopRight,
    Right,
    BottomRight,
    Bottom,
    BottomLeft,
    Left,
    TopLeft,
};

pub const TileInfo = struct {
    group: Group,
    layer: CollisionLayer,
    orient: Orient,
    frames: []u16,
};

pub fn textureAssetListInfo(gpa: std.mem.Allocator) [][:0]const u8 {
    const assets = app.context.getResourceUnchecked(Assets);

    return assets.getAssetListZ(Atlas, gpa) orelse
        @panic("Cant reach this");
}

pub const Tileset = struct {
    const Self = @This();
    const Serializer = sr.CurrentSerializer(Tileset);
    const TAGS = .{
        .texture = .{
            .show_mode = imgui.StringShowMode.ComboSelection,
            .selection_item_provider = &textureAssetListInfo,
        },
    };
    texture: []const u8,
    x_axis_count: u32,
    y_axis_count: u32,
    tiles: []TileInfo,

    pub fn init(gpa: std.mem.Allocator, x_count: u32, y_count: u32) !Self {
        const tiles = try gpa.alloc(TileInfo, x_count * y_count);
        for (tiles, 0..) |*tile, index| {
            tile.index = @intCast(index);
        }
        return .{
            .texture = "",
            .x_axis_count = x_count,
            .y_axis_count = y_count,
            .tiles = &.{},
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
