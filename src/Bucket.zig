const Bucket = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn makeBucket(comptime T: type, comptime Elements: comptime_int) type {
    return struct {
        const Self = @This();
        pub const Count = Elements;
        pub const AddResult = struct { ptr: *T, pos: u32 };
        pub const GetItemError = error{
            OutOfBounds,
        };

        pub const Iterator = struct {
            const Container = Self;
            container: *Container,
            index: usize,

            pub fn next(self: @This()) ?@This() {
                const nextIndex = self.index + 1;
                std.debug.print("next index {d}\n", .{nextIndex});
                if (nextIndex >= self.container.end) {
                    return null;
                }
                return .{
                    .container = self.container,
                    .index = nextIndex,
                };
            }

            pub fn get(self: @This()) *T {
                return &self.container.elements[self.index];
            }
        };

        allocator: Allocator,
        end: usize,
        elements: []T,

        pub fn init(gpa: Allocator) !Self {
            return .{
                .allocator = gpa,
                .end = 0,
                .elements = try gpa.alloc(T, Count),
            };
        }

        pub fn deinit(self: Self) void {
            self.allocator.free(self.elements);
        }

        pub fn getIterator(self: *Self) Iterator {
            return .{
                .container = self,
                .index = 0,
            };
        }

        pub fn get(self: Self, index: usize) ?*T {
            std.debug.print("get from bucket {}\n", .{index});
            if (index >= self.end) {
                return null;
            }

            return &self.elements[index];
        }

        pub fn isFull(self: Self) bool {
            return self.end == Count;
        }

        pub fn allocOrGet(self: *Self, index: usize) *T {
            if (index < self.end) {
                return &self.elements[index];
            }
            return self.alloc(index);
        }

        pub fn alloc(self: *Self, index: usize) *T {
            const end = index + 1;

            self.end = end;
            return &self.elements[index];
        }

        pub fn allocOne(self: *Self) ?AddResult {
            const index = self.end;
            //std.debug.print("89: addOne {}", .{index});
            if (index >= self.elements.len) {
                return null;
            }
            const elem = self.alloc(self.end);
            return .{
                .ptr = elem,
                .pos = @intCast(index),
            };
        }
    };
}
