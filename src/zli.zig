const std = @import("std");
const Allocator = std.mem.Allocator;

const Error = error{
    UnrecognizedOption,
    IndexOOB,
    TypeError,
    MissingOptionName,
    NotAFlag,
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
        extra_args: [][]const u8,
        alloc: Allocator,
        args: [][:0]u8,

        pub fn init(alloc: Allocator) !Self {
            return .{
                .arguments = .{},
                .options = .{},
                .extra_args = &.{},
                .alloc = alloc,
                .args = try std.process.argsAlloc(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.extra_args.len > 0) {
                self.alloc.free(self.extra_args);
            }
            std.process.argsFree(self.alloc, self.args);
            self.* = undefined;
        }

        pub fn parse(self: *Self) !void {
            var current_argument: usize = 1;
            var extra_args = std.ArrayList([]const u8).init(self.alloc);
            defer extra_args.deinit();

            var idx: usize = 1; // 0 = program name
            while (idx < self.args.len) : (idx += 1) {
                const arg = self.args[idx];

                if (std.mem.startsWith(u8, arg, "--")) {
                    if (arg.len == 2) {
                        return Error.MissingOptionName;
                    }
                    const name = arg[2..];
                    const value = value: {
                        if (try isFlag(name)) {
                            break :value "true";
                        }

                        // TODO: get real value
                        // split on =
                        // if no = present, check next arg
                        break :value "test";
                    };
                    try self.setOption(name, value);
                    continue;
                }

                if (arg[0] == '-') {
                    if (arg.len == 1) {
                        return Error.MissingOptionName;
                    }
                    // TODO: Check for single short option with value
                    // if(arg.len == 2) -> get long name and extract option handling out to function
                    for (arg[1..]) |shorthand| {
                        const long_name = try getOptionFromShort(shorthand);
                        if (!try isFlag(long_name)) {
                            // TODO: Move this to comptime schema check
                            return Error.NotAFlag;
                        }

                        try self.setOption(long_name, "true");
                    }
                    continue;
                }

                // Everything else will likely be an argument
                self.setArgument(current_argument, arg) catch |err| switch (err) {
                    Error.IndexOOB => try extra_args.append(arg),
                    else => return err,
                };
                current_argument += 1;
            }

            self.extra_args = try extra_args.toOwnedSlice();
        }

        fn setOption(self: *Self, name: []const u8, value: []const u8) Error!void {
            inline for (std.meta.fields(Options)) |field| {
                const option_def = @field(def.options, field.name);
                if (std.mem.eql(u8, field.name, name)) {
                    @field(self.options, field.name) = try convertValue(option_def.type, value);
                    return;
                }
            }

            return Error.UnrecognizedOption;
        }

        fn isFlag(name: []const u8) Error!bool {
            inline for (std.meta.fields(Options)) |field| {
                const option_def = @field(def.options, field.name);
                if (std.mem.eql(u8, field.name, name)) {
                    return option_def.type == bool;
                }
            }

            return Error.UnrecognizedOption;
        }

        fn getOptionFromShort(shorthand: u8) Error![]const u8 {
            inline for (std.meta.fields(@TypeOf(def.options))) |option| {
                const option_def = @field(def.options, option.name);
                if (!@hasField(@TypeOf(option_def), "short")) {
                    continue;
                }

                if (option_def.short == shorthand) {
                    return option.name;
                }
            }

            return Error.UnrecognizedOption;
        }

        fn optionExists(name: []const u8) bool {
            return @hasField(Options, name);
        }

        fn setArgument(self: *Self, index: usize, value: []const u8) Error!void {
            const fields = std.meta.fields(Arguments);

            if (index > fields.len) {
                return Error.IndexOOB;
            }

            inline for (fields) |field| {
                const argument_def = @field(def.arguments, field.name);
                if (argument_def.pos == index) {
                    @field(self.arguments, field.name) = try convertValue(argument_def.type, value);
                    return;
                }
            }
        }
    };
}

fn convertValue(target: type, value: []const u8) Error!target {
    return switch (@typeInfo(target)) {
        .int => std.fmt.parseInt(target, value, 0) catch return Error.TypeError,
        .float => std.fmt.parseFloat(target, value) catch return Error.TypeError,
        .bool => value.len > 0,
        .pointer => value,
        else => unreachable,
    };
}

fn MakeOptions(options: anytype) type {
    const option_typedef = @TypeOf(options);
    const option_fields = std.meta.fields(option_typedef);
    var fields: [option_fields.len]std.builtin.Type.StructField = undefined;

    for (option_fields, 0..) |field, i| {
        const option = @field(options, field.name);
        const field_type = option.type;

        if (!isAllowedType(@typeInfo(field_type))) {
            @compileError(std.fmt.comptimePrint("Type of option '{s}' must be one of {{ bool, int, float, []const u8 }}, found: '{}'", .{ field.name, field_type }));
        }

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

        if (!isAllowedType(@typeInfo(field_type))) {
            @compileError(std.fmt.comptimePrint("Type of argument '{s}' must be one of {{ bool, int, float, []const u8 }}, found: '{}'", .{ field.name, field_type }));
        }

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

fn isAllowedType(check: std.builtin.Type) bool {
    return check == .bool or check == .int or check == .float or isString(check);
}

fn isString(check: std.builtin.Type) bool {
    return check == .pointer and check.pointer.size == .Slice and check.pointer.child == u8 and check.pointer.is_const;
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
