const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Parser(options: anytype) type {
    const Options = MakeOptions(options);

    return struct {
        const Self = @This();

        options: Options,
        parsed: bool,
        alloc: Allocator,
        args: []const [:0]u8 = undefined,

        pub fn init(alloc: Allocator) !Self {
            return .{
                .options = .{},
                .parsed = false,
                .alloc = alloc,
                .args = try std.process.argsAlloc(alloc),
            };
        }

        pub fn parse(self: *Self) !void {
            _ = self;
        }

        pub fn deinit(self: *Self) void {
            std.process.argsFree(self.alloc, self.args);
            self.* = undefined;
        }

        pub fn option(self: *Self, comptime name: []const u8) getOptionType(name) {
            return @field(self.options, name);
        }

        fn getOptionType(comptime name: []const u8) type {
            const fields = @typeInfo(Options).@"struct".fields;

            for (fields) |field| {
                if (std.mem.eql(u8, field.name, name)) {
                    return field.type;
                }
            }

            @compileError(std.fmt.comptimePrint("{s} is not an option", .{name}));
        }
    };
}

fn MakeOptions(options: anytype) type {
    const option_typedef = @TypeOf(options);
    const option_fields = std.meta.fields(option_typedef);
    var fields: [option_fields.len]std.builtin.Type.StructField = undefined;

    for (option_fields, 0..) |field, i| {
        const optional_type = @Type(std.builtin.Type{ .optional = .{ .child = field.type } });
        fields[i] = .{
            .name = field.name,
            .type = optional_type,
            .default_value = &@as(?field.type, null),
            .is_comptime = false,
            .alignment = @alignOf(optional_type),
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = fields[0..],
            .decls = &.{},
            .is_tuple = false,
        },
    });
}
