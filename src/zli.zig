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

    const shorthands = optionShorthands(def.options);
    _ = shorthands;

    return struct {
        const Self = @This();

        options: Options,
        arguments: Arguments,
        extra_args: [][]const u8,
        parsed: bool,
        alloc: Allocator,
        args: std.process.ArgIterator,

        pub fn init(alloc: Allocator) !Self {
            return .{
                .arguments = .{},
                .options = .{},
                .extra_args = undefined,
                .parsed = false,
                .alloc = alloc,
                .args = try std.process.argsWithAllocator(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            self.alloc.free(self.extra_args);
            self.args.deinit();
            self.* = undefined;
        }

        pub fn parse(self: *Self) !void {
            _ = self.args.skip(); // Skip program name
            var current_argument: usize = 1;
            var extra_args = std.ArrayList([]const u8).init(self.alloc);
            defer extra_args.deinit();

            while (self.args.next()) |arg| {
                // '--' -> long option
                // else '-' -> short option(s)
                // else -> argument / done

                if (std.mem.startsWith(u8, arg, "--")) {
                    // TODO:
                    // handle boolean flag
                    // handle splitting on =
                    // handle next arg if value expected
                    continue;
                }

                if (arg[0] == '-') {
                    // TODO:
                    continue;
                }

                self.setArgument(current_argument, arg) catch |err| switch (err) {
                    error.IndexOutOfBounds => try extra_args.append(arg),
                    else => return err,
                };
                current_argument += 1;
            }

            self.extra_args = try extra_args.toOwnedSlice();

            self.parsed = true;
        }

        fn setOption(self: *Self, name: []const u8, value: []const u8) bool {
            inline for (std.meta.fields(Options)) |field| {
                if (std.mem.eql(u8, field.name, name)) {
                    @field(self.options, field.name) = value;
                    return true;
                }
            }

            return false;
        }

        fn setArgument(self: *Self, index: usize, value: []const u8) error{ TypeError, IndexOutOfBounds }!void {
            const fields = std.meta.fields(Arguments);

            if (index > fields.len) {
                return error.IndexOutOfBounds;
            }

            inline for (fields) |field| {
                const argument_def = @field(def.arguments, field.name);
                if (argument_def.pos == index) {
                    const converted = switch (@typeInfo(argument_def.type)) {
                        .int => std.fmt.parseInt(argument_def.type, value, 0) catch return .TypeError,
                        .pointer => value,
                        else => unreachable,
                    };

                    @field(self.arguments, field.name) = converted;
                    return;
                }
            }
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

fn optionShorthands(options: anytype) std.StaticStringMap([]const u8) {
    const option_typedef = @TypeOf(options);
    const option_fields = std.meta.fields(option_typedef);
    var shorthands: [option_fields.len]std.meta.Tuple(&.{ []const u8, []const u8 }) = undefined;

    var shorts_count: usize = 0;
    for (option_fields) |field| {
        const option = @field(options, field.name);
        if (!@hasField(@TypeOf(option), "short")) {
            continue;
        }

        shorthands[shorts_count] = .{ &[1]u8{option.short}, field.name };
        shorts_count += 1;
    }

    return std.StaticStringMap([]const u8).initComptime(shorthands[0..shorts_count]);
}
