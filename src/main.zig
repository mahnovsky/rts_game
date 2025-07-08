const std = @import("std");
const App = @import("app.zig").App;
const Game = @import("Game.zig");

pub fn main() anyerror!u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const width: u32 = 1024;
    const height: u32 = 768;
    const allocator = gpa.allocator();
    var app = try App.init(
        width,
        height,
        allocator,
    );
    defer app.deinit();

    var game = try Game.init(allocator, &app);
    defer game.deinit(allocator);

    try app.run(&game);

    return 0;
}
