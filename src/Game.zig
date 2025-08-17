const std = @import("std");
const Atlas = @import("atlas.zig").Atlas;
const GameMap = @import("game_map.zig").GameMap;
const MapData = @import("game_map.zig").MapData;
const Serializer = @import("game_map.zig").Serializer;
const YamlSerializer = @import("game_map.zig").YamlSerializer;
const zm = @import("zm");
const App = @import("app.zig").App;
const Window = @import("Window.zig");
const utils = @import("utils.zig");
const editor = @import("editor.zig");
const ecs = @import("ecs.zig");

const Game = @This();
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
var game_instance: ?*Game = null;
app: *App,
map: GameMap,
frame_time: f64 = 0,
proj: zm.Mat4f,
camera: zm.Mat4f,
camera_offset: zm.Vec2f,
move_camera: bool,
ecs_inst: ecs.Ecs,

pub fn init(gpa: std.mem.Allocator, app: *App) !Game {
    const proj = zm.Mat4f.orthographic(
        0,
        @floatFromInt(app.width),
        0,
        @floatFromInt(app.height),
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
    //for (map_data.tile_data) |index| {
    //std.log.debug("test map index: {d}", .{index});
    //}

    return .{
        .map = try GameMap.init(
            gpa,
            "./data/GRAPHICS/tilesets/summer/terrain/summer.png",
            map_data,
            proj,
        ),
        .app = app,
        .proj = proj,
        .camera = zm.Mat4f.identity(),
        .camera_offset = .{ 0, 0 },
        .move_camera = true,
        .ecs_inst = try ecs.Ecs.init(gpa),
    };
}

pub fn deinit(game: *Game, gpa: std.mem.Allocator) void {
    game.map.deinit(gpa);
    game.ecs_inst.deinit();
}

pub fn postInit(game: *Game) !void {
    const Movable = struct {
        const Self = @This();
        component: ecs.Component,
        pos: f32,

        pub fn init() Self {
            return .{
                .component = ecs.Component.init(Self),
                .pos = 0,
            };
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
    };

    for (0..20) |_| {
        const ent = try game.ecs_inst.makeEntity();

        _ = try game.ecs_inst.addComponent(Transform, ent);
        _ = try game.ecs_inst.addComponent(Movable, ent);
    }
    var tr_iter = try game.ecs_inst.getIterator(Transform);
    var mv_iter = try game.ecs_inst.getIterator(Movable);
    var i: u32 = 0;
    while (!mv_iter.isEnd() and !tr_iter.isEnd()) {
        const tr = tr_iter.get();
        const mv = mv_iter.get();
        if (tr != null and mv != null) {
            std.debug.print("Movable iteration {d}\n", .{i});
            i += 1;

            tr.?.pos += mv.?.pos;
        }
        tr_iter = tr_iter.next();
        mv_iter = mv_iter.next();
    }

    //std.log.debug("transform {d}, movable {d}", .{ tr.component.type_index, mv.component.type_index });
}

fn applyCameraOffset(game: *Game) void {
    game.camera.data[3] = game.camera_offset[0];
    game.camera.data[7] = game.camera_offset[1];
}

pub fn processInput(game: *Game, frame_time: f64) !void {
    const pos = game.app.window.getCursorPos();
    if (game.move_camera) {
        if (pos[0] < BorderOffset) {
            game.camera_offset[0] += @floatCast(frame_time * CamSpeed);
        }

        if (pos[0] > (game.app.width - BorderOffset)) {
            game.camera_offset[0] -= @floatCast(frame_time * CamSpeed);
        }

        if (pos[1] < BorderOffset) {
            game.camera_offset[1] -= @floatCast(frame_time * CamSpeed);
        }

        if (pos[1] > (game.app.height - BorderOffset)) {
            game.camera_offset[1] += @floatCast(frame_time * CamSpeed);
        }

        game.applyCameraOffset();
    }
}

pub fn update(game: *Game, frame_time: f64) !void {
    game.frame_time = frame_time;

    try game.processInput(frame_time);
}

pub fn draw(game: *Game) void {
    game.map.draw(&game.camera);
}
