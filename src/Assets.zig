const std = @import("std");
const app = @import("app.zig");
const utils = @import("utils.zig");
const Atlas = @import("atlas.zig").Atlas;
const sr = @import("serializer.zig");
const opengl = @import("opengl.zig");
const zigimg = @import("zigimg");
const map = @import("game_map.zig");
const ObjectStorage = @import("ObjectStorage.zig");
const Image = zigimg.Image;
const DataPath = app.DataPath;
const Self = @This();

pub const Error = error{
    AssetNotExist,
    AssetAlreadyExist,
    NoSuchAssetType,
};

pub const Type = enum {
    Texture,
    Atlas,
    Font,
    MapData,
};

pub const Content = union(Type) {
    Texture: opengl.Texture,
    Atlas: Atlas,
    Font: void,
    MapData: map.MapData,

    fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        switch (self.*) {
            .Atlas => |*atl| {
                atl.deinit(gpa);
            },
            .Texture => |*texture| {
                std.debug.print("Texture deinit asset \n", .{});
                texture.deinit();
            },
            .MapData => |*map_data| {
                std.debug.print("MapData deinit asset \n", .{});
                map_data.deinit(gpa);
            },
            else => {},
        }
    }
};

const FileAssetDesc = struct {
    uid: []const u8,
    path: []const u8,
    file: []const u8,
};

const AtlasDesc = struct {
    uid: []const u8,
    texture: []const u8,
    greed_width: u16,
    greed_height: u16,
};

const Lib = struct {
    textures: []FileAssetDesc,
    maps: []FileAssetDesc,
    atlases: []AtlasDesc,

    fn parse(gpa: std.mem.Allocator, data: []const u8) Lib {
        return sr.Serializer(Lib).init(sr.YamlSerializer(Lib)).load(gpa, data);
    }

    fn deinitFileAssets(gpa: std.mem.Allocator, slice: []FileAssetDesc) void {
        for (slice) |info| {
            gpa.free(info.uid);
            gpa.free(info.path);
            gpa.free(info.file);
        }
        gpa.free(slice);
    }

    fn deinit(self: *const @This(), gpa: std.mem.Allocator) void {
        deinitFileAssets(gpa, self.textures);
        deinitFileAssets(gpa, self.maps);
        for (self.atlases) |info| {
            std.debug.print("Deinit Lib {s}\n", .{info.uid});
            gpa.free(info.uid);
            gpa.free(info.texture);
        }
        gpa.free(self.atlases);
    }
};

const SIZE = @typeInfo(Type).@"enum".fields.len;
const Container = std.StringHashMap;
var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
key_allocator: std.mem.Allocator,
objects: ObjectStorage.Storage(struct {}),

pub fn initInplace(gpa: std.mem.Allocator, self: *Self, _: anytype) !void {
    self.* = .{
        .key_allocator = arena.allocator(),
        .objects = .init(gpa),
    };
}

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    const content_info = @typeInfo(Content);
    inline for (content_info.@"union".fields, 0..) |tag, i| {
        const T = @FieldType(Content, tag.name);
        if (self.objects.getResource(Container(T))) |assets| {
            var it = assets.iterator();
            const t: Type = @enumFromInt(i);
            std.debug.print("deinit asset {d} {s}\n", .{ assets.count(), @tagName(t) });
            while (it.next()) |item| {
                var content = @unionInit(Content, tag.name, item.value_ptr.*);
                content.deinit(gpa);
            }
            assets.deinit();
        }
    }
    self.objects.deinit();
    arena.deinit();
}

fn putAsset(self: *Self, comptime T: type, uid: []const u8, content: T) !void {
    var asset_cont = self.objects.getResourceUnchecked(Container(T));
    if (asset_cont.contains(uid)) {
        return error.AssetAlreadyExist;
    }
    try asset_cont.put(try self.key_allocator.dupe(u8, uid), content);
}

