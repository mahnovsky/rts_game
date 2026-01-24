const std = @import("std");
const App = @import("app.zig").App;
const Game = @import("Game.zig");

// In your root source file (e.g., src/main.zig)
pub const std_options: std.Options = .{
    // Set the global minimum log level to .warn, .err, or .info to silence debug logs
    // .err will show only errors
    // .warn will show errors and warnings
    // .info will show errors, warnings, and informational messages
    // .debug (default in Debug mode) shows all messages
    .log_level = .warn,
};

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

    try app.editor.pushCommand(.OpenEditorWindow);

    try app.run();

    return 0;
}
