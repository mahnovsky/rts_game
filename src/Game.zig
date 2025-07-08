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

app: *App,
map: GameMap,
frame_time: f64 = 0,
proj: zm.Mat4f,
camera: zm.Mat4f,
camera_offset: zm.Vec2f,
move_camera: bool,

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
    for (map_data.tile_data) |index| {
        std.log.debug("test map index: {d}", .{index});
    }

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
    };
}

pub fn deinit(game: *Game, gpa: std.mem.Allocator) void {
    game.map.deinit(gpa);
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
