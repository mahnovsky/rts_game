const gl = @cImport({
    @cInclude("glad/glad.h");
});

const std = @import("std");
const zm = @import("zm");
const utils = @import("utils.zig");
const enums = std.enums;

const c_cast = std.zig.c_translation.cast;
const info = std.log.info;
const warn = std.log.warn;
const err = std.log.err;
const panic = std.debug.panic;

const Handle = gl.GLuint;
const Vec3 = @Vector(3, f32);
const Color = @Vector(3, u8);
const ColorF = @Vector(3, f32);
pub const GLAPIENTRY: std.builtin.CallingConvention = .{ .x86_64_win = .{} };

const OpenGLError = error{FailedInitGLAD};

fn MessageCallback(_: gl.GLenum, errType: gl.GLenum, _: gl.GLuint, severity: gl.GLenum, _: gl.GLsizei, message: [*c]const u8, _: ?*const anyopaque) callconv(GLAPIENTRY) void {
    const errStr = switch (errType) {
        gl.GL_DEBUG_TYPE_ERROR => "ERROR",
        gl.GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR => "DEPRECATED_BEHAVIOR",
        gl.GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR => "UNDEFINED_BEHAVIOR",
        gl.GL_DEBUG_TYPE_PORTABILITY => "PORTABILITY",
        gl.GL_DEBUG_TYPE_PERFORMANCE => "PERFORMANCE",
        gl.GL_DEBUG_TYPE_OTHER => "OTHER",
        else => "UNKNOWN",
    };

    const servStr = switch (severity) {
        gl.GL_DEBUG_SEVERITY_LOW => "LOW",
        gl.GL_DEBUG_SEVERITY_MEDIUM => "MEDIUM",
        gl.GL_DEBUG_SEVERITY_HIGH => "HIGH",
        gl.GL_DEBUG_SEVERITY_NOTIFICATION => "INFO",
        else => "UNKNOWN",
    };

    const fmtStr = "GL CALLBACK: [type: {s}, severity: {s}] \n\tmessage: {s}\n";
    const fmtArgs = .{ errStr, servStr, message };
    if (severity != gl.GL_DEBUG_SEVERITY_NOTIFICATION) {
        if (severity == gl.GL_DEBUG_SEVERITY_HIGH) {
            err(fmtStr, fmtArgs);
            std.debug.assertReadable("OpenGL error occurred");
        } else {
            warn(fmtStr, fmtArgs);
        }
    } else {
        info(fmtStr, fmtArgs);
    }
}

pub fn setErrorCallback() void {
    gl.glEnable(gl.GL_DEBUG_OUTPUT);
    gl.glDebugMessageCallback(MessageCallback, undefined);
}

pub const RenderState = enum(u32) {
    Blend = gl.GL_BLEND,
    Scissor = gl.GL_SCISSOR_TEST,
};

pub const RenderStateBitSet = enums.EnumSet(RenderState);
pub const RenderFuncParams = struct {
    pub const TransparentBlend: RenderFuncParams = .{
        .first = gl.GL_SRC_ALPHA,
        .second = gl.GL_ONE_MINUS_SRC_ALPHA,
        .func = blendFunc,
    };

    first: gl.GLenum,
    second: gl.GLenum,
    func: *const fn (gl.GLenum, gl.GLenum) void,
};

fn blendFunc(first: c_uint, second: c_uint) void {
    gl.glBlendFunc(first, second);
}

pub const RenderStateFlags = struct {
    const Self = @This();
    pub const empty: Self = .{
        .flags = .initEmpty(),
        .func_params = .init(.{}),
    };

    flags: RenderStateBitSet,
    func_params: enums.EnumMap(RenderState, RenderFuncParams),

    pub fn setFlags(self: *Self, flags: RenderStateBitSet) void {
        self.flag = flags;
    }

    pub fn setFunc(self: *Self, state: RenderState, params: RenderFuncParams) void {
        self.func_params.put(state, params);
    }

    fn enable(self: Self, on: bool) void {
        const states = enums.values(RenderState);

        for (states) |state| {
            if (self.flags.contains(state)) {
                if (on) {
                    gl.glEnable(@intFromEnum(state));
                    if (self.func_params.get(state)) |f| {
                        f.func(f.first, f.second);
                    }
                } else {
                    gl.glDisable(@intFromEnum(state));
                }
            }
        }
    }
};

pub fn init(inProc: *const fn ([*c]const u8) callconv(.c) ?*const fn () callconv(.c) void) OpenGLError!void {
    const proc: gl.GLADloadproc = @ptrCast(inProc);
    if (gl.gladLoadGLLoader(proc) == gl.GL_FALSE) {
        return error.FailedInitGLAD;
    }

    setErrorCallback();
}

