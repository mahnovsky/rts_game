const std = @import("std");
const OutBucket = @import("Bucket.zig");
const Allocator = std.mem.Allocator;

const TypeIdData = struct {
    index: u32 = std.math.maxInt(u32),
    flag: u32 = 0,
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
    const flag_ptr = &innerTypeId(T).flag;
    flag_ptr.* = std.math.pow(u32, 2, index);

    return index;
}

pub fn getComponentFlag(comptime T: type) u32 {
    return innerTypeId(T).flag;
}

pub fn getComponentFlags(comptime fields: []const type) u32 {
    var flags: [fields.len]u32 = undefined;
    inline for (0..fields.len) |index| {
        const field = fields[index];
        flags[index] = getComponentFlag(field);
    }

    var res: u32 = 0;
    for (flags) |flag| {
        res |= flag;
    }
    return res;
}

pub fn prettyTypeName(comptime ctype: type) [:0]const u8 {
    const name = @typeName(ctype); //std.fmt.comptimePrint("elem_{d}", .{i});
    if (std.mem.lastIndexOf(u8, name, ".")) |index| {
        return name[index + 1 .. :0];
    }
}

pub fn generateStruct(comptime types: []const type) type {
    var fields: [types.len]std.builtin.Type.StructField = undefined;

    inline for (0.., types) |i, ctype| {
        //var iter = std.mem.splitBackwardsScalar(u8, @typeName(ctype), '.');

        const name = prettyTypeName(ctype); //std.fmt.comptimePrint("elem_{d}", .{i});

        fields[i] = .{
            .name = name,
            .type = *ctype,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(ctype),
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}

const EntityImpl = struct {
    content: ?struct {
        index: u32,
        components: u32,
        version: u32,
    },

    pub fn getIndex(self: @This()) EcsError!u32 {
        if (self.content) |c| {
            return @intCast(c.index);
        }
        return error.EntityNotExist;
    }

    pub fn getVersion(self: @This()) EcsError!u32 {
        if (self.content) |c| {
            return @intCast(c.version);
        }
        return error.EntityNotExist;
    }

    pub fn getComponents(self: @This()) EcsError!u32 {
        if (self.content) |c| {
            return c.components;
        }
        return error.EntityNotExist;
    }

    pub fn isAlive(self: @This()) bool {
        return self.content != null;
    }

    pub fn hasComponent(self: @This(), comptime T: type) bool {
        return (self.content.?.components & getComponentFlag(T)) != 0;
    }

    pub fn hasComponents(self: @This(), comptime types: []const type) bool {
        const flags = getComponentFlags(types);
        return (self.content.?.components & flags) == flags;
    }

    fn setComponent(self: *@This(), components: u32) void {
        std.debug.print("set components {d}\n", .{components});
        self.content.?.components = components;
    }

    fn addComponent(self: *@This(), component: u32) void {
        //std.debug.print("add components {d}\n", .{component});
        self.content.?.components |= component;
    }
};

const EcsError = error{
    EntityNotExist,
    ComponentAlreadyAdded,
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

fn baseStorage(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const Bucket = OutBucket.makeBucket(T, std.heap.pageSize() / @sizeOf(T));

        const Iterator = struct {
            const Container = Self;
            const This = @This();
            container: *Container,
            index: usize = 0,
            item_iter: Bucket.Iterator,

            fn next(self: @This()) ?@This() {
                if (self.item_iter.next()) |iter| {
                    return .{
                        .container = self.container,
                        .index = self.index,
                        .item_iter = iter,
                    };
                }

                const buckets = self.container.buckets.items.len;
                const next_index = self.index + 1;
                std.debug.print("next index {d}\n", .{next_index});
                if (next_index >= buckets) {
                    return null;
                }

                return .{
                    .container = self.container,
                    .index = next_index,
                    .item_iter = self.container.buckets.items[next_index].getIterator(),
                };
            }

            fn get(self: @This()) *T {
                return self.item_iter.get();
            }
        };

        allocator: Allocator,
        buckets: std.ArrayList(Bucket),

        pub fn init(allocator: Allocator) !Self {
            var buckets: std.ArrayList(Bucket) = .empty;
            const bucket = try buckets.addOne(allocator);

            bucket.* = try Bucket.init(allocator);
            return .{
                .allocator = allocator,
                .buckets = buckets,
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.buckets.items) |item| {
                item.deinit();
            }
            self.buckets.deinit(self.allocator);
        }

        fn grow(self: *Self, new_len: usize) !void {
            const elements = self.buckets.items.len;
            if (new_len > elements) {
                try self.buckets.resize(self.allocator, new_len);

                for (elements..new_len) |index| {
                    self.buckets.items[index] = try Bucket.init(self.allocator);
                }
            }
        }

        fn growAlloc(self: *Self) ?Bucket.AddResult {
            const new_bucket = self.buckets.addOne(self.allocator) catch {
                return null;
            };
            new_bucket.* = Bucket.init(self.allocator) catch {
                return null;
            };
            return new_bucket.allocOne();
        }

        pub fn addOne(self: *Self) ?Bucket.AddResult {
            const elements = self.buckets.items.len;
            if (elements == 0) {
                return self.growAlloc();
            } else {
                var bucket = &self.buckets.items[elements - 1];
                if (bucket.isFull()) {
                    return self.growAlloc();
                }
                return bucket.allocOne();
            }
            return null;
        }

        pub fn getIterator(self: *Self) Iterator {
            return .{
                .container = self,
                .index = 0,
                .item_iter = self.buckets.items[0].getIterator(),
            };
        }

        pub fn getItem(self: *Self, index: usize) ?*T {
            const bucket: usize = @intFromFloat(std.math.floor(@as(f64, @floatFromInt(index)) / Bucket.Count));
            if (bucket < self.buckets.items.len) {
                const inside_index = index % Bucket.Count;
                return &self.buckets.items[bucket].elements[inside_index];
            }
            return null;
        }

        pub fn allocInplace(self: *Self, index: usize) ?*T {
            const bucket: usize = @intFromFloat(std.math.floor(@as(f64, @floatFromInt(index)) / Bucket.Count));
            const current_len = self.buckets.items.len;
            if (bucket > current_len) {
                const new_len = bucket + 1;
                self.grow(new_len) catch {
                    return null;
                };
            }
            const inside_index = index % Bucket.Count;
            return &self.buckets.items[bucket].elements[inside_index];
        }
    };
}

const ComponentContainer = struct {
    ptr: *anyopaque,
    destroy_func: *const fn (*anyopaque) void,
};

fn makeContainer(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const Storage = baseStorage(T);
        pub const Iterator = Storage.Iterator;
        allocator: Allocator,
        storage: Storage,

        fn getIterator(self: *Self) Iterator {
            return self.getIterator();
        }

        fn create(gpa: Allocator) !*Self {
            const container = try gpa.create(Self);

            container.* = .{
                .allocator = gpa,
                .storage = try Storage.init(gpa),
            };

            return container;
        }

        fn destroy(self: *Self) void {
            self.storage.deinit();
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

        fn getComponent(self: *Self, entity: EntityId) EcsError!*T {
            if (self.storage.getItem(entity.index)) |comp| {
                return comp;
            }
            return error.ComponetNotContains;
        }

        fn addComponent(self: *Self, entity: EntityId) !*T {
            const opt_comp = self.storage.getItem(entity.index) orelse self.storage.allocInplace(entity.index);

            if (opt_comp) |comp| {
                comp.* = T.init();
                // entity.addComponent(getComponentFlag(T));
                return comp;
            }

            unreachable;
        }
    };
}

pub const EntityId = struct {
    index: u32,
    version: u32,
};

pub const EntityInfo = struct {
    components: u32,
    version: u32,
};

const EntityCell = union(enum) {
    Alive: EntityInfo,
    Dead: void,
};

pub const Entities = struct {
    const Self = @This();
    entities: std.ArrayList(EntityCell),
    free_entities: std.ArrayList(EntityId),
    allocator: Allocator,

    pub const Iterator = struct {
        container: *Self,
        index: usize,

        pub fn next(self: @This()) ?@This() {
            const len = self.container.entities.items.len;
            if ((self.index + 1) < len) {
                return .{
                    .container = self.container,
                    .index = self.index + 1,
                };
            }

            return null;
        }

        pub fn get(self: @This()) ?EntityId {
            const cell = self.container.entities.items[self.index];

            switch (cell) {
                .Alive => |a| return .{ .index = @intCast(self.index), .version = a.version },
                .Dead => std.debug.print("Iterator.get empty element\n", .{}),
            }

            return null;
        }
    };

    fn init(gpa: Allocator) Self {
        return Self{
            .entities = .empty,
            .free_entities = .empty,
            .allocator = gpa,
        };
    }

    fn deinit(self: *Self) void {
        self.entities.deinit(self.allocator);
        self.free_entities.deinit(self.allocator);
    }

    fn makeEntity(self: *Self) !EntityId {
        if (self.free_entities.pop()) |info| {
            const newVersion = info.version + 1;
            self.entities.items[info.index] = .{ .Alive = .{ .version = newVersion, .components = 0 } };

            return .{ .index = info.index, .version = newVersion };
        }

        const index: u32 = @intCast(self.entities.items.len);
        const cell = try self.entities.addOne(self.allocator);
        cell.* = .{ .Alive = .{ .version = 0, .components = 0 } };
        return .{ .index = index, .version = 0 };
    }

    fn killEntity(self: *Self, entity: EntityId) !void {
        if (entity.index < self.entities.items.len) {
            const info = self.entities.items[entity.index];
            switch (info) {
                .Alive => |_| std.debug.print("killEntity {d}\n", .{entity.index}),
                .Dead => return error.EntityNotExist,
            }
            self.entities.items[entity.index] = .Dead;
        }
        self.free_entities.append(self.allocator, .{ .index = entity.index, .version = entity.version }) catch {
            unreachable;
        };
    }

    fn getEntity(self: Self, index: u32) ?EntityId {
        if (index < self.entities.items.len) {
            const info = self.entities.items[index];
            switch (info) {
                .Alive => |a| return .{ .index = index, .version = a.version },
                .Dead => return null,
            }
        }
        return null;
    }

    pub fn getIterator(self: *Self) Iterator {
        return .{
            .container = self,
            .index = 0,
        };
    }

    pub fn getComponentsFlag(self: Self, entity: EntityId) !u32 {
        if (self.isEntityExist(entity)) {
            const info = self.entities.items[entity.index];
            switch (info) {
                .Alive => |a| return a.components,
                .Dead => unreachable,
            }
        }
        return error.EntityNotExist;
    }

    pub fn setComponentsFlag(self: *Self, entity: EntityId, flag: u32) !void {
        if (self.isEntityExist(entity)) {
            const info = self.entities.items[entity.index];
            switch (info) {
                .Alive => |a| {
                    self.entities.items[entity.index] = .{ .Alive = .{ .version = a.version, .components = flag } };
                },
                .Dead => unreachable,
            }
        } else {
            return error.EntityNotExist;
        }
    }

    pub fn addComponentsFlag(self: *Self, entity: EntityId, flag: u32) !void {
        if (self.isEntityExist(entity)) {
            const info = self.entities.items[entity.index];
            switch (info) {
                .Alive => |a| {
                    self.entities.items[entity.index] = .{ .Alive = .{ .version = a.version, .components = a.components | flag } };
                },
                .Dead => unreachable,
            }
        } else {
            return error.EntityNotExist;
        }
    }

    pub fn isEntityExist(self: Self, entity: EntityId) bool {
        if (self.getEntity(entity.index)) |ent| {
            std.debug.print("isEntityExist index: {d}, version: {d} == ", .{ entity.index, entity.version });
            std.debug.print("isEntityExist index: {d}, version: {d}\n", .{ ent.index, ent.version });
            return ent.version == entity.version;
        }

        return false;
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
            .components = .empty,
            .entities = Entities.init(gpa),
        };
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit();
        for (self.components.items) |cont| {
            cont.destroy_func(cont.ptr);
        }

        self.components.deinit(self.allocator);
    }

    pub fn makeEntity(self: *Self) !EntityId {
        return self.entities.makeEntity();
    }

    pub fn killEntity(self: *Self, entity: EntityId) !void {
        try self.entities.killEntity(entity);
    }

    pub fn getEntity(self: Self, index: u32) ?EntityId {
        return self.entities.getEntity(index);
    }

    pub fn isEntityExist(self: Self, entity: EntityId) bool {
        return self.entities.isEntityExist(entity);
    }

    pub fn getComponentsFlag(self: Self, entity: EntityId) !u32 {
        return self.entities.getComponentsFlag(entity);
    }

    fn getContainer(self: *Self, comptime T: type) ?*makeContainer(T) {
        const index = typeIndex(T);
        std.debug.assert(self.components.items.len > index);

        return @ptrCast(@alignCast(self.components.items[index].ptr));
    }

    fn grow(self: *Self, comptime T: type) !void {
        const Container = makeContainer(T);

        const index = initTypeIndex(T);
        if (self.components.items.len <= index) {
            const container = try Container.create(self.allocator);
            try self.components.append(self.allocator, container.getComponentContainer());
        }
    }

    pub fn addComponent(self: *Self, comptime T: type, entity: EntityId) !*T {
        if (self.isEntityExist(entity)) {
            try self.grow(T);
            if (self.getContainer(T)) |container| {
                try self.entities.addComponentsFlag(entity, getComponentFlag(T));
                return try container.addComponent(entity);
            }
        }

        return error.EntityNotExist;
    }

    pub fn removeComponent(self: *Self, comptime T: type, entity: EntityId) EcsError!void {
        if (self.isEntityExist(entity)) {
            const component_flag = getComponentFlag(T);

            var comps = try self.getComponentsFlag(entity);
            std.debug.print("removeComponent comps: {d}, component_flag: {d}\n", .{ comps, component_flag });
            comps ^= component_flag;
            try self.entities.setComponentsFlag(entity, comps);

            const container = self.getContainer(T);
            const comp = try container.?.getComponent(entity);
            comp.*.deinit();
        } else {
            return error.EntityNotExist;
        }
    }

    pub fn getComponent(self: *Self, comptime T: type, entity: EntityId) EcsError!*T {
        if (!self.isEntityExist(entity)) {
            return error.EntityNotExist;
        }
        if (self.getContainer(T)) |container| {
            return try container.getComponent(entity);
        }
        return error.ComponetNotContains;
    }

    pub fn getComponents(self: *Self, comptime Args: []const type, entity: EntityId) EcsError!generateStruct(Args) {
        if (!self.isEntityExist(entity)) {
            return error.EntityNotExist;
        }

        const S = generateStruct(Args);
        const fields = std.meta.fields(S);
        var res: S = undefined;
        inline for (fields) |field| {
            const child_type = switch (@typeInfo(field.type)) {
                .pointer => |info| info.child,
                else => @compileError("Expected a pointer type"),
            };
            if (self.getContainer(child_type)) |container| {
                //std.fmt.comptimePrint("elem_{d}", .{i})
                @field(&res, prettyTypeName(child_type)) = try container.getComponent(entity);
            }
        }
        return res;
    }
};
