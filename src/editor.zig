const std = @import("std");
const atlas = @import("atlas.zig");
const texture_view = @import("texture_view.zig");
const GameMap = @import("game_map.zig").GameMap;
const app = @import("app.zig");
const Game = @import("Game.zig");
const Window = @import("Window.zig");
const utils = @import("utils.zig");
const Serializer = @import("game_map.zig").Serializer;
const YamlSerializer = @import("game_map.zig").YamlSerializer;
const glfw = @cImport({
    @cInclude("glfw/glfw3.h");
});

pub const Command = union(enum) {
    const Self = @This();
    OpenTextureView: struct { atl: atlas.Atlas, orig: ?*glfw.GLFWwindow },
    PickTextureIndex: u32,
    ClickOnMap: @Vector(2, u32),
    SaveCurrentMap: void,

    fn is(self: Self, tag: std.meta.Tag(Self)) bool {
        return self == tag;
    }
};

pub const Editor = struct {
    const Self = @This();
    gpa: std.mem.Allocator,
    command_queue: std.ArrayList(Command),
    texture_view_window: ?texture_view.TextureViewWindow,
    tile_index: u16 = 0,

    pub fn init(gpa: std.mem.Allocator) Self {
        return .{
            .gpa = gpa,
            .command_queue = .init(gpa),
            .texture_view_window = null,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.texture_view_window != null) {
            self.texture_view_window.?.close();
        }
        self.command_queue.deinit();
    }

    pub fn pushCommand(self: *Self, command: Command) !void {
        std.log.debug("push command {s}", .{@tagName(command)});
        try self.command_queue.append(command);
    }

    pub fn showTextureViewWindow(self: *Self, atl: atlas.Atlas, orig: ?*glfw.GLFWwindow) !void {
        if (self.texture_view_window == null) {
            std.log.debug("texture_view_window", .{});
            self.texture_view_window = try texture_view.TextureViewWindow.init(self.gpa, &atl, orig, self);
        }
    }

    pub fn processInput(self: *Self, application: *app.App, game: *Game) !void {
        const pos = application.window.getCursorPos();

        if (application.window.isMouseButtonPressed(.Left)) {
            const mouse_y = @as(i32, @intCast(application.height)) - pos[1];
            const pos_x = @floor(@as(f32, @floatFromInt(pos[0])) - game.camera_offset[0]);
            const pos_y = @floor(@as(f32, @floatFromInt(mouse_y)) - game.camera_offset[1]);
            if (game.map.convertScreen2TileCoords(pos_x, pos_y)) |tile_coords| {
                if (self.command_queue.getLastOrNull()) |last| {
                    if (last != .ClickOnMap) {
                        try self.pushCommand(.{ .ClickOnMap = tile_coords });
                    }
                } else {
                    try self.pushCommand(.{ .ClickOnMap = tile_coords });
                }
            }
        }

        if (application.window.getLastMouseEvent()) |event| {
            if (event.state == .Press and event.btn == .Left) {
                if (pos[0] < 100 and pos[1] < 100) {
                    try self.pushCommand(.{ .OpenTextureView = .{
                        .atl = game.map.render_data.atlas,
                        .orig = game.app.window.window,
                    } });
                }
                if (pos[0] > 100 and pos[0] < 200 and pos[1] < 100) {
                    try self.pushCommand(.SaveCurrentMap);
                }
            }
        }
    }

    pub fn processCommands(self: *Self, application: *app.App, game: *Game) !void {
        if (self.command_queue.items.len > 0) {
            for (self.command_queue.items) |cmd| {
                switch (cmd) {
                    .OpenTextureView => |view_cmd| {
                        game.move_camera = false;
                        try self.showTextureViewWindow(view_cmd.atl, view_cmd.orig);
                    },
                    .PickTextureIndex => |index| {
                        self.tile_index = @truncate(index);
                        std.log.debug("new index {d}", .{self.tile_index});
                    },
                    .ClickOnMap => |coords| game.map.tryReplaceTile(coords[0], coords[1], self.tile_index),
                    .SaveCurrentMap => {
                        const data = try game.map.map_data.save(application.allocator, Serializer.init(YamlSerializer));
                        defer application.allocator.free(data);
                        try utils.writeFileData("./data/maps/test_map.yaml", data);
                    },
                }
            }
            self.command_queue.clearRetainingCapacity();
        }
    }

    pub fn update(self: *Self, application: *app.App, game: *Game) !void {
        if (self.texture_view_window != null) {
            try self.texture_view_window.?.update();
            if (self.texture_view_window.?.window == null) {
                self.texture_view_window = null;
            }
        }

        try self.processInput(application, game);
        try self.processCommands(application, game);
    }
};
