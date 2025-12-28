const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{NoTypeNameForIndex};
pub fn TypeIdData(comptime T: type, comptime Space: type) type {
    return struct {
        index: u32 = std.math.maxInt(u32),
        flag: u32 = 0,
        comptime type_name: [:0]const u8 = prettyTypeName(T),
        comptime space: Space = .{},
    };
}

pub fn CreateTypeIndexing(comptime Space: type) type {
    return struct {
        const Self = @This();
        const Info = struct {
            index: u32,
            flag: u32,
            name: [:0]const u8,
        };
        var counter: u32 = 0;
        var type_info: std.ArrayList(Info) = .empty;

        fn innerTypeId(comptime T: type) *TypeIdData(T, Space) {
            return &struct {
                comptime {
                    _ = struct { T, Space };
                }
                var id: TypeIdData(T, Space) = .{};
            }.id;
        }

        pub fn typeIndex(comptime T: type) u32 {
            return innerTypeId(T).index;
        }

        pub fn deinit(gpa: Allocator) void {
            type_info.deinit(gpa);
        }

        pub fn initTypeIndex(comptime T: type, gpa: Allocator) u32 {
            const index_ptr = &innerTypeId(T).index;
            if (index_ptr.* < std.math.maxInt(u32)) {
                return index_ptr.*;
            }

            const index = Self.counter;
            Self.counter += 1;
            index_ptr.* = index;
            const flag_ptr = &innerTypeId(T).flag;
            flag_ptr.* = std.math.pow(u32, 2, index);

            type_info.insert(gpa, index, .{
                .index = index,
                .flag = innerTypeId(T).flag,
                .name = innerTypeId(T).type_name,
            }) catch unreachable;

            return index;
        }

        pub fn getTypeFlag(comptime T: type) u32 {
            return innerTypeId(T).flag;
        }

        pub fn getTypeFlags(comptime fields: []const type) u32 {
            var flags: [fields.len]u32 = undefined;
            inline for (0..fields.len) |index| {
                const field = fields[index];
                flags[index] = getTypeFlag(field);
            }

            var res: u32 = 0;
            for (flags) |flag| {
                res |= flag;
            }
            return res;
        }

        pub fn getTypeName(index: u32) ![:0]const u8 {
            if (index >= type_info.items.len) {
                return error.NoTypeNameForIndex;
            }
            return type_info.items[index].name;
        }

        pub fn getIndexByName(type_name: [:0]const u8) !u32 {
            for (type_info.items) |info| {
                if (std.mem.eql(u8, type_name, info.name)) {
                    return info.index;
                }
            }
            return error.NoTypeNameForIndex;
        }

        pub fn getInfoByName(type_name: [:0]const u8) !Info {
            for (type_info.items) |info| {
                if (std.mem.eql(u8, type_name, info.name)) {
                    return info;
                }
            }
            return error.NoTypeNameForIndex;
        }
    };
}

inline fn prettyTypeName(comptime ctype: type) [:0]const u8 {
    const name = @typeName(ctype); //std.fmt.comptimePrint("elem_{d}", .{i});
    if (std.mem.lastIndexOf(u8, name, ".")) |index| {
        return name[index + 1 .. :0];
    }
    return "";
}
