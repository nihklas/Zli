const std = @import("std");
const Allocator = std.mem.Allocator;

const Error = error{
    UnrecognizedOption,
    IndexOOB,
    TypeError,
    MissingOptionName,
    MissingOptionValue,
    NotAFlag,
};

pub fn Parser(def: anytype) type {
    // TODO: more advanced schema check
    // maybe even turn it into a library

    if (!@hasField(@TypeOf(def), "options")) {
        @compileError("No options defined. If this command doesn't have options, pass an empty struct.");
    }

    if (!@hasField(@TypeOf(def), "arguments")) {
        @compileError("No arguments defined. If this command doesn't have arguments, pass an empty struct.");
    }

    const Options = MakeOptions(def.options);
    const Arguments = MakeArguments(def.arguments);
    // TODO: Add sorted Arguments to optimize positional argument setting

    return struct {
        const Self = @This();

        options: Options,
        arguments: Arguments,
        extra_args: [][]const u8,
        alloc: Allocator,
        args: [][:0]u8,
        current_arg: usize,

        pub fn init(alloc: Allocator) !Self {
            return .{
                .arguments = .{},
                .options = .{},
                .extra_args = &.{},
                .alloc = alloc,
                .args = try std.process.argsAlloc(alloc),
                .current_arg = 1, // start at 1 because at 0 is program name
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

            while (self.current_arg < self.args.len) : (self.current_arg += 1) {
                const arg = self.args[self.current_arg];

                if (std.mem.startsWith(u8, arg, "--")) {
                    if (arg.len == 2) {
                        return Error.MissingOptionName;
                    }
                    const equal_index = std.mem.indexOf(u8, arg, "=");
                    const name = if (equal_index) |index| arg[2..index] else arg[2..];
                    const value = try self.getValue(name);
                    try self.setOption(name, value);
                    continue;
                }

                if (arg[0] == '-') {
                    if (arg.len == 1) {
                        return Error.MissingOptionName;
                    }

                    if (arg.len == 2) {
                        const long_name = try getOptionFromShort(arg[1]);
                        const value = try self.getValue(long_name);
                        try self.setOption(long_name, value);
                        continue;
                    }

                    for (arg[1..]) |shorthand| {
                        const long_name = try getOptionFromShort(shorthand);
                        if (!try isFlag(long_name)) {
                            return Error.NotAFlag; // Combining multiple shorthands can is only possible for flags
                        }
                        try self.setOption(long_name, "true");
                    }
                    continue;
                }

                // Everything else will be interpreted as an extra argument
                self.setArgument(current_argument, arg) catch |err| switch (err) {
                    Error.IndexOOB => try extra_args.append(arg),
                    else => return err,
                };
                current_argument += 1;
            }

            self.extra_args = try extra_args.toOwnedSlice();
        }

        fn getValue(self: *Self, name: []const u8) Error![]const u8 {
            const arg = self.args[self.current_arg];
            const equal_index = std.mem.indexOf(u8, arg, "=");
            if (try isFlag(name)) {
                return "true";
            }

            if (equal_index) |index| {
                return arg[index + 1 ..];
            }

            if (self.current_arg + 1 < self.args.len) {
                if (self.args[self.current_arg + 1][0] != '-') {
                    self.current_arg += 1;
                    return self.args[self.current_arg];
                }
            }

            return Error.MissingOptionValue;
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

        pub fn help(self: *Self, writer: anytype) !void {
            const program_name = try programName(self.alloc);
            defer self.alloc.free(program_name);

            const options = std.meta.fields(Options);
            const arguments = sortedArguments();

            try writer.print("USAGE: {s}", .{program_name});
            if (options.len > 0) {
                try writer.print(" [OPTIONS]", .{});
            }
            if (arguments.len > 0) {
                inline for (arguments) |field| {
                    try writer.print(" <{s}>", .{field.name});
                }
            }
            try writer.writeByte('\n');

            // TODO: Add "=<VALUE>" if Value is needed, with 'VALUE' being the datatype
            if (arguments.len > 0) {
                try writer.print("\n", .{});
                try writer.print("ARGUMENTS:\n", .{});

                inline for (arguments) |field| {
                    const arg = @field(def.arguments, field.name);
                    try writer.print("    {s: <25}", .{field.name});
                    if (@hasField(@TypeOf(arg), "desc")) {
                        try writer.print("{s}", .{arg.desc});
                    }
                    try writer.writeByte('\n');
                }
            }

            if (options.len > 0) {
                try writer.print("\n", .{});
                try writer.print("OPTIONS:\n", .{});

                inline for (options) |field| {
                    const option = @field(def.options, field.name);
                    if (@hasField(@TypeOf(option), "short")) {
                        try writer.print("    --{s}, -{c}", .{ field.name, option.short });
                        for (0..(19 - field.name.len)) |_| {
                            try writer.print(" ", .{});
                        }
                    } else {
                        try writer.print("    --{s}", .{field.name});
                        for (0..(23 - field.name.len)) |_| {
                            try writer.print(" ", .{});
                        }
                    }
                    if (@hasField(@TypeOf(option), "desc")) {
                        try writer.print("{s}", .{option.desc});
                    }
                    try writer.writeByte('\n');
                }
            }
        }

        fn sortedArguments() []std.builtin.Type.StructField {
            const arguments = std.meta.fields(Arguments);
            var sorted: [arguments.len]std.builtin.Type.StructField = undefined;
            var index_filled: [arguments.len]bool = .{false} ** arguments.len;

            for (arguments) |field| {
                const arg = @field(def.arguments, field.name);
                if (!@hasField(@TypeOf(arg), "pos")) {
                    // TODO: Move to schema validation
                    @compileError(std.fmt.comptimePrint("Argument '{s}' is missing field .pos", .{field.name}));
                }

                const idx = arg.pos - 1;
                if (index_filled[idx]) {
                    // TODO: Move to schema validation
                    @compileError(std.fmt.comptimePrint("Argument position '{d}' exists multiple time", .{arg.pos}));
                }

                sorted[idx] = field;
                index_filled[idx] = true;
            }

            return sorted[0..];
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

fn programName(alloc: Allocator) ![]const u8 {
    const path = try std.fs.selfExePathAlloc(alloc);
    defer alloc.free(path);
    return try alloc.dupe(u8, std.fs.path.basename(path));
}
