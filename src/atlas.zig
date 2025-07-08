const std = @import("std");
const TrueType = @import("TrueType");
const opengl = @import("opengl.zig");
const Image = @import("zigimg").Image;
const PixelFormat = @import("zigimg").PixelFormat;

const MapBufferError = error{
    XOutOfRange,
    YOutOfRange,
    FreeRectNotFound,
} || anyerror;

pub const Rect = struct {
    const Self = @This();
    x: u16,
    y: u16,
    w: u16,
    h: u16,
    off_x: i16 = 0,
    off_y: i16 = 0,
    scale: f32 = 0,
    hmet: TrueType.HMetrics = .{ .advance_width = 0, .left_side_bearing = 0 },

    fn print(self: Self) void {
        std.log.debug("Rect( x = {d} y = {d} w = {d} h = {d} )", .{ self.x, self.y, self.w, self.h });
    }

    pub fn getPosition(self: Self) struct { x: f32, y: f32 } {
        return .{
            .x = @as(f32, @floatFromInt(self.x)),
            .y = @as(f32, @floatFromInt(self.y)),
        };
    }

    pub fn getSize(self: Self) struct { w: f32, h: f32 } {
        return .{
            .w = @as(f32, @floatFromInt(self.w)),
            .h = @as(f32, @floatFromInt(self.h)),
        };
    }

    pub fn makeQuad(self: Self, tw: f32, th: f32, pos_x: f32, pos_y: f32, scale: f32, out_data: []opengl.Vertex3T) void {
        const tpos = self.getPosition();
        const rect_size = self.getSize();
        const ou: f32 = tpos.x / tw;
        const ov: f32 = tpos.y / th;
        const u = ou + (rect_size.w / tw);
        const v = ov + (rect_size.h / th);
        const x0: f32 = pos_x;
        const y0: f32 = pos_y;
        const x1: f32 = x0 + rect_size.w * scale;
        const y1: f32 = y0 + rect_size.h * scale;

        // out_data.* = [6]opengl.Vertex3T{
        //     .{ .x = x0, .y = y0, .z = 0.0, .u = ou, .v = v },
        //     .{ .x = x1, .y = y0, .z = 0.0, .u = u, .v = v },
        //     .{ .x = x1, .y = y1, .z = 0.0, .u = u, .v = ov },

        //     .{ .x = x0, .y = y0, .z = 0.0, .u = ou, .v = v },
        //     .{ .x = x1, .y = y1, .z = 0.0, .u = u, .v = ov },
        //     .{ .x = x0, .y = y1, .z = 0.0, .u = ou, .v = ov },
        // };
        out_data[0] = .{ .x = x0, .y = y0, .z = 0.0, .u = ou, .v = v };
        out_data[1] = .{ .x = x1, .y = y0, .z = 0.0, .u = u, .v = v };
        out_data[2] = .{ .x = x1, .y = y1, .z = 0.0, .u = u, .v = ov };
        out_data[3] = .{ .x = x0, .y = y0, .z = 0.0, .u = ou, .v = v };
        out_data[4] = .{ .x = x1, .y = y1, .z = 0.0, .u = u, .v = ov };
        out_data[5] = .{ .x = x0, .y = y1, .z = 0.0, .u = ou, .v = ov };
    }

    pub fn hitTest(self: Self, x: u16, y: u16) bool {
        std.log.debug("hit test click pos {d} : {d}, rect {d} : {d}", .{ x, y, self.x, self.y });
        return x > self.x and x < (self.x + self.w) and y > self.y and y < (self.y + self.h);
    }
};
fn MakeMapBuffer(size: u32, cell_size: u16) type {
    if ((size % cell_size) != 0) {
        @compileError("Cell size must be divided without remainder from division");
    }

    return struct {
        const Self = @This();
        const Size: u32 = size;
        const MapSize: u16 = size / cell_size;
        const Cell: u16 = cell_size;
        const MaxCells = Self.MapSize * Self.MapSize;

        const BitArray = std.bit_set.ArrayBitSet(usize, MaxCells);

        texture: []u8,
        map: BitArray = BitArray.initEmpty(),

        fn init(gpa: std.mem.Allocator) std.mem.Allocator.Error!Self {
            const texture = try gpa.alloc(u8, Size * Size);
            for (0..(Size * Size)) |i| {
                texture[i] = 0;
            }

            return Self{
                .texture = texture,
            };
        }

        fn deinit(self: Self, gpa: std.mem.Allocator) void {
            gpa.free(self.texture);
        }

        fn iterateRegion(map: *BitArray, cols: u16, rows: u16, x: usize, y: usize, func: *const fn (*BitArray, usize, usize) bool) bool {
            const xEnd = x + cols;
            const yEnd = y + rows;
            var all = true;

            outer: for (y..yEnd) |j| {
                for (x..xEnd) |i| {
                    if (!func(map, i, j)) {
                        all = false;
                        break :outer;
                    }
                }
            }
            return all;
        }

        fn isFreeCell(map: *BitArray, x: usize, y: usize) bool {
            if (x >= MapSize or y >= MapSize) {
                return false;
            }

            const index = x + y * MapSize;
            if (index >= MaxCells) {
                return false;
            }

            if (map.isSet(index)) {
                return false;
            }

            return true;
        }

        fn markCell(map: *BitArray, x: usize, y: usize) bool {
            if (x >= MapSize or y >= MapSize) {
                return false;
            }
            const index = x + y * MapSize;

            if (index >= Self.MaxCells) {
                return false;
            }

            map.set(index);

            return true;
        }

        fn findFreeSpace(self: *Self, w: u16, h: u16) MapBufferError!Rect {
            const cols = try std.math.divCeil(u16, w, Self.Cell);
            const rows = try std.math.divCeil(u16, h, Self.Cell);

            for (0..MapSize) |y| {
                for (0..MapSize) |x| {
                    const index = x + y * MapSize;
                    std.debug.assert(index < MaxCells);
                    if (self.map.isSet(index)) {
                        continue;
                    }

                    if (iterateRegion(&self.map, cols, rows, x, y, &isFreeCell)) {
                        if (!iterateRegion(&self.map, cols, rows, x, y, &markCell)) {
                            unreachable;
                        }
                        return .{
                            .x = @as(u16, @intCast(x)),
                            .y = @as(u16, @intCast(y)),
                            .w = cols,
                            .h = rows,
                        };
                    }
                }
            }
            std.log.debug("end findFreeSpace {d};{d} => {d};{d}", .{ w, h, cols, rows });
            return error.MapBufferError;
        }

        fn add(self: *Self, width: u16, height: u16, pixels: []u8) MapBufferError!Rect {
            const rect = try self.findFreeSpace(width, height);
            const x = @as(usize, rect.x) * Cell;
            const y = @as(usize, rect.y) * Cell;
            const w = rect.w * Cell;
            const h = rect.h * Cell;

            for (0..height) |j| {
                for (0..width) |i| {
                    const index = (x + i) + (y + j) * Size;
                    self.texture[index] = pixels[j * width + i];
                }
            }

            return .{
                .x = @truncate(x),
                .y = @truncate(y),
                .w = w,
                .h = h,
            };
        }
    };
}

