const std = @import("std");
const Allocator = std.mem.Allocator;

const Error = error{
    UnrecognizedOption,
};

pub fn Parser(def: anytype) type {
    if (!@hasField(@TypeOf(def), "options")) {
        @compileError("No options defined. If this command doesn't have options, pass an empty struct.");
    }

    if (!@hasField(@TypeOf(def), "arguments")) {
        @compileError("No arguments defined. If this command doesn't have arguments, pass an empty struct.");
    }

    const Options = MakeOptions(def.options);
    const Arguments = MakeArguments(def.arguments);

    return struct {
        const Self = @This();

        options: Options,
        arguments: Arguments,
        parsed: bool,
        alloc: Allocator,
        args: std.process.ArgIterator,

        pub fn init(alloc: Allocator) !Self {
            return .{
                .arguments = .{},
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
            fields[i] = makeField(field.name, field_type, @as(field_type, option.default));
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

fn MakeArguments(arguments: anytype) type {
    const argument_typedef = @TypeOf(arguments);
    const argument_fields = std.meta.fields(argument_typedef);
    var fields: [argument_fields.len]std.builtin.Type.StructField = undefined;

    for (argument_fields, 0..) |field, i| {
        const argument = @field(arguments, field.name);
        const field_type = argument.type;
        const optional_type = @Type(std.builtin.Type{ .optional = .{ .child = field_type } });
        fields[i] = makeField(field.name, optional_type, null);
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
