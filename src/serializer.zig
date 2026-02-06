const std = @import("std");
const yaml = @import("yaml");
const Yaml = @import("yaml").Yaml;
const Allocator = std.mem.Allocator;
pub const CurrentSerializer = YamlSerializer;

pub fn Serializer(comptime S: type) type {
    return struct {
        const Self = @This();
        saveFunc: ?*const fn (Allocator, *const S) []u8 = null,
        loadFunc: ?*const fn (Allocator, []const u8) S = null,

        pub fn init(comptime T: type) Self {
            const gen = struct {
                fn save(arena: Allocator, map_data: *const S) []u8 {
                    return T.save(arena, map_data);
                }

                fn load(arena: Allocator, data: []const u8) S {
                    return T.load(arena, data);
                }
            };

            return .{
                .saveFunc = gen.save,
                .loadFunc = gen.load,
            };
        }

        pub fn save(self: Self, gpa: Allocator, map_data: *const S) []u8 {
            if (self.saveFunc) |saveFunc| {
                return saveFunc(gpa, map_data);
            }
            unreachable;
        }

        pub fn load(self: Self, gpa: Allocator, data: []const u8) S {
            if (self.loadFunc) |loadFunc| {
                return loadFunc(gpa, data);
            }
            unreachable;
        }
    };
}

pub fn YamlSerializer(comptime S: type) type {
    return struct {
        const Self = @This();

        fn load(gpa: Allocator, data: []const u8) S {
            var doc = Yaml{ .source = data };
            doc.load(gpa) catch {
                unreachable;
            };
            defer doc.deinit(gpa);

            const map_data = doc.parse(gpa, S) catch unreachable;

            return map_data;
        }

        fn save(gpa: Allocator, map_data: *const S) []u8 {
            var body = std.Io.Writer.Allocating.init(gpa);
            defer body.deinit();
            yaml.stringify(
                gpa,
                map_data.*,
                &body.writer,
            ) catch unreachable;
            return body.toOwnedSlice() catch unreachable;
        }
    };
}
