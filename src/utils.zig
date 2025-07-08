const std = @import("std");

fn len(comptime E: type) usize {
    return @typeInfo(E).@"enum".fields.len;
}

/// Looks up the supplied fields in the given enum type.
/// Uses only the field names, field values are ignored.
/// The result array is in the same order as the input.
pub inline fn valuesFromFields(comptime E: type, comptime fields: []const std.builtin.Type.EnumField) [len(E)]E {
    comptime {
        var result: [fields.len]E = undefined;
        for (&result, fields) |*r, f| {
            r.* = @enumFromInt(f.value);
        }
        const final = result;
        return &final;
    }
}

pub inline fn intValuesFromFields(comptime E: type, comptime fields: []const std.builtin.Type.EnumField) [len(E)]u32 {
    comptime {
        var result: [fields.len]u32 = undefined;
        for (&result, fields) |*r, f| {
            r.* = f.value;
        }
        return result;
    }
}

/// Returns the set of all named values in the given enum, in
/// declaration order.
pub fn values(comptime E: type) [len(E)]E {
    return comptime valuesFromFields(E, @typeInfo(E).@"enum".fields);
}

pub fn intValues(comptime E: type) [len(E)]u32 {
    return comptime intValuesFromFields(E, @typeInfo(E).@"enum".fields);
}

pub fn flags(comptime x: anytype) u32 {
    // Get type info.
    const info = @typeInfo(@TypeOf(x));
    // Check if it's a tuple.
    if (info != .Struct) @panic("Not a tuple!");
    if (!info.Struct.is_tuple) @panic("Not a tuple!");
    // Do stuff...
    var res: u32 = 0;
    inline for (x) |field| res |= @intCast(field);

    return res;
}

pub fn readFileData(gpa: std.mem.Allocator, file_path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    var stream = std.io.StreamSource{ .file = file };
    return try stream.reader().readAllAlloc(gpa, std.math.maxInt(usize));
}

pub fn writeFileData(file_path: []const u8, bytes: []const u8) !void {
    var file = try std.fs.cwd().openFile(file_path, .{ .mode = .write_only });
    defer file.close();

    var stream = std.io.StreamSource{ .file = file };
    _ = try stream.write(bytes);
}
