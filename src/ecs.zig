const std = @import("std");
const Allocator = std.mem.Allocator;

const TypeIdData = struct {
    index: u32 = std.math.maxInt(u32),
};

const InnerTypeId = *TypeIdData;
const TypeId = *const TypeIdData;

inline fn innerTypeId(comptime T: type) InnerTypeId {
    return &struct {
        comptime {
            _ = T;
        }
        var id: @typeInfo(InnerTypeId).pointer.child = .{};
    }.id;
}

pub inline fn typeId(comptime T: type) TypeId {
    return innerTypeId(T);
}

pub inline fn typeIndex(comptime T: type) u32 {
    return typeId(T).index;
}

pub fn initTypeIndex(comptime T: type) u32 {
    const gen = struct {
        var counter: u32 = 0;
    };

    const index_ptr = &innerTypeId(T).index;
    if (index_ptr.* < std.math.maxInt(u32)) {
        return index_ptr.*;
    }

    const index = gen.counter;
    gen.counter += 1;
    index_ptr.* = index;

    return index;
}

const EntityImpl = struct {
    index: u32,
    components: u32,
};

pub const Entity = *EntityImpl;

const EcsError = error{
    ComponetNotContains,
};

pub const Component = struct {
    const Self = @This();
    type_index: u32,

    pub fn init(comptime T: type) Self {
        return .{
            .type_index = initTypeIndex(T),
        };
    }
};

fn makeBucket(comptime T: type) type {
    const Bucket = struct {
        const Self = @This();
        const Count = 32;
        const AddResult = struct { ptr: *T, pos: u32 };
        allocator: Allocator,
        alives: u32,
        components: []T,

        fn init(gpa: Allocator) !Self {
            return .{
                .allocator = gpa,
                .alives = 0,
                .components = try gpa.alloc(T, Count),
            };
        }

        fn deinit(self: Self) void {
            self.allocator.free(self.components);
        }

        fn isFull(self: Self) bool {
            return self.alives == std.math.maxInt(u32);
        }

        fn allocOrGet(self: *Self, pos: u32) *T {
            const index = pos % Count;
            const bit: u32 = std.math.pow(u32, 2, index);

            if ((bit & self.alives) != 0) {
                return &self.components[index];
            }

            return self.alloc(pos);
        }

        fn alloc(self: *Self, pos: u32) *T {
            const index = pos % Count;
            const bit: u32 = std.math.pow(u32, 2, index);

            std.debug.assert((bit & self.alives) == 0);
            self.alives |= bit;

            //self.components[index] = T.init();

            return &self.components[index];
        }

        fn allocOne(self: *Self) !AddResult {
            for (0..Count) |index| {
                const bit: u32 = std.math.pow(u32, 2, @intCast(index));
                if ((bit & self.alives) == 0) {
                    return .{ .ptr = self.alloc(@intCast(index)), .pos = @intCast(index) };
                }
            }

            unreachable;
        }

        fn freeByIndex(self: *Self, pos: u32) void {
            const index = pos % Count;
            const bit: u32 = std.math.pow(u32, 2, index);

            self.alives ^= bit;
        }

        fn free(self: *Self, ptr: *T) void {
            const index = ptr.index % Count;
            const bit: u32 = std.math.pow(u32, 2, index);

            self.alives ^= bit;
        }
    };

    return Bucket;
}

fn baseStorage(comptime T: type) type {
    return struct {
        const Self = @This();
        const Bucket = makeBucket(T);
        const Node = struct {
            next: ?*@This() = null,
            bucket: makeBucket(T),
        };

        allocator: Allocator,
        head: *Node,
        tail: ?*Node,

        fn init(allocator: Allocator) !Self {
            const head = try allocator.create(Node);
            head.* = .{
                .bucket = try Bucket.init(allocator),
            };

            return .{
                .allocator = allocator,
                .head = head,
                .tail = head,
            };
        }

        fn deinit(self: Self) void {
            var it: ?*Node = self.head;
            while (it) |node| {
                node.bucket.deinit();
                self.allocator.destroy(node);
                it = node.next;
            }
        }

        fn grow(self: *Self) !*Node {
            if (self.tail) |tail| {
                const next = try self.allocator.create(Node);
                next.* = .{
                    .bucket = try Bucket.init(self.allocator),
                };
                self.tail = next;
                tail.next = next;
                return next;
            }
            unreachable;
        }

        fn getNodeToAdd(self: *Self) !*Node {
            var it: ?*Node = self.head;
            while (it) |node| {
                if (!node.bucket.isFull()) {
                    return node;
                }
                it = node.next;
            }
            return try self.grow();
        }

        fn getNodeByIndex(self: *Self, index: u32) ?*Node {
            var it: ?*Node = &self.head;
            var counter: u32 = 0;
            while (it) |node| {
                it = node.next;
                if (counter == index) {
                    return it;
                }
                counter += 1;
            }
            return null;
        }

        fn addOne(self: *Self) !Bucket.AddResult {
            const node = try self.getNodeToAdd();

            return node.bucket.allocOne();
        }

        fn addInPlace(self: *Self, pos: u32) ?*T {
            const bucket_index = @as(f32, @floatFromInt(pos)) / Bucket.Count;

            if (self.getNodeByIndex(bucket_index)) |node| {
                return node.bucket.alloc(pos);
            }
            return null;
        }
    };
}

