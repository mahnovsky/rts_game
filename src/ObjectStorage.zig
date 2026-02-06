const std = @import("std");
const Indexing = @import("type_indexing.zig");
const Allocator = std.mem.Allocator;
const DestroyFn = *const fn (Allocator, *anyopaque) void;

const ObjectContainer = struct {
    ptr: *anyopaque,
    destroy_fn: DestroyFn,
};

pub fn Storage(comptime Space: type) type {
    return struct {
        const Self = @This();
        pub const ResourceIndexing = Indexing.CreateTypeIndexing(Space);
        allocator: Allocator,
        objects: std.ArrayList(ObjectContainer),

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .objects = .empty,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.objects.items) |obj| {
                std.debug.print("Destroy address: {*}\n", .{obj.ptr});
                obj.destroy_fn(self.allocator, obj.ptr);
            }
            self.objects.deinit(self.allocator);
            ResourceIndexing.deinit(self.allocator);
        }

        fn createDestroyFn(comptime T: type) DestroyFn {
            return struct {
                fn destroy(gpa: std.mem.Allocator, ptr: *anyopaque) void {
                    const s: *T = @ptrCast(@alignCast(ptr));
                    gpa.destroy(s);
                }
            }.destroy;
        }

        pub fn allocResource(self: *Self, comptime T: type) !*T {
            const res = try self.allocator.create(T);
            const index = ResourceIndexing.initTypeIndex(T, self.allocator);
            if (index >= self.objects.items.len) {
                try self.objects.resize(self.allocator, index + 1);
            }
            self.objects.items[index] = .{ .ptr = res, .destroy_fn = createDestroyFn(T) };

            return res;
        }

        pub fn addResource(self: *Self, comptime T: type, resource: T) !void {
            const res = try self.allocator.create(T);
            res.* = resource;

            const index = ResourceIndexing.initTypeIndex(T, self.allocator);
            if (index >= self.objects.items.len) {
                try self.objects.resize(self.allocator, index + 1);
            }
            self.objects.items[index] = .{ .ptr = res, .destroy_fn = createDestroyFn(T) };
        }

        pub fn addResourceInplace(self: *Self, comptime T: type, gpa: Allocator, args: anytype) !*T {
            const res = try self.allocator.create(T);
            try T.initInplace(gpa, res, args);
            const index = ResourceIndexing.initTypeIndex(T, self.allocator);
            if (index >= self.objects.items.len) {
                try self.objects.resize(self.allocator, index + 1);
            }
            self.objects.items[index] = .{ .ptr = res, .destroy_fn = createDestroyFn(T) };
            return res;
        }

        pub fn getResource(self: *const Self, comptime T: type) ?*T {
            const index = ResourceIndexing.initTypeIndex(T, self.allocator);
            if (index < self.objects.items.len) {
                return self.getResourceUnchecked(T);
            }
            return null;
        }

        pub fn getResourceUnchecked(self: *const Self, comptime T: type) *T {
            const index = ResourceIndexing.initTypeIndex(T, self.allocator);
            std.debug.assert(index < self.objects.items.len);
            return @ptrCast(@alignCast(self.objects.items[index].ptr));
        }
    };
}
