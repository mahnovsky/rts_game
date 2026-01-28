const std = @import("std");
const app = @import("app.zig");
const utils = @import("utils.zig");
const Atlas = @import("atlas.zig").Atlas;
const sr = @import("serializer.zig");
const opengl = @import("opengl.zig");
const zigimg = @import("zigimg");
const Image = zigimg.Image;
const DataPath = app.DataPath;
const Self = @This();

pub const Type = enum {
    Texture,
    Atlas,
    Font,
};

const Content = union(Type) {
    Texture: opengl.Texture,
    Atlas: Atlas,
    Font: void,

    fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        switch (self.*) {
            .Atlas => |*atl| {
                atl.deinit(gpa);
            },
            .Texture => |*texture| {
                texture.deinit();
            },
            else => {},
        }
    }
};

pub const Handle = struct {
    type: Type,
    name: []const u8,
};
const TextureDesc = struct {
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
    textures: []TextureDesc,
    atlases: []AtlasDesc,

    fn parse(gpa: std.mem.Allocator, data: []const u8) Lib {
        return sr.Serializer(Lib).init(sr.YamlSerializer(Lib)).load(gpa, data);
    }
};

const SIZE = @typeInfo(Type).@"enum".fields.len;
const Container = std.StringHashMap(Content);
assets: [SIZE]Container = undefined,

pub fn initInplace(gpa: std.mem.Allocator, self: *Self, _: anytype) !void {
    self.* = .{ .assets = blk: {
        var temp: [SIZE]Container = undefined;

        inline for (0..SIZE) |i| {
            temp[i] = Container.init(gpa);
        }

        break :blk temp;
    } };
}

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    for (&self.assets) |*assets| {
        var it = assets.iterator();
        while (it.next()) |item| {
            item.value_ptr.deinit(gpa);
        }
        assets.deinit();
    }
}

pub fn load(self: *Self, gpa: std.mem.Allocator) !void {
    const data_path = app.context.getResourceUnchecked(DataPath);
    const full_path = try data_path.getFullPath(gpa, "AssetsLib.yaml");
    defer gpa.free(full_path);
    const data = try utils.readFileData(gpa, full_path);
    std.debug.print("Parse data: {s}, path: {s}\n", .{ data, full_path });
    const lib = Lib.parse(gpa, data);
    std.debug.print("Assets loaded {s}, {s}\n", .{ lib.atlases[0].texture, lib.atlases[1].texture });
    try self.loadTextures(gpa, &lib);
    try self.loadAtlases(gpa, &lib);
}

fn loadTextures(self: *Self, gpa: std.mem.Allocator, lib: *const Lib) !void {
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
        try self.assets[@intFromEnum(Type.Texture)].put(info.uid, .{ .Texture = texture });

        std.debug.print("texture loaded {s}\n", .{info.uid});
    }
}

fn loadAtlases(self: *Self, gpa: std.mem.Allocator, lib: *const Lib) !void {
    for (lib.atlases) |info| {
        if (self.assets[@intFromEnum(Type.Texture)].get(info.texture)) |texture| {
            const atl = try Atlas.initGreedFromTexture(gpa, texture.Texture, info.greed_width, info.greed_height);
            try self.assets[@intFromEnum(Type.Atlas)].put(info.uid, .{ .Atlas = atl });
        } else {
            std.log.err("failed to load atlas {s} \n", .{info.texture});
        }
    }
}

pub fn getAssetList(self: *const Self, gpa: std.mem.Allocator, asset_type: Type) ?[]Handle {
    var iter = self.assets[@intFromEnum(asset_type)].iterator();
    const res: std.ArrayList(Handle) = .empty;
    while (iter.next()) |entry| {
        res.append(gpa, .{
            .name = entry.key_ptr,
            .type = asset_type,
        });
    }

    return res.toOwnedSlice(gpa);
}