const ComponentContainer = struct {
    ptr: *anyopaque,
    destroy_func: *const fn (*anyopaque) void,
};

fn makeContainer(comptime T: type) type {
    const Container = struct {
        const Self = @This();
        const Bucket = makeBucket(T);

        buckets: std.ArrayList(Bucket),
        allocator: Allocator,

        fn create(gpa: Allocator) !*Self {
            const container = try gpa.create(Self);

            container.* = .{
                .buckets = std.ArrayList(Bucket).init(gpa),
                .allocator = gpa,
            };

            return container;
        }

        fn destroy(self: *Self) void {
            for (self.buckets.items) |bucket| {
                bucket.deinit();
            }
            self.buckets.deinit();
            self.allocator.destroy(self);
        }

        fn destroySelf(ptr: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ptr));

            self.destroy();
        }

        fn getComponentContainer(self: *Self) ComponentContainer {
            return .{
                .ptr = self,
                .destroy_func = &destroySelf,
            };
        }

        fn getBucketIndex(entity: Entity) usize {
            const bucket_index: usize = @intFromFloat(std.math.floor(@as(f32, @floatFromInt(entity.index)) / Bucket.Count));

            return bucket_index;
        }

        fn getComponent(self: *Self, entity: Entity) *T {
            const bucket_index = getBucketIndex(entity);
            std.debug.assert(self.buckets.items.len > bucket_index);

            const bucket = self.buckets.items[bucket_index];
            return bucket.allocOrGet(entity.index);
        }

        fn addComponent(self: *Self, entity: Entity) !*T {
            const bucket_index = getBucketIndex(entity);

            if (self.buckets.items.len <= bucket_index) {
                const last = self.buckets.items.len;
                try self.buckets.resize(bucket_index + 1);

                for (last..self.buckets.items.len) |index| {
                    self.buckets.items[index] = try Bucket.init(self.allocator);
                }
            }

            var bucket = self.buckets.items[bucket_index];
            const comp = bucket.allocOrGet(entity.index);
            comp.* = T.init();
            return comp;
        }

        fn removeComponent(self: *Self, entity: Entity) void {
            const bucket_index = getBucketIndex(entity);
            std.debug.assert(self.buckets.items.len > bucket_index);

            self.buckets.items[bucket_index].free(entity.index);
        }
    };

    return Container;
}

const Entities = struct {
    const Self = @This();
    const BaseStorage = baseStorage(EntityImpl);

    storage: BaseStorage,
    allocator: Allocator,
    counter: u32 = 0,

    fn init(gpa: Allocator) !Self {
        return Self{
            .storage = try BaseStorage.init(gpa),
            .allocator = gpa,
        };
    }

    fn deinit(self: Self) void {
        self.storage.deinit();
    }

    fn makeEntity(self: *Self) !Entity {
        const res = try self.storage.addOne();
        res.ptr.* = .{
            .index = res.pos,
            .components = 0,
        };
        return res.ptr;
    }
};

pub const Ecs = struct {
    const Self = @This();

    allocator: Allocator,
    components: std.ArrayList(ComponentContainer),
    entities: Entities,

    pub fn init(gpa: Allocator) !Ecs {
        return .{
            .allocator = gpa,
            .components = std.ArrayList(ComponentContainer).init(gpa),
            .entities = try Entities.init(gpa),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit();
        for (self.components.items) |cont| {
            cont.destroy_func(cont.ptr);
        }

        self.components.deinit();
    }

    pub fn makeEntity(self: *Self) !Entity {
        return self.entities.makeEntity();
    }

    fn getContainer(self: *Self, comptime T: type) !*makeContainer(T) {
        const Container = makeContainer(T);

        _ = initTypeIndex(T);
        const index = typeIndex(T);
        if (self.components.items.len <= index) {
            const container = try Container.create(self.allocator);
            try self.components.append(container.getComponentContainer());
        }

        return @ptrCast(@alignCast(self.components.items[index].ptr));
    }

    pub fn addComponent(self: *Self, comptime T: type, entity: Entity) !*T {
        const container = try self.getContainer(T);

        return container.addComponent(entity);
    }

    pub fn removeComponent(self: Self, comptime T: type, entity: Entity) !void {
        const container = try self.getContainer(T);
        container.removeComponent(entity);
    }

    pub fn getComponent(self: Self, comptime T: type, entity: Entity) !*T {
        const container = try self.getContainer(T);

        return container.getComponent(entity);
    }

    //pub fn getIterator(comptime T: type) Iterator(T) {

    //}
};
