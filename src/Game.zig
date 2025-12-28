const std = @import("std");
const Atlas = @import("atlas.zig").Atlas;
const GameMap = @import("game_map.zig").GameMap;
const MapData = @import("game_map.zig").MapData;
const Serializer = @import("game_map.zig").Serializer;
const YamlSerializer = @import("game_map.zig").YamlSerializer;
const zm = @import("zm");
const App = @import("app.zig").App;
const utils = @import("utils.zig");
const editor = @import("editor.zig");
const ecs = @import("ecs.zig");
const ObjectStorage = @import("ObjectStorage.zig");
const Window = @import("Window.zig");

const Game = @This();
var buffer: [1024 * 8]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
const allocator = fba.allocator();
var context: ObjectStorage = .init(allocator);

const CamSpeed: f32 = 200;
const BorderOffset: i32 = 20;
const Rand = struct {
    var prng: std.Random.DefaultPrng = undefined;

    fn get() std.Random {
        return prng.random();
    }
};

fn initRandom() !void {
    Rand.prng = .init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
}

const World = struct {};
const Ecs = ecs.CreateEcs(World);
var game_instance: ?*Game = null;
width: u32,
height: u32,
map: GameMap,
frame_time: f64 = 0,
proj: zm.Mat4f,
camera: zm.Mat4f,
camera_offset: zm.Vec2f,
move_camera: bool,
ecs_inst: Ecs,

pub fn init(gpa: std.mem.Allocator, width: u32, height: u32) !*Game {
    const proj = zm.Mat4f.orthographic(
        0,
        @floatFromInt(width),
        0,
        @floatFromInt(height),
        0,
        100,
    );

    try initRandom();
    const rand = Rand.get();
    const cols = 40;
    const rows = 40;
    const map = try gpa.alloc(u16, cols * rows);
    defer gpa.free(map);
    for (0..rows) |y| {
        for (0..cols) |x| {
            map[x + y * cols] = rand.intRangeAtMost(u16, 16, 255);
        }
    }

    const data = try utils.readFileData(gpa, "./data/maps/test_map.yaml");
    defer gpa.free(data);
    const map_data = try MapData.load(gpa, data, Serializer.init(YamlSerializer));

    std.log.debug("test map: {d}, {d}, {d}", .{ map_data.width, map_data.height, map_data.tile_data.len });
    try context.addResource(Game, .{
        .map = try GameMap.init(
            gpa,
            "./data/GRAPHICS/tilesets/summer/terrain/summer.png",
            map_data,
            proj,
        ),
        .width = width,
        .height = height,
        .proj = proj,
        .camera = zm.Mat4f.identity(),
        .camera_offset = .{ 0, 0 },
        .move_camera = true,
        .ecs_inst = try Ecs.init(gpa),
    });

    return context.getResource(Game).?;
}

pub fn deinit(game: *Game, gpa: std.mem.Allocator) void {
    game.map.deinit(gpa);
    game.ecs_inst.deinit();
}

