const std = @import("std");
const Allocator = std.mem.Allocator;

const Error = error{
    UnrecognizedOption,
};

pub fn Parser(def: anytype) type {
    const Options = if (@hasField(@TypeOf(def), "options")) MakeOptions(def.options) else struct {};

    return struct {
        const Self = @This();

        options: Options,
        parsed: bool,
        alloc: Allocator,
        args: std.process.ArgIterator,

        pub fn init(alloc: Allocator) !Self {
            return .{
                .options = .{},
                .parsed = false,
                .alloc = alloc,
                .args = try std.process.argsWithAllocator(alloc),
            };
        }

        pub fn parse(self: *Self) !void {
            _ = self.args.skip(); // Skip program name
            while (self.args.next()) |arg| {
                if (std.mem.startsWith(u8, arg, "--")) {
                    const arg_name = arg[2..];
                    std.debug.print("arg: {s}\n", .{arg_name});
                    // if (!self.setOption(arg_name, true)) {
                    //     return Error.UnrecognizedOption;
                    // }
                }
            }
            self.parsed = true;
        }

        pub fn deinit(self: *Self) void {
            self.args.deinit();
            self.* = undefined;
        }

        fn setOption(self: *Self, name: []const u8, value: anytype) bool {
            inline for (std.meta.fields(Options)) |field| {
                if (std.mem.eql(u8, field.name, name)) {
                    @field(self.options, field.name) = value;
                    return true;
                }
            }

            return false;
        }
    };
}

fn MakeOptions(options: anytype) type {
    const option_typedef = @TypeOf(options);
    const option_fields = std.meta.fields(option_typedef);
    var fields: [option_fields.len]std.builtin.Type.StructField = undefined;

    for (option_fields, 0..) |field, i| {
        const option = @field(options, field.name);
        const field_type = option.type;

        if (@hasField(@TypeOf(option), "default")) {
            const default_type_info = @typeInfo(@TypeOf(option.default));
            const field_type_info = @typeInfo(field_type);
            const can_cast = switch (default_type_info) {
                .comptime_int => field_type_info == .int,
                .comptime_float => field_type_info == .float,
                else => std.mem.eql(u8, @tagName(std.meta.activeTag(field_type_info)), @tagName(std.meta.activeTag(default_type_info))),
            };

            if (!can_cast) {
                @compileError(std.fmt.comptimePrint("Default value '{any}' is a different type than option '{s}' expects. Expected '{}' got '{}'.", .{ option.default, field.name, field_type, @TypeOf(option.default) }));
            }
            fields[i] = makeField(field.name, field_type, option.default);
        } else {
            const optional_type = @Type(std.builtin.Type{ .optional = .{ .child = field_type } });
            fields[i] = makeField(field.name, optional_type, null);
        }
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

fn makeField(name: [:0]const u8, field_type: type, default: field_type) std.builtin.Type.StructField {
    return .{
        .name = name,
        .type = field_type,
        .default_value = &@as(field_type, default),
        .is_comptime = false,
        .alignment = @alignOf(field_type),
    };
}