pub fn load(self: *Self, gpa: std.mem.Allocator) !void {
    const data_path = app.context.getResourceUnchecked(DataPath);
    const full_path = try data_path.getFullPath(gpa, "AssetsLib.yaml");
    defer gpa.free(full_path);
    const data = try utils.readFileData(gpa, full_path);
    defer gpa.free(data);
    std.debug.print("Parse data: {s}, path: {s}\n", .{ data, full_path });
    const lib = Lib.parse(gpa, data);
    defer lib.deinit(gpa);
    std.debug.print("Assets loaded {s}, {s}\n", .{ lib.atlases[0].texture, lib.atlases[1].texture });

    try self.loadTextures(gpa, &lib);
    try self.loadAtlases(gpa, &lib);
    try self.loadMaps(gpa, &lib);
}

fn addAsssetContainer(self: *Self, comptime T: type, gpa: std.mem.Allocator) !void {
    const container = try self.objects.allocResource(Container(T));
    container.* = .init(gpa);
}

fn loadTextures(self: *Self, gpa: std.mem.Allocator, lib: *const Lib) !void {
    try self.addAsssetContainer(opengl.Texture, gpa);
    const data_path = app.context.getResourceUnchecked(DataPath);
    var read_buffer: [zigimg.io.DEFAULT_BUFFER_SIZE]u8 = undefined;
    for (lib.textures) |info| {
        const full_img_path = try std.fs.path.join(gpa, &.{ data_path.path, info.path, info.file });
        defer gpa.free(full_img_path);
        var image = try Image.fromFilePath(gpa, full_img_path, read_buffer[0..]);
        defer image.deinit(gpa);

        const width: i32 = @intCast(image.width);
        const height: i32 = @intCast(image.height);

        if (image.pixelFormat().isIndexed()) {
            try image.convert(gpa, .rgba32);
        }
        const components = image.pixelFormat().channelCount();
        const texture = opengl.Texture.init(image.rawBytes(), width, height, components);
        try self.putAsset(opengl.Texture, info.uid, texture);
        std.debug.print("texture loaded {s}\n", .{info.uid});
    }
}

fn loadAtlases(self: *Self, gpa: std.mem.Allocator, lib: *const Lib) !void {
    try self.addAsssetContainer(Atlas, gpa);
    for (lib.atlases) |info| {
        const texture = try self.getAsset(opengl.Texture, info.texture);
        const atl = try Atlas.initGreedFromTexture(gpa, texture, info.greed_width, info.greed_height);
        std.debug.print("asset load atlas {s}\n", .{info.uid});
        try self.putAsset(Atlas, info.uid, atl);
    }
}

fn loadMaps(self: *Self, gpa: std.mem.Allocator, lib: *const Lib) !void {
    try self.addAsssetContainer(map.MapData, gpa);
    const data_path = app.context.getResourceUnchecked(DataPath);
    for (lib.maps) |info| {
        const full_path = try std.fs.path.join(gpa, &.{ data_path.path, info.path, info.file });
        defer gpa.free(full_path);
        const data = try utils.readFileData(gpa, full_path);
        defer gpa.free(data);
        const map_data = try map.MapData.load(gpa, data);
        try self.putAsset(map.MapData, info.uid, map_data);
    }
}

pub fn getAssetListZ(self: *const Self, comptime T: type, gpa: std.mem.Allocator) ?[][:0]const u8 {
    var container = self.objects.getResourceUnchecked(Container(T));
    var iter = container.iterator();
    var res: std.ArrayList([:0]const u8) = .empty;
    while (iter.next()) |entry| {
        res.append(
            gpa,
            gpa.dupeZ(u8, entry.key_ptr.*) catch return null,
        ) catch @panic("test");
    }

    const slice = res.toOwnedSlice(gpa) catch null;
    return slice;
}

pub fn getAsset(self: *const Self, comptime T: type, uid: []const u8) !T {
    if (self.objects.getResource(Container(T))) |container| {
        return container.get(uid) orelse error.AssetNotExist;
    }
    return error.NoSuchAssetType;
}
