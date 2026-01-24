const std = @import("std");
const App = @import("app.zig").App;
const glfw = @cImport({
    @cInclude("glfw/glfw3.h");
});
const imgui = @cImport({
    @cDefine("CIMGUI_USE_GLFW", "1");
    @cDefine("CIMGUI_USE_OPENGL3", "1");
    @cDefine("CIMGUI_DEFINE_ENUMS_AND_STRUCTS", "1");
    @cInclude("cimgui.h");
    @cInclude("cimgui_impl.h");
});
pub const Handle = usize;
pub const Context = struct {
    const Self = @This();
    ctx: *imgui.struct_ImGuiContext,
    windows: std.AutoArrayHashMapUnmanaged(Handle, Window) = .empty,
    counter: usize = 0,

    pub fn init(window: ?*glfw.GLFWwindow) !Self {
        const ctx = imgui.igCreateContext(null);
        if (!imgui.ImGui_ImplGlfw_InitForOpenGL(@ptrCast(window), true)) {
            return error.ImGuiError;
        }
        if (!imgui.ImGui_ImplOpenGL3_Init(App.glsl_version)) {
            return error.ImGuiError;
        }

        return .{
            .ctx = ctx,
        };
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        var it = self.windows.iterator();
        while (it.next()) |item| {
            item.value_ptr.deinit(gpa);
        }
        self.windows.deinit(gpa);
    }

    pub fn addWindow(self: *Self, gpa: std.mem.Allocator, wnd: Window) !Handle {
        const res = self.counter;
        try self.windows.put(gpa, res, wnd);
        self.counter += 1;
        return res;
    }

    pub fn removeWindow(self: *Self, handle: Handle) void {
        _ = self.windows.remove(handle);
    }

    pub fn isInputOnUI(self: Self) bool {
        return imgui.igIsItemHovered(imgui.ImGuiHoveredFlags_RectOnly) or self.ctx.IO.WantCaptureMouse;
    }
};

pub const ElementType = enum {
    Window,
    Button,
    Text,
};

pub const Window = struct {
    title: [:0]const u8,
    size: imgui.ImVec2_c,
    children: std.ArrayList(Element),

    fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        self.children.deinit(gpa);
    }
};

pub const Button = struct {
    name: [:0]const u8,
    handle: []const u8,
    size: imgui.ImVec2_c,
    user_data: *anyopaque,
    callback: *const fn (*anyopaque, []const u8) void,
};

pub const Text = struct {
    text: [:0]const u8,
};

pub const Element = union(ElementType) {
    const Self = @This();
    Window: Window,
    Button: Button,
    Text: Text,
};

pub fn init(window: ?*glfw.GLFWwindow) error{ImGuiError}!Context {
    const context: Context = .{ .ctx = imgui.igCreateContext(null) };
    if (!imgui.ImGui_ImplGlfw_InitForOpenGL(@ptrCast(window), true)) {
        return error.ImGuiError;
    }
    if (!imgui.ImGui_ImplOpenGL3_Init(App.glsl_version)) {
        return error.ImGuiError;
    }

    return context;
}

fn draw_window(wnd: Window) void {
    imgui.igSetNextWindowSize(wnd.size, imgui.ImGuiCond_Appearing);
    if (imgui.igBegin(wnd.title, null, 0)) {
        draw_elements(&wnd.children);
    }
    imgui.igEnd();
}

fn draw_button(btn: Button) void {
    if (imgui.igButton(btn.name, btn.size)) {
        btn.callback(btn.user_data, btn.handle);
    }
}

fn draw_text(txt: Text) void {
    imgui.igText(txt.text);
}

fn draw_elements(elements: *const std.ArrayList(Element)) void {
    for (elements.items) |item| {
        switch (item) {
            .Window => |wnd| {
                draw_window(wnd);
            },
            .Button => |btn| {
                draw_button(btn);
            },
            .Text => |txt| {
                draw_text(txt);
            },
        }
    }
}

pub fn draw_imgui(ctx: *const Context) void {
    imgui.ImGui_ImplOpenGL3_NewFrame();
    imgui.ImGui_ImplGlfw_NewFrame();
    imgui.igNewFrame();

    var it = ctx.windows.iterator();
    while (it.next()) |entry| {
        draw_window(entry.value_ptr.*);
    }

    imgui.igRender();
    //glfwMakeContextCurrent(window);
    //glViewport(0, 0, (int)ioptr->DisplaySize.x, (int)ioptr->DisplaySize.y);
    //glClearColor(clearColor.x, clearColor.y, clearColor.z, clearColor.w);
    //glClear(GL_COLOR_BUFFER_BIT);
    imgui.ImGui_ImplOpenGL3_RenderDrawData(imgui.igGetDrawData());
}