pub fn clearColor(color: ColorF) void {
    gl.glClearColor(color[0], color[1], color[2], 255);
}

// order pos > uv > color
pub const VertexFormat = enum(u32) {
    PositionXY = 0x1, // 0001
    PositionXYZ = 0x3, // 0011
    TextureUV = 0x8,
    ColorRGB = 0x10,
};
const VertexFormatBitSet = enums.EnumSet(VertexFormat);

pub const Vertex3P = struct {
    const Self = @This();
    pub const format: VertexFormatBitSet = VertexFormatBitSet.init(.{ .PositionXYZ = true, .ColorRGB = true });
    x: f32,
    y: f32,
    z: f32,

    r: f32 = 1.0,
    g: f32 = 0.0,
    b: f32 = 0.0,
};

pub const Vertex3T = struct {
    const Self = @This();
    pub const format: VertexFormatBitSet = VertexFormatBitSet.init(.{ .PositionXYZ = true, .TextureUV = true });
    x: f32,
    y: f32,
    z: f32,

    u: f32,
    v: f32,
};

const ComponentInfo = struct {
    const Self = @This();
    count: i32,
    size: i32,
    ctype: u32,

    fn init(format: VertexFormat) Self {
        const floatSize = @sizeOf(f32);
        return switch (format) {
            .PositionXY => .{ .count = 2, .size = floatSize, .ctype = gl.GL_FLOAT },
            .PositionXYZ => .{ .count = 3, .size = floatSize, .ctype = gl.GL_FLOAT },
            .TextureUV => .{ .count = 2, .size = floatSize, .ctype = gl.GL_FLOAT },
            .ColorRGB => .{ .count = 3, .size = floatSize, .ctype = gl.GL_FLOAT },
        };
    }
};

pub const BufferUsage = enum(u32) {
    Static = gl.GL_STATIC_DRAW,
    Dynamic = gl.GL_DYNAMIC_DRAW,
};

pub const BufferObject = struct {
    const Self = @This();
    handle: Handle,
    buffer_type: u32,
    vertices: i32,
    vertex_size: i32,
    format: VertexFormatBitSet,

    pub fn init(comptime T: type, elements: []const T, usage: BufferUsage) Self {
        var handle: Handle = undefined;
        const buffer_type = if (T == u16) gl.GL_ELEMENT_ARRAY_BUFFER else gl.GL_ARRAY_BUFFER;

        gl.glGenBuffers(1, &handle);
        gl.glBindBuffer(buffer_type, handle);
        gl.glBufferData(
            buffer_type,
            @intCast(elements.len * @sizeOf(T)),
            elements.ptr,
            @intFromEnum(usage),
        );

        return Self{
            .handle = handle,
            .buffer_type = buffer_type,
            .vertices = @intCast(elements.len),
            .vertex_size = @sizeOf(T),
            .format = T.format,
        };
    }

    pub fn deinit(self: Self) void {
        gl.glDeleteBuffers(1, self.handle);
    }

    pub fn bind(self: Self) void {
        gl.glBindBuffer(self.buffer_type, self.handle);
    }

    pub fn update(self: Self, comptime T: type, elements: []const T, offset: u32) void {
        self.bind();
        gl.glBufferSubData(self.buffer_type, offset, @intCast(elements.len * @sizeOf(T)), elements.ptr);
    }
};

const ArrayObject = struct {
    const Self = @This();
    handle: Handle,

    pub fn init() Self {
        var handle: Handle = undefined;
        gl.glGenVertexArrays(1, &handle);

        return Self{ .handle = handle };
    }

    pub fn bind(self: Self) void {
        gl.glBindVertexArray(self.handle);
    }

    pub fn unbind() void {
        gl.glBindVertexArray(0);
    }
};

fn isShaderCompiled(shader: Handle) bool {
    var success: gl.GLint = 0;
    gl.glGetShaderiv(shader, gl.GL_COMPILE_STATUS, &success);

    return success > 0;
}

fn compileShader(shaderType: gl.GLenum, shaderCode: []const u8) Handle {
    const handle = gl.glCreateShader(shaderType);

    const size: c_int = @intCast(shaderCode.len);
    gl.glShaderSource(handle, 1, &shaderCode.ptr, &size);
    gl.glCompileShader(handle);

    return handle;
}

pub const ProgramError = error{
    VertexShaderError,
    FragmentShaderError,
    LinkError,
};

