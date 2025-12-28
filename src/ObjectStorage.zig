const std = @import("std");
const Indexing = @import("type_indexing.zig");
const Allocator = std.mem.Allocator;

const ObjectContainer = struct {
    ptr: *anyopaque,
};

const Self = @This();
pub const ResourceIndexing = Indexing.CreateTypeIndexing(struct {});
allocator: Allocator,
objects: std.ArrayList(ObjectContainer),

pub fn init(allocator: Allocator) Self {
    return .{
        .allocator = allocator,
        .objects = .empty,
    };
}

pub fn deinit(self: Self) void {
    self.objects.deinit(self.allocator);
}

pub fn addResource(self: *Self, comptime T: type, resource: T) !void {
    const res = try self.allocator.create(T);

    res.* = resource;

    const index = ResourceIndexing.initTypeIndex(T, self.allocator);
    if (index >= self.objects.items.len) {
        try self.objects.resize(self.allocator, index + 1);
    }
    self.objects.items[index] = .{ .ptr = res };
}

pub fn getResource(self: *Self, comptime T: type) ?*T {
    const index = ResourceIndexing.initTypeIndex(T, self.allocator);
    if (index < self.objects.items.len) {
        return @ptrCast(@alignCast(self.objects.items[index].ptr));
    }
    return null;
}
