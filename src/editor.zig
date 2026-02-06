const std = @import("std");
const atlas = @import("atlas.zig");
const texture_view = @import("texture_view.zig");
const GameMap = @import("game_map.zig").GameMap;
const app = @import("app.zig");
const Game = @import("Game.zig");
const Window = @import("Window.zig");
const utils = @import("utils.zig");
const Serializer = @import("serializer.zig").Serializer;
const YamlSerializer = @import("serializer.zig").YamlSerializer;
const MapData = @import("game_map.zig").MapData;
const imgui = @import("imgui.zig");
const glfw = @cImport({
    @cInclude("glfw/glfw3.h");
});
pub const CommandType = enum {
    OpenEditorWindow,
    OpenTextureView,
    PickTextureIndex,
    ClickOnMap,
    SaveCurrentMap,
};

pub const Command = union(CommandType) {
    const Self = @This();
    OpenEditorWindow: void,
    OpenTextureView: struct {
        atl: atlas.Atlas,
        orig: *anyopaque,
    },
    PickTextureIndex: u32,
    ClickOnMap: @Vector(2, u32),
    SaveCurrentMap: void,

    fn is(self: Self, tag: std.meta.Tag(Self)) bool {
        return self == tag;
    }
};

const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    fn initDefault() @This() {
        return .{ .x = 0, .y = 0, .z = 0 };
    }
};

pub const Editor = struct {
    pub const TAGS = .{
        .ignore_list = .{ "gpa", "command_queue" },
        .points = .{ .add_default_item = &Vec3.initDefault },
    };
    const Self = @This();
    gpa: std.mem.Allocator,
    command_queue: std.ArrayList(Command),
    texture_view_window: ?texture_view.TextureViewWindow,
    tile_index: u16 = 0,
    editor_window: ?imgui.Handle = null,
    points: []Vec3,
    name: []const u8,

    pub fn init(gpa: std.mem.Allocator) Self {
        const name = gpa.alloc(u8, 4) catch unreachable;
        std.mem.copyForwards(u8, name, "test");
        const points = gpa.alloc(Vec3, 8) catch unreachable;
        for (points) |*p| {
            p.* = Vec3.initDefault();
        }
        return .{
            .gpa = gpa,
            .command_queue = .empty,
            .texture_view_window = null,
            .points = points,
            .name = name,
        };
    }

    pub fn deinit(self: *Self) void {
        std.debug.print("Actual text {s}\n", .{self.name});
        if (self.texture_view_window != null) {
            self.texture_view_window.?.close();
        }
        self.command_queue.deinit(self.gpa);
    }

    fn onButtonPressed(user_data: *anyopaque, handle: []const u8) void {
        const self: *Self = @ptrCast(@alignCast(user_data));
        std.debug.print("On Button pressed {s}\n", .{handle});
        const application = app.context.getResource(app.App).?;
        const game = app.context.getResource(Game).?;

        if (std.meta.stringToEnum(CommandType, handle)) |command| {
            switch (command) {
                .OpenTextureView => self.pushCommand(.{ .OpenTextureView = .{
                    .atl = game.map.render_data.atlas,
                    .orig = @ptrCast(application.window.window.?),
                } }) catch unreachable,
                .SaveCurrentMap => self.pushCommand(.SaveCurrentMap) catch unreachable,
                else => {},
            }
        }
    }

    fn openWindow(self: *Self, main_wnd: *Window) !void {
        if (self.editor_window != null) {
            std.log.warn("Editor window already exist", .{});
            return;
        }

        var children = try std.ArrayList(imgui.Element).initCapacity(self.gpa, 10);
        try children.append(self.gpa, .{ .Button = .{
            .name = "Open tiles window",
            .handle = @tagName(CommandType.OpenTextureView),
            .size = .{ .x = 200, .y = 50 },
            .user_data = self,
            .callback = &onButtonPressed,
        } });

        try children.append(self.gpa, .{ .Button = .{
            .name = "Save",
            .handle = @tagName(CommandType.SaveCurrentMap),
            .size = .{ .x = 200, .y = 50 },
            .user_data = self,
            .callback = &onButtonPressed,
        } });

        var wnd: imgui.Panel = .{
            .title = "Editor",
            .size = .{ .x = 400, .y = 400 },
            .children = children,
        };

        wnd.reflectItem(Self, self.gpa, self);
        self.editor_window = try main_wnd.im_context.addWindow(self.gpa, wnd);
    }

    pub fn pushCommand(self: *Self, command: Command) !void {
        std.log.debug("push command {s}", .{@tagName(command)});
        try self.command_queue.append(self.gpa, command);
    }

    pub fn showTextureViewWindow(self: *Self, atl: atlas.Atlas, orig: *anyopaque) !void {
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
    }

    pub fn processCommands(self: *Self, application: *app.App, game: *Game) !void {
        if (self.command_queue.items.len > 0) {
            for (self.command_queue.items) |cmd| {
                switch (cmd) {
                    .OpenEditorWindow => {
                        try self.openWindow(application.window);
                    },
                    .OpenTextureView => |view_cmd| {
                        game.move_camera = false;
                        try self.showTextureViewWindow(view_cmd.atl, view_cmd.orig);
                    },
                    .PickTextureIndex => |index| {
                        self.tile_index = @truncate(index);
                        std.log.debug("new index {d}", .{self.tile_index});
                        game.move_camera = true;
                    },
                    .ClickOnMap => |coords| game.map.tryReplaceTile(coords[0], coords[1], self.tile_index),
                    .SaveCurrentMap => {
                        //const data = try game.map.map_data.save(application.allocator, Serializer(MapData).init(YamlSerializer(MapData)));
                        const data = try game.map.map_data.save(application.allocator, YamlSerializer);
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