pub fn postInit(game: *Game, _: std.mem.Allocator) !void {
    const Movable = struct {
        const Self = @This();
        component: ecs.Component,
        pos: f32,

        pub fn init() Self {
            return .{
                .component = ecs.Component.init(Self),
                .pos = 0.3,
            };
        }
        pub fn deinit(self: *Self) void {
            self.pos = 0.0;
        }

        pub fn create(gpa: std.mem.Allocator) *anyopaque {
            const res = gpa.create(Self) catch unreachable;
            res.* = Self.init();
            std.log.info("Movable created {d}", .{res.pos});
            return res;
        }
    };

    const Transform = struct {
        const Self = @This();
        component: ecs.Component,
        pos: f32,

        pub fn init() Self {
            return .{
                .component = ecs.Component.init(Self),
                .pos = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.pos = 0.0;
        }

        pub fn create(gpa: std.mem.Allocator) *anyopaque {
            const res = gpa.create(Self) catch unreachable;
            res.* = Self.init();

            return res;
        }
    };

    const Sprite = struct {
        const Self = @This();
        component: ecs.Component,
        pos: f32,

        pub fn init() Self {
            return .{
                .component = ecs.Component.init(Self),
                .pos = 0,
            };
        }

        pub fn create(gpa: std.mem.Allocator) *anyopaque {
            const res = gpa.create(Self) catch unreachable;
            res.* = Self.init();

            return res;
        }

        pub fn deinit(_: *Self) void {}
    };
    try context.addResource(GameMap, game.map);

    std.debug.print("spawn started\n", .{});
    for (0..20) |_| {
        // const ent = try game.ecs_inst.makeEntity();

        // var tr = try game.ecs_inst.addComponent(Transform, ent);
        // tr.pos = 12;
        // var mv = try game.ecs_inst.addComponent(Movable, ent);
        // mv.pos = 44;

        const object = try game.ecs_inst.spawnOne(&.{ Transform, Movable, Sprite });

        object.components.Transform.pos = 11;
        object.components.Movable.pos = 9;
        object.components.Sprite.pos = 3;
    }

    if (game.ecs_inst.getEntity(12)) |ent_12| {
        std.debug.print("added sprite to ent {d}\n", .{ent_12.index});
        //_ = try game.ecs_inst.addComponent(Sprite, ent_12);
        var tr = try game.ecs_inst.getComponent(Transform, ent_12);
        tr.pos = 8;
        //try game.ecs_inst.removeComponent(Sprite, ent_12);
        //try game.ecs_inst.killEntity(ent_12);
    }

    // const ent = try game.ecs_inst.makeEntity();
    // _ = try game.ecs_inst.addComponent(Transform, ent);
    // _ = try game.ecs_inst.addComponent(Movable, ent);
    // _ = try game.ecs_inst.addComponent(Sprite, ent);

    const ent = try game.ecs_inst.spawnOne(&.{ Movable, Sprite });
    _ = try game.ecs_inst.addComponentByName(ent.entity, "Transform");
    const x = try game.ecs_inst.getComponent(Transform, ent.entity);
    x.pos = 88.88;
    const flags = Ecs.ComponentIndexing.getTypeFlags(&.{ Transform, Movable });
    std.debug.print("Flags comps: {d}, ent {d}\n", .{ flags, x.pos });
    //const components = ecs.getComponentFlag(Transform) | ecs.getComponentFlag(Movable);
    var en_it: ?Ecs.Entities.Iterator = game.ecs_inst.entities.getIterator(&.{ Transform, Movable });
    //const Res = ecs.generateStruct(&.{ Transform, Movable, Sprite });
    while (en_it) |it| {
        if (it.get()) |ent_id| {
            const d = try game.ecs_inst.getComponents(&.{ Transform, Movable, Sprite }, ent_id);
            std.debug.print("ent {d} tr: {d}, mv: {d}, sp: {d}\n", .{ ent_id.index, d.Transform.pos, d.Movable.pos, d.Sprite.pos });
        }
        en_it = it.next();
    }

    // var tr_iter = try game.ecs_inst.getIterator(Transform);
    // var mv_iter = try game.ecs_inst.getIterator(Movable);
    // var i: u32 = 0;
    // while (!mv_iter.isEnd() and !tr_iter.isEnd()) {
    //     const tr = tr_iter.get();
    //     const mv = mv_iter.get();
    //     if (tr != null and mv != null) {
    //         std.debug.print("Movable iteration {d}\n", .{i});
    //         i += 1;

    //         tr.?.pos += mv.?.pos;
    //     }
    //     tr_iter = tr_iter.next();
    //     mv_iter = mv_iter.next();
    // }

    //std.log.debug("transform {d}, movable {d}", .{ tr.component.type_index, mv.component.type_index });
}

fn applyCameraOffset(game: *Game) void {
    game.camera.data[3] = game.camera_offset[0];
    game.camera.data[7] = game.camera_offset[1];
}

pub fn processInput(game: *Game, window: *Window, frame_time: f64) !void {
    const pos = window.getCursorPos();
    if (game.move_camera) {
        if (pos[0] < BorderOffset) {
            game.camera_offset[0] += @floatCast(frame_time * CamSpeed);
        }

        if (pos[0] > (game.width - BorderOffset)) {
            game.camera_offset[0] -= @floatCast(frame_time * CamSpeed);
        }

        if (pos[1] < BorderOffset) {
            game.camera_offset[1] -= @floatCast(frame_time * CamSpeed);
        }

        if (pos[1] > (game.height - BorderOffset)) {
            game.camera_offset[1] += @floatCast(frame_time * CamSpeed);
        }

        game.applyCameraOffset();
    }
}

pub fn update(game: *Game, window: *Window, frame_time: f64) !void {
    game.frame_time = frame_time;

    try game.processInput(window, frame_time);
}

pub fn draw(game: *Game) void {
    //game.map.draw(&game.camera);
    if (context.getResource(GameMap)) |map| {
        map.draw(&game.camera);
    }
}
