const Window = @This();
const App = @import("app.zig").App;
const std = @import("std");
const opengl = @import("opengl.zig");
const imgui = @import("imgui.zig");
pub const glfw = @cImport({
    @cInclude("glfw/glfw3.h");
});
var buffer: [1024]u8 = undefined;
var window_allocator: std.heap.FixedBufferAllocator = .init(&buffer);
const allocator = window_allocator.allocator();

pub const MouseButtonState = enum(c_int) {
    Press = glfw.GLFW_PRESS,
    Release = glfw.GLFW_RELEASE,
};

pub const MouseButton = enum(c_int) {
    Left = glfw.GLFW_MOUSE_BUTTON_1,
    Right = glfw.GLFW_MOUSE_BUTTON_2,
    Middle = glfw.GLFW_MOUSE_BUTTON_3,
};

pub const Key = enum(c_int) {
    Minus = glfw.GLFW_KEY_MINUS,
    Equal = glfw.GLFW_KEY_EQUAL,
};

pub const MouseBtnEvent = struct {
    btn: MouseButton,
    state: MouseButtonState,
};

var windows: std.ArrayList(Window) = .empty; //(window_allocator.allocator());

window: ?*glfw.GLFWwindow,
im_context: imgui.Context,
mouse_events: std.ArrayList(MouseBtnEvent),
mouse_button_state: [3]bool = [_]bool{ false, false, false },

fn mouseCallback(window: ?*glfw.GLFWwindow, button: c_int, action: c_int, _: c_int) callconv(.c) void {
    for (windows.items) |*wnd| {
        if (wnd.window == window and !wnd.im_context.isInputOnUI()) {
            wnd.onMouseAction(button, action) catch {};
            break;
        }
    }
}

pub fn create(_: std.mem.Allocator, width: u32, height: u32, title: []const u8) !*Window {
    const window = glfw.glfwCreateWindow(
        @intCast(width),
        @intCast(height),
        title.ptr,
        null,
        null,
    );

    glfw.glfwMakeContextCurrent(window);
    errdefer glfw.glfwDestroyWindow(window);

    _ = glfw.glfwSetMouseButtonCallback(
        window,
        mouseCallback,
    );

    try windows.append(window_allocator.allocator(), .{
        .window = window,
        .im_context = try .init(@ptrCast(window)),
        .mouse_events = .empty,
    });

    return &windows.items[windows.items.len - 1];
}

pub fn destroy(self: *Window, gpa: std.mem.Allocator) void {
    self.mouse_events.deinit(allocator);
    self.im_context.deinit(gpa);
    glfw.glfwDestroyWindow(self.window);
}

pub fn isWindowShouldClose(self: Window) bool {
    return glfw.glfwWindowShouldClose(self.window) != 0;
}

pub fn frameBegin(self: *Window) void {
    self.mouse_events.clearRetainingCapacity();
    glfw.glfwMakeContextCurrent(self.window);
}

pub fn frameEnd(self: Window) void {
    imgui.draw_imgui(&self.im_context);

    glfw.glfwSwapBuffers(self.window);
    glfw.glfwPollEvents();
}

fn onMouseAction(self: *Window, btn: c_int, action: c_int) !void {
    self.mouse_button_state[@intCast(btn)] = action == glfw.GLFW_PRESS;
    try self.mouse_events.append(allocator, .{
        .btn = @enumFromInt(btn),
        .state = @enumFromInt(action),
    });
}

pub fn getLastMouseEvent(self: Window) ?MouseBtnEvent {
    return self.mouse_events.getLastOrNull();
}

pub fn getCursorPos(self: Window) @Vector(2, i32) {
    var xpos: f64 = undefined;
    var ypos: f64 = undefined;
    glfw.glfwGetCursorPos(self.window, &xpos, &ypos);

    return .{ @intFromFloat(xpos), @intFromFloat(ypos) };
}

pub fn isMouseButtonPressed(self: Window, btn: MouseButton) bool {
    if (self.getLastMouseEvent()) |e| {
        return e.btn == btn and e.state == .Press;
    }
    return false; //glfw.glfwGetMouseButton(self.window, @intFromEnum(btn)) == glfw.GLFW_PRESS;
}

pub fn isMouseButtonReleased(self: Window, btn: MouseButton) bool {
    if (self.getLastMouseEvent()) |e| {
        return e.btn == btn and e.state == .Release;
    }
    return false; //return glfw.glfwGetMouseButton(self.window, @intFromEnum(btn)) == glfw.GLFW_RELEASE;
}

pub fn isKeyButtonPressed(self: Window, btn: Key) bool {
    return glfw.glfwGetKey(self.window, @intFromEnum(btn)) == glfw.GLFW_PRESS;
}