pub const Program = struct {
    const Self = @This();
    handle: Handle,

    pub fn init(vertShaderCode: []const u8, fragShaderCode: []const u8) ProgramError!Self {
        const vshader = compileShader(gl.GL_VERTEX_SHADER, vertShaderCode);
        if (!isShaderCompiled(vshader)) {
            return error.VertexShaderError;
        }

        const fshader = compileShader(gl.GL_FRAGMENT_SHADER, fragShaderCode);
        if (!isShaderCompiled(fshader)) {
            return error.FragmentShaderError;
        }

        const handle = gl.glCreateProgram();
        gl.glAttachShader(handle, vshader);
        gl.glAttachShader(handle, fshader);

        gl.glLinkProgram(handle);

        if (!isLinkedSuccessfuly(handle)) {
            return error.LinkError;
        }

        return Self{ .handle = handle };
    }

    pub fn use(self: Self) void {
        gl.glUseProgram(self.handle);
    }

    fn isLinkedSuccessfuly(handle: Handle) bool {
        var success: c_int = undefined;
        gl.glGetProgramiv(handle, gl.GL_LINK_STATUS, &success);

        return success > 0;
    }

    fn getErrorString(self: Self, buf: []const u8) void {
        gl.glGetProgramInfoLog(self.handle, buf.len, null, buf.ptr);
    }

    pub fn setUniform(self: Self, name: []const u8, val: i32) void {
        const loc = gl.glGetUniformLocation(self.handle, name.ptr);
        if (loc >= 0) {
            gl.glUniform1i(
                loc,
                val,
            );
        }
    }

    pub fn setUniformMatrix(self: Self, name: []const u8, matrix: zm.Mat4f) void {
        const loc = gl.glGetUniformLocation(self.handle, name.ptr);
        if (loc >= 0) {
            gl.glUniformMatrix4fv(
                loc,
                1,
                gl.GL_TRUE,
                @ptrCast(&matrix),
            );
        }
    }
};

pub const DrawingObject = struct {
    const Self = @This();
    vao: ArrayObject,
    vbo: BufferObject,
    texture: Texture,
    states: RenderStateFlags,

    pub fn init(buf: BufferObject, texture: Texture, states: RenderStateFlags) Self {
        const vao = ArrayObject.init();
        vao.bind();
        buf.bind();

        const flags = enums.values(VertexFormat);
        var i: gl.GLuint = 0;
        var offset: usize = 0;
        for (flags) |flag| {
            if (buf.format.contains(flag)) {
                const component_info = ComponentInfo.init(flag);
                const component_size = component_info.count * component_info.size;
                gl.glEnableVertexAttribArray(i);
                gl.glVertexAttribPointer(i, component_info.count, component_info.ctype, gl.GL_FALSE, buf.vertex_size, @ptrFromInt(offset));

                info("vertex attrib index: {d}, offset: {d}", .{ i, offset });

                offset += @intCast(component_size);
                i += 1;
            }
        }
        ArrayObject.unbind();

        return Self{
            .vao = vao,
            .vbo = buf,
            .texture = texture,
            .states = states,
        };
    }

    pub fn drawBegin(self: Self) void {
        self.states.enable(true);
    }

    pub fn drawEnd(self: Self) void {
        self.states.enable(false);
    }

    pub fn draw(self: Self) void {
        self.vao.bind();
        self.texture.bind();

        gl.glDrawArrays(gl.GL_TRIANGLES, 0, @intCast(self.vbo.vertices));

        ArrayObject.unbind();
    }
};

pub const Texture = struct {
    const Self = @This();
    handle: Handle,

    pub fn init(buf: []const u8, width: i32, height: i32, components: u32) Self {
        std.log.debug("Texture init w {d}, h {d}, components {d}", .{ width, height, components });

        var handle: Handle = undefined;
        gl.glGenTextures(1, &handle);
        gl.glBindTexture(gl.GL_TEXTURE_2D, handle);
        gl.glPixelStorei(gl.GL_UNPACK_ALIGNMENT, 1);
        const format: u32 = switch (components) {
            1 => gl.GL_RED,
            3 => gl.GL_RGB,
            4 => gl.GL_RGBA,
            else => unreachable,
        };

        gl.glTexImage2D(
            gl.GL_TEXTURE_2D,
            0,
            @intCast(format),
            width,
            height,
            0,
            format,
            gl.GL_UNSIGNED_BYTE,
            buf.ptr,
        );

        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);

        //gl.glGenerateMipmap(gl.GL_TEXTURE_2D);
        info("texture created, width: {d}, height: {d}, components: {d}", .{ width, height, components });
        return Self{
            .handle = handle,
        };
    }

    pub fn deinit(self: *Self) void {
        gl.glDeleteTextures(1, self.handle);
        self.handle = 0;
    }

    fn bind(self: Self) void {
        //gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.handle);
    }
};