pub const Atlas = struct {
    const Self = @This();
    //texture_data: []u8,
    texture_width: u32,
    texture_height: u32,
    texture: opengl.Texture,
    rects: []Rect,
    symbol_base: u32,

    pub fn initFromFont(gpa: std.mem.Allocator, from: u32, count: u32, fontData: []u8) !Self {
        const ttf = TrueType.load(fontData) catch {
            return error.FailedInitFont;
        };

        var buffer: std.ArrayListUnmanaged(u8) = .empty;
        defer buffer.deinit(gpa);
        const MapBuffer = MakeMapBuffer(512, 8);
        var map = try MapBuffer.init(gpa);
        defer map.deinit(gpa);

        const scale = ttf.scaleForPixelHeight(30);
        std.log.debug("font scale {d}", .{scale});
        const end: u32 = from + count;
        const rects = try gpa.alloc(Rect, count);
        errdefer gpa.free(rects);
        var max_y: u16 = 0;
        for (from..end) |codepoint| {
            if (ttf.codepointGlyphIndex(@intCast(codepoint))) |glyph| {
                buffer.clearRetainingCapacity();

                if (ttf.glyphBitmap(
                    gpa,
                    &buffer,
                    glyph,
                    scale,
                    scale,
                )) |dims| {
                    const rect = try map.add(dims.width, dims.height, buffer.items);
                    rect.print();

                    const index = codepoint - from;
                    rects[index] = .{
                        .x = rect.x,
                        .y = rect.y,
                        .w = rect.w,
                        .h = rect.h,
                        .off_x = dims.off_x,
                        .off_y = dims.off_y,
                        .scale = scale,
                        .hmet = ttf.glyphHMetrics(glyph),
                    };
                    const off_y = rect.y + rect.h;
                    if (max_y < off_y) {
                        max_y = off_y;
                    }
                } else |_| {
                    const index = codepoint - from;
                    rects[index] = .{
                        .x = 0,
                        .y = 0,
                        .w = 0,
                        .h = 0,
                        .off_x = 0,
                        .off_y = 0,
                        .scale = scale,
                        .hmet = ttf.glyphHMetrics(glyph),
                    };
                }
            } else {
                std.log.debug("codepointGlyphIndex {d}: none", .{codepoint});
            }
        }

        std.log.debug("Max y {d}", .{max_y});
        var height: u32 = 1;
        while (height < max_y) {
            height *= 2;
        }

        const texture_data = if (height < MapBuffer.Size)
            try gpa.alloc(u8, MapBuffer.Size * height)
        else
            try gpa.alloc(u8, MapBuffer.Size * MapBuffer.Size);
        defer gpa.free(texture_data);

        for (0..texture_data.len) |index| {
            texture_data[index] = map.texture[index];
        }

        const font_texture = opengl.Texture.init(
            texture_data,
            MapBuffer.Size,
            @intCast(height),
            1,
        );

        return .{
            .texture_width = MapBuffer.Size,
            .texture_height = height,
            .texture = font_texture,
            .rects = rects,
            .symbol_base = from,
        };
    }

    pub fn initGreed(gpa: std.mem.Allocator, image: *Image, cell_w: u16, cell_h: u16) !Self {
        const width: u32 = @intCast(image.width);
        const height: u32 = @intCast(image.height);

        const cols = try std.math.divCeil(u32, width, cell_w);
        const rows = try std.math.divCeil(u32, height, cell_h);
        const fmt_name = std.enums.tagName(PixelFormat, image.pixelFormat()).?;
        std.log.debug("cols {d}, rows {d}, pixel format {s}", .{ cols, rows, fmt_name });
        const rects = try gpa.alloc(Rect, cols * rows);

        for (0..rows) |y| {
            for (0..cols) |x| {
                rects[x + y * cols] = .{
                    .x = @as(u16, @intCast(x)) * cell_w,
                    .y = @as(u16, @intCast(y)) * cell_h,
                    .w = cell_w,
                    .h = cell_h,
                };
            }
        }

        if (image.pixelFormat().isIndexed()) {
            try image.convert(.rgba32);
        }

        const texture = opengl.Texture.init(
            image.rawBytes(),
            @intCast(width),
            @intCast(height),
            image.pixelFormat().channelCount(),
        );

        return .{
            .texture_width = width,
            .texture_height = height,
            .texture = texture,
            .rects = rects,
            .symbol_base = 0,
        };
    }

    pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
        gpa.free(self.rects);
    }

    pub fn getTexture(self: Self) opengl.Texture {
        return self.texture;
    }

    pub fn getTextureSize(self: Self) struct { w: f32, h: f32 } {
        return .{ .w = @floatFromInt(self.texture_width), .h = @floatFromInt(self.texture_height) };
    }

    pub fn getSymbolRect(self: Self, s: u8) Rect {
        const index = @as(u32, s) - self.symbol_base;
        std.debug.assert(index < self.rects.len);
        return self.rects[index];
    }
};
