const std = @import("std");
const Atlas = @import("atlas.zig").Atlas;
const Self = @This();

pub const Type = enum {
    Texture,
    Atlas,
    Font,
};

const Content = union(Type) {
    Texture: void,
    Atlas: Atlas,
    Font: void,
};

pub const Handle = struct {
    type: Type,
    name: []const u8,
};
const SIZE = @typeInfo(Type).@"enum".fields.len;
const Container = std.StringHashMap(Content);
assets: [SIZE]Container,

pub fn init(gpa: std.mem.Allocator) Self {
    return .{
        .atlases = .{
            inline for (0..SIZE) |_| {
                try Container.init(gpa);
            },
        },
    };
}

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    for (self.assets) |assets| {
        var it = assets.iterator();
        for (it.next()) |item| {
            switch (item) {
                .Atlas => |atl| {
                    atl.deinit(gpa);
                },
                else => {},
            }
        }
        assets.deinit(gpa);
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
