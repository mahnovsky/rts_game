const std = @import("std");
const App = @import("app.zig").App;
const glfw = @cImport({
    @cInclude("glfw/glfw3.h");
});

const c_string = @cImport({
    @cInclude("string.h");
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
    windows: std.AutoArrayHashMapUnmanaged(Handle, Panel) = .empty,
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

    pub fn addWindow(self: *Self, gpa: std.mem.Allocator, wnd: Panel) !Handle {
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

pub const Panel = struct {
    const Self = @This();
    title: [:0]const u8,
    top_level: bool = true,
    is_open: bool = false,
    size: imgui.ImVec2_c,
    children: std.ArrayList(Element),

    fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        self.children.deinit(gpa);
    }

    pub fn reflectEnum(
        comptime T: type,
        gpa: std.mem.Allocator,
        name: [:0]const u8,
        e: std.builtin.Type.Enum,
        item_ptr: *anyopaque,
    ) Element {
        var items: [][:0]const u8 = gpa.alloc([:0]const u8, e.fields.len) catch unreachable;
        inline for (e.fields, 0..) |field, i| {
            items[i] = field.name;
        }

        const gen = struct {
            fn update(ptr: *anyopaque, selected: u32) void {
                const self: *T = @ptrCast(@alignCast(ptr));
                self.* = @enumFromInt(selected);
                std.debug.print("new item selected for {s}\n", .{@tagName(self.*)});
            }
        };

        return .{
            .Combo = .{
                .ptr = item_ptr,
                .selected = 0,
                .update_fn = &gen.update,
                .title = name,
                .items = items,
            },
        };
    }

    pub fn reflectBool(
        name: [:0]const u8,
        item_ptr: *bool,
    ) Element {
        return .{
            .CheckBox = .{
                .title = name,
                .bool_ptr = item_ptr,
            },
        };
    }

    pub fn reflectInt(
        comptime T: type,
        name: [:0]const u8,
        item_ptr: *T,
    ) Element {
        return .{
            .IntValue = .{
                .title = name,
                .value_ptr = item_ptr,
            },
        };
    }

    pub fn reflectValue(
        comptime T: type,
        name: [:0]const u8,
        item_ptr: *T,
    ) Element {
        const info = @typeInfo(T);
        return blk: {
            switch (info) {
                .float => |f| {
                    if (f.bits == 32) {
                        break :blk .{ .Float32Value = .{ .title = name, .value_ptr = item_ptr } };
                    } else if (f.bits == 64) {
                        break :blk .{ .Float64Value = .{ .title = name, .value_ptr = item_ptr } };
                    }
                },
                .int => |v| {
                    switch (v.signedness) {
                        .signed => {
                            switch (v.bits) {
                                8 => unreachable,
                                16 => break :blk .{ .Int16Value = .{ .title = name, .value_ptr = item_ptr } },
                                32 => break :blk .{ .Int32Value = .{ .title = name, .value_ptr = item_ptr } },
                                64 => break :blk .{ .Int64Value = .{ .title = name, .value_ptr = item_ptr } },
                                else => unreachable,
                            }
                        },
                        .unsigned => {
                            switch (v.bits) {
                                8 => unreachable,
                                16 => break :blk .{ .Uint16Value = .{ .title = name, .value_ptr = item_ptr } },
                                32 => break :blk .{ .Uint32Value = .{ .title = name, .value_ptr = item_ptr } },
                                64 => break :blk .{ .Uint64Value = .{ .title = name, .value_ptr = item_ptr } },
                                else => unreachable,
                            }
                        },
                    }
                },
                else => unreachable,
            }
        };
    }

    pub fn reflectStruct(comptime S: type, gpa: std.mem.Allocator, name: [:0]const u8, s: *S) Element {
        var panel: Panel = .{
            .is_open = false,
            .top_level = false,
            .title = name,
            .size = .{ .x = 400, .y = 400 },
            .children = .empty,
        };
        panel.reflectItem(S, gpa, s);
        std.debug.print("Reflect struct {s}, top_level {}\n", .{ name, panel.top_level });

        return .{ .Panel = panel };
    }

    fn reflectString(
        gpa: std.mem.Allocator,
        name: [:0]const u8,
        item_ptr: *[]const u8,
    ) Element {
        const buffer = gpa.alloc(u8, 4096) catch unreachable;
        @memset(buffer, 0);
        std.mem.copyForwards(u8, buffer, item_ptr.*);
        gpa.free(item_ptr.*);
        item_ptr.* = buffer;
        std.debug.print("String {s}\n", .{name});
        return .{
            .EditStringBox = .{
                .title = name,
                .value_ptr = item_ptr,
                .buffer = buffer,
            },
        };
    }

    fn reflectSliceOfStructs(
        comptime S: type,
        gpa: std.mem.Allocator,
        name: [:0]const u8,
        item_ptr: *[]S,
        make_default_fn: *const fn () S,
    ) Element {
        const Container = struct {
            gpa_alloc: std.mem.Allocator,
            base_ptr: *[]S,
            elements: std.ArrayList(S),
            root_panel: Panel,
            add_default_item_fn: *const fn () S,

            fn init(
                gpa_alloc: std.mem.Allocator,
                root: Panel,
                base: *[]S,
                add_default_item_fn: *const fn () S,
            ) *@This() {
                const max_elements = blk: {
                    if (base.len < 16) {
                        break :blk 64;
                    } else {
                        break :blk base.len * 2;
                    }
                };

                const res = gpa_alloc.create(@This()) catch @panic("oom");
                res.* = .{
                    .gpa_alloc = gpa_alloc,
                    .base_ptr = base,
                    .elements = std.ArrayList(S).initCapacity(gpa_alloc, max_elements) catch unreachable,
                    .add_default_item_fn = add_default_item_fn,
                    .root_panel = root,
                };

                res.elements.appendSlice(gpa_alloc, base.*) catch @panic("oom");
                res.buildUi();
                return res;
            }

            fn buildUi(self: *@This()) void {
                std.debug.print("Build ui {d}\n", .{self.elements.items.len});
                self.root_panel.children.clearRetainingCapacity();
                var buffer: [128]u8 = undefined;
                for (self.elements.items, 0..) |*item, index| {
                    const title = std.fmt.bufPrintZ(&buffer, "element {d}", .{index}) catch @panic("oom");
                    var panel: Panel = .{
                        .is_open = false,
                        .top_level = false,
                        .title = self.gpa_alloc.dupeZ(u8, title) catch @panic("oom"),
                        .size = .{ .x = 400, .y = 400 },
                        .children = .empty,
                    };
                    panel.reflectItem(S, self.gpa_alloc, item);
                    self.root_panel.children.append(self.gpa_alloc, .{ .Panel = panel }) catch @panic("oom");
                }
            }

            fn getRootPanel(ptr: *anyopaque) *Panel {
                const self: *@This() = @ptrCast(@alignCast(ptr));
                return &self.root_panel;
            }

            fn modifySlice(ptr: *anyopaque, handle: []const u8) void {
                const self: *@This() = @ptrCast(@alignCast(ptr));
                if (std.mem.eql(u8, handle, "add_default_item")) {
                    self.addNew();
                    self.base_ptr.* = self.elements.items;
                }

                self.buildUi();
            }

            fn addNew(self: *@This()) void {
                std.debug.print("AddNew ui {d}\n", .{self.elements.items.len});
                self.elements.append(self.gpa_alloc, self.add_default_item_fn()) catch @panic("oom");
            }
        };

        return .{
            .EditableSlice = .{
                .container = Container.init(
                    gpa,
                    .{
                        .title = name,
                        .top_level = false,
                        .is_open = false,
                        .size = .{ .x = 400, .y = 400 },
                        .children = .empty,
                    },
                    item_ptr,
                    make_default_fn,
                ),
                .modify_slice_fn = &Container.modifySlice,
                .get_root_panel = &Container.getRootPanel,
            },
        };
    }

    fn reflectArrayOfStructs(
        comptime S: type,
        comptime N: usize,
        gpa: std.mem.Allocator,
        name: [:0]const u8,
        item_ptr: *[N]S,
    ) Element {
        var children: std.ArrayList(Element) = .empty;
        var buffer: [128]u8 = undefined;
        for (item_ptr, 0..) |*item, index| {
            const title = std.fmt.bufPrintZ(&buffer, "element {d}", .{index}) catch @panic("oom");
            var panel: Panel = .{
                .is_open = false,
                .top_level = false,
                .title = gpa.dupeZ(u8, title) catch @panic("oom"),
                .size = .{ .x = 400, .y = 400 },
                .children = .empty,
            };
            panel.reflectItem(S, gpa, item);
            children.append(gpa, .{ .Panel = panel }) catch @panic("oom");
        }
        return .{
            .Panel = .{
                .title = name,
                .top_level = false,
                .is_open = false,
                .size = .{ .x = 400, .y = 400 },
                .children = children,
            },
        };
    }
    pub fn reflectItem(self: *Self, comptime S: type, gpa: std.mem.Allocator, s: *S) void {
        const type_info = @typeInfo(S);
        inline for (type_info.@"struct".fields) |field| {
            switch (@typeInfo(field.type)) {
                .@"enum" => |e| {
                    const element = reflectEnum(field.type, gpa, field.name, e, &@field(s, field.name));
                    self.children.append(gpa, element) catch unreachable;
                },
                .bool => {
                    self.children.append(gpa, reflectBool(field.name, &@field(s, field.name))) catch unreachable;
                },
                .float, .int => {
                    self.children.append(gpa, reflectValue(field.type, field.name, &@field(s, field.name))) catch unreachable;
                },
                .array => |p| {
                    std.debug.print("Array {s}, {s}\n", .{ field.name, @typeName(p.child) });
                    const element = reflectArrayOfStructs(p.child, p.len, gpa, field.name, &@field(s, field.name));

                    self.children.append(gpa, element) catch @panic("oom");
                },
                .pointer => |p| {
                    std.debug.print("Pointer {s}, {s}, {s}\n", .{ field.name, @typeName(p.child), @tagName(p.size) });
                    if (p.size == .slice) {
                        const info_u8 = @typeInfo(u8);
                        const element = blk: switch (@typeInfo(p.child)) {
                            info_u8 => break :blk reflectString(gpa, field.name, &@field(s, field.name)),
                            .@"struct" => {
                                if (!@hasField(@TypeOf(S.TAGS), field.name)) {
                                    @compileError("For slices of struct needed meta info, plz provide its in TAGS");
                                }
                                const meta = @field(S.TAGS, field.name);
                                break :blk reflectSliceOfStructs(p.child, gpa, field.name, &@field(s, field.name), meta.add_default_item);
                            },
                            else => unreachable,
                        };
                        self.children.append(gpa, element) catch unreachable;
                    }
                },
                .@"struct" => {
                    // Access the metadata from the nested TAGS struct
                    // const meta = @field(S.TAGS, field.name);
                    // const db_type = meta.db_type;
                    // const description = meta.description;
                    var ignore = false;
                    if (@hasField(@TypeOf(S.TAGS), "ignore_list")) {
                        const ignore_list = @field(S.TAGS, "ignore_list");
                        inline for (ignore_list) |item| {
                            if (std.mem.eql(u8, item, field.name)) {
                                ignore = true;
                            }
                        }
                    }

                    if (!ignore) {
                        self.children.append(gpa, reflectStruct(field.type, gpa, field.name, &@field(s, field.name))) catch unreachable;
                    }
                },
                else => {},
            }
        }
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

pub const Combo = struct {
    ptr: ?*anyopaque,
    selected: u32,
    title: [:0]const u8,
    items: [][:0]const u8,
    update_fn: *const fn (self: *anyopaque, item: u32) void,
};

pub const CheckBox = struct {
    title: [:0]const u8,
    bool_ptr: *bool,
};

fn ValueBox(comptime T: type) type {
    return struct {
        const V: type = T;
        title: [:0]const u8,
        value_ptr: *T,
    };
}

pub const EditStringBox = struct {
    title: [:0]const u8,
    buffer: []u8,
    value_ptr: *[]const u8,
};

const EditableSlice = struct {
    container: *anyopaque,
    get_root_panel: *const fn (*anyopaque) *Panel,
    modify_slice_fn: *const fn (*anyopaque, []const u8) void,
};

pub const Element = union(enum) {
    const Self = @This();
    Panel: Panel,
    Button: Button,
    Text: Text,
    Combo: Combo,
    CheckBox: CheckBox,
    Float32Value: ValueBox(f32),
    Float64Value: ValueBox(f64),
    Int8Value: ValueBox(i8),
    Int16Value: ValueBox(i16),
    Int32Value: ValueBox(i32),
    Int64Value: ValueBox(i64),
    Uint8Value: ValueBox(u8),
    Uint16Value: ValueBox(u16),
    Uint32Value: ValueBox(u32),
    Uint64Value: ValueBox(u64),
    EditStringBox: EditStringBox,
    EditableSlice: EditableSlice,
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

fn drawPanel(wnd: *Panel) void {
    if (wnd.top_level) {
        imgui.igSetNextWindowSize(wnd.size, imgui.ImGuiCond_Appearing);
        if (imgui.igBegin(wnd.title, &wnd.is_open, 0)) {
            drawElements(&wnd.children);
        }
        imgui.igEnd();
    } else {
        if (imgui.igTreeNodeEx_Str(wnd.title, imgui.ImGuiTreeNodeFlags_Framed)) {
            drawElements(&wnd.children);
            imgui.igTreePop();
        }
    }
}

fn drawButton(btn: Button) void {
    if (imgui.igButton(btn.name, btn.size)) {
        btn.callback(btn.user_data, btn.handle);
    }
}

fn drawText(txt: Text) void {
    imgui.igText(txt.text);
}

fn drawCombo(cmb: *Combo) void {
    const current = cmb.selected;
    if (imgui.igBeginCombo(cmb.title, cmb.items[current], 0)) {
        for (0..cmb.items.len) |n| {
            const is_selected = (cmb.selected == n);
            if (imgui.igSelectable_Bool(cmb.items[n], is_selected, 0, .{ .x = 200, .y = 50 })) {
                cmb.selected = @intCast(n);
            }

            if (is_selected) {
                imgui.igSetItemDefaultFocus();
            }
        }
        imgui.igEndCombo();
    }
    if (cmb.ptr) |ptr| {
        if (current != cmb.selected) {
            std.debug.assert(cmb.selected < cmb.items.len);
            cmb.update_fn(ptr, cmb.selected);
        }
    }
}

fn drawCheckBox(box: *CheckBox) void {
    _ = imgui.igCheckbox(box.title, @ptrCast(box.bool_ptr));
}

fn drawIntEdit(comptime T: type, v: *ValueBox(T)) void {
    const info = @typeInfo(T);
    if (info != .int) {
        @compileError("Can be used only for integers");
    }

    switch (info.int.signedness) {
        .signed => {
            const data_type = switch (info.int.bits) {
                8 => imgui.ImGuiDataType_S8,
                16 => imgui.ImGuiDataType_S16,
                32 => imgui.ImGuiDataType_S32,
                64 => imgui.ImGuiDataType_S64,
                else => unreachable,
            };
            var speed: T = 1;
            var fast_speed: T = 10;
            _ = imgui.igInputScalar(v.title, data_type, v.value_ptr, &speed, &fast_speed, "%d", 0);
        },
        .unsigned => {
            const data_type = switch (info.int.bits) {
                8 => imgui.ImGuiDataType_U8,
                16 => imgui.ImGuiDataType_U16,
                32 => imgui.ImGuiDataType_U32,
                64 => imgui.ImGuiDataType_U64,
                else => unreachable,
            };
            var speed: T = 1;
            var fast_speed: T = 10;
            _ = imgui.igInputScalar(v.title, data_type, v.value_ptr, &speed, &fast_speed, "%u", 0);
        },
    }
}

fn drawFloatEdit(comptime T: type, v: *ValueBox(T)) void {
    const info = @typeInfo(T);
    if (info != .float) {
        @compileError("Can be used only for floats");
    }
    if (info.float.bits == 32) {
        _ = imgui.igInputFloat(v.title, v.value_ptr, 0.1, 1.0, "%.2f", 0);
    } else if (info.float.bits == 64) {
        _ = imgui.igInputDouble(v.title, v.value_ptr, 0.1, 1.0, "%.2f", 0);
    }
}

fn drawStringEdit(v: *EditStringBox) void {
    if (imgui.igInputText(v.title, v.buffer.ptr, v.buffer.len, 0, null, null)) {
        v.value_ptr.* = std.mem.span(@as([*:0]const u8, @ptrCast(v.buffer.ptr)));
    }
    //callback: ?*const fn ([*c]struct_ImGuiInputTextCallbackData) c_int, null)
}

fn drawSlice(v: *EditableSlice) void {
    const panel = v.get_root_panel(v.container);
    drawElements(&panel.children);
    drawButton(.{
        .name = "+",
        .handle = "add_default_item",
        .size = .{ .x = 40, .y = 40 },
        .user_data = v.container,
        .callback = v.modify_slice_fn,
    });
}

fn drawElements(elements: *std.ArrayList(Element)) void {
    for (elements.items) |*item| {
        switch (item.*) {
            .Panel => |*panel| {
                drawPanel(panel);
            },
            .Button => |btn| {
                drawButton(btn);
            },
            .Text => |txt| {
                drawText(txt);
            },
            .Combo => |*cmb| {
                drawCombo(cmb);
            },
            .CheckBox => |*box| {
                drawCheckBox(box);
            },
            .Int8Value => |*v| {
                drawIntEdit(i8, v);
            },
            .Int16Value => |*v| {
                drawIntEdit(i16, v);
            },
            .Int32Value => |*v| {
                drawIntEdit(i32, v);
            },
            .Int64Value => |*v| {
                drawIntEdit(i64, v);
            },
            .Uint8Value => |*v| {
                drawIntEdit(u8, v);
            },
            .Uint16Value => |*v| {
                drawIntEdit(u16, v);
            },
            .Uint32Value => |*v| {
                drawIntEdit(u32, v);
            },
            .Uint64Value => |*v| {
                drawIntEdit(u64, v);
            },
            .Float32Value => |*v| {
                drawFloatEdit(f32, v);
            },
            .Float64Value => |*v| {
                drawFloatEdit(f64, v);
            },
            .EditStringBox => |*v| {
                drawStringEdit(v);
            },
            .EditableSlice => |*v| {
                drawSlice(v);
            },
        }
    }
}

pub fn drawImgui(ctx: *const Context) void {
    imgui.ImGui_ImplOpenGL3_NewFrame();
    imgui.ImGui_ImplGlfw_NewFrame();
    imgui.igNewFrame();

    var it = ctx.windows.iterator();
    while (it.next()) |entry| {
        drawPanel(entry.value_ptr);
    }

    imgui.igRender();
    //glfwMakeContextCurrent(window);
    //glViewport(0, 0, (int)ioptr->DisplaySize.x, (int)ioptr->DisplaySize.y);
    //glClearColor(clearColor.x, clearColor.y, clearColor.z, clearColor.w);
    //glClear(GL_COLOR_BUFFER_BIT);
    imgui.ImGui_ImplOpenGL3_RenderDrawData(imgui.igGetDrawData());
}
