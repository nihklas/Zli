const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn generateParser(output_file_path: []const u8, alloc: Allocator, def: anytype) !void {
    // TODO: Complete schema checking of def

    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        std.debug.print("unable to open '{s}': {s}", .{ output_file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer output_file.close();

    try output_file.writeAll(
        \\const std = @import("std");
        \\const Allocator = std.mem.Allocator;
        \\
        \\const Self = @This();
        \\
        \\const Error = error{
        \\    TypeError,
        \\    UnknownOption,
        \\    MissingValue,
        \\};
        \\
        \\
    );

    try output_file.writeAll(try getArgumentStruct(def.arguments, alloc));
    try output_file.writeAll(try getOptionsStruct(def.options, alloc));

    // TODO: generate help text as plain string attribute '.help'
    try output_file.writeAll(
        \\extra_args: [][]const u8 = &.{},
        \\args: ?[][:0]u8 = null,
        \\alloc: Allocator,
        \\
        \\pub fn init(alloc: Allocator) Self {
        \\    return .{
        \\        .alloc = alloc,
        \\    };
        \\}
        \\
        \\pub fn deinit(self: *Self) void {
        \\    if (self.args) |args| {
        \\        std.process.argsFree(self.alloc, args);
        \\    }
        \\    self.alloc.free(self.extra_args);
        \\}
        \\
        \\pub fn parse(self: *Self) !void {
        \\    const args = try std.process.argsAlloc(self.alloc);
        \\    self.args = args;
        \\
        \\    var extra_args: std.ArrayList([]const u8) = .init(self.alloc);
        \\    defer extra_args.deinit();
        \\
        \\    var idx: usize = 1;
        \\    var arguments_found: usize = 0;
        \\    while (idx < args.len) : (idx += 1) {
        \\        const arg = args[idx];
        \\
        \\        if (std.mem.startsWith(u8, arg, "--")) {
        \\            idx = try self.parseLongOption(idx, args);
        \\            continue;
        \\        }
        \\
        \\        if (arg[0] == '-') {
        \\            try self.parseShortOptions(arg[1..]);
        \\            continue;
        \\        }
        \\
        \\        arguments_found = try self.parseArgument(arg, arguments_found, &extra_args);
        \\    }
        \\
        \\    self.extra_args = try extra_args.toOwnedSlice();
        \\}
        \\
        \\pub fn convertValue(target: type, value: []const u8) Error!target {
        \\    return switch (@typeInfo(target)) {
        \\        .int => std.fmt.parseInt(target, value, 0) catch return Error.TypeError,
        \\        .float => std.fmt.parseFloat(target, value) catch return Error.TypeError,
        \\        .bool => value.len > 0,
        \\        .pointer => value,
        \\        else => unreachable,
        \\    };
        \\}
        \\
    );

    try output_file.writeAll(try getArgumentParseFunc(def.arguments, alloc));
    try output_file.writeAll(try getLongOptionParseFunc(def.options, alloc));
    try output_file.writeAll(try getShortOptionParseFunc(def.options, alloc));
}

fn getArgumentStruct(arguments: anytype, alloc: Allocator) ![]const u8 {
    var fields: std.ArrayList([]const u8) = .init(alloc);
    const fields_def = std.meta.fields(@TypeOf(arguments));

    inline for (fields_def) |argument_field| {
        const type_def = @field(arguments, argument_field.name).type;
        try fields.append(std.fmt.comptimePrint("    {s}: ?{} = null,\n", .{ argument_field.name, type_def }));
    }

    const fields_array = try fields.toOwnedSlice();
    const fields_raw = try std.mem.concat(alloc, u8, fields_array);
    return std.fmt.allocPrint(alloc,
        \\arguments: struct {{
        \\{s}}} = .{{}},
        \\
    , .{fields_raw});
}

fn getOptionsStruct(options: anytype, alloc: Allocator) ![]const u8 {
    var fields: std.ArrayList([]const u8) = .init(alloc);
    const fields_def = std.meta.fields(@TypeOf(options));

    inline for (fields_def) |option_field| {
        const option = @field(options, option_field.name);
        const default: ?option.type = default: {
            if (@hasField(@TypeOf(option), "default")) {
                break :default option.default;
            }

            if (option.type == bool) {
                break :default false;
            }

            break :default null;
        };

        if (default) |default_val| {
            try fields.append(std.fmt.comptimePrint("    {s}: {} = {any},\n", .{ option_field.name, option.type, default_val }));
        } else {
            try fields.append(std.fmt.comptimePrint("    {s}: ?{} = null,\n", .{ option_field.name, option.type }));
        }
    }

    const fields_array = try fields.toOwnedSlice();
    const fields_raw = try std.mem.concat(alloc, u8, fields_array);
    return std.fmt.allocPrint(alloc,
        \\options: struct {{
        \\{s}}} = .{{}},
        \\
    , .{fields_raw});
}

fn getArgumentParseFunc(arguments: anytype, alloc: Allocator) ![]const u8 {
    var checks: std.ArrayList([]const u8) = .init(alloc);
    const fields = std.meta.fields(@TypeOf(arguments));

    try checks.append(std.fmt.comptimePrint(
        \\    if (arguments_found >= {d}) {{
        \\        try extra_args.append(std.mem.span(arg.ptr));
        \\        return arguments_found;
        \\    }}
        \\
    , .{fields.len}));

    inline for (fields) |field| {
        const arg = @field(arguments, field.name);
        const type_def = arg.type;
        const idx = arg.pos;

        try checks.append(std.fmt.comptimePrint(
            \\
            \\    if (arguments_found == {d}) {{
            \\        self.arguments.{s} = try convertValue({}, arg);
            \\    }}
            \\
        , .{ idx, field.name, type_def }));
    }

    const check_string = try std.mem.concat(alloc, u8, try checks.toOwnedSlice());

    return std.fmt.allocPrint(alloc,
        \\
        \\fn parseArgument(self: *Self, arg: [:0]const u8, arguments_found: usize, extra_args: *std.ArrayList([]const u8)) !usize {{
        \\{s}
        \\    return arguments_found + 1;
        \\}}
        \\
    , .{check_string});
}

fn getLongOptionParseFunc(options: anytype, alloc: Allocator) ![]const u8 {
    var checks: std.ArrayList([]const u8) = .init(alloc);
    const fields = std.meta.fields(@TypeOf(options));

    try checks.append(
        \\    const current_option = args[idx][2..];
        \\    const option_name, const maybe_value = blk: {
        \\        const separator = std.mem.indexOf(u8, current_option, "=");
        \\        if (separator) |sep| {
        \\            break :blk .{ current_option[0..sep], current_option[sep + 1..] };
        \\        }
        \\        break :blk .{ current_option, null };
        \\    };
        \\
    );

    inline for (fields) |field| {
        const option = @field(options, field.name);
        const type_def = option.type;

        if (type_def == bool) {
            try checks.append(try std.fmt.allocPrint(alloc,
                \\
                \\    if (std.mem.eql(u8, option_name, "{s}")) {{
                \\        self.options.{s} = if (maybe_value) |value| try convertValue(bool, value) else true;
                \\        return idx;
                \\    }}
                \\
            , .{ field.name, field.name }));
        } else {
            try checks.append(try std.fmt.allocPrint(alloc,
                \\    if (std.mem.eql(u8, option_name, "{s}")) {{
                \\        const value, const ret_idx = blk: {{
                \\            if (maybe_value) |value| {{
                \\                break :blk .{{ value, idx }};
                \\            }}
                \\            if (idx < args.len - 1 and args[idx + 1][0] != '-') {{
                \\                break :blk .{{ args[idx + 1], idx + 1 }};
                \\            }}
                \\
                \\            return Error.MissingValue;
                \\        }};
                \\
                \\        self.options.{s} = try convertValue({}, value);
                \\        return ret_idx;
                \\    }}
            , .{ field.name, field.name, type_def }));
        }
    }

    const check_string = try std.mem.concat(alloc, u8, try checks.toOwnedSlice());

    return std.fmt.allocPrint(alloc,
        \\
        \\fn parseLongOption(self: *Self, idx: usize, args: [][:0]const u8) !usize {{
        \\{s}
        \\    return Error.UnknownOption;
        \\}}
        \\
    , .{check_string});
}

fn getShortOptionParseFunc(options: anytype, alloc: Allocator) ![]const u8 {
    var checks: std.ArrayList([]const u8) = .init(alloc);
    const fields = std.meta.fields(@TypeOf(options));

    inline for (fields) |field| {
        const option = @field(options, field.name);
        const type_def = option.type;
        if (type_def == bool and @hasField(@TypeOf(option), "short")) {
            const short_name = option.short;
            try checks.append(std.fmt.comptimePrint(
                \\        if (flag == '{c}') {{
                \\            self.options.{s} = true;
                \\            continue;
                \\        }}
                \\
            , .{ short_name, field.name }));
        }
    }

    const check_string = try std.mem.concat(alloc, u8, try checks.toOwnedSlice());
    return std.fmt.allocPrint(alloc,
        \\
        \\fn parseShortOptions(self: *Self, flags: []const u8) !void {{
        \\    for (flags) |flag| {{
        \\{s}
        \\        return Error.UnknownOption;
        \\    }}
        \\}}
        \\
    , .{check_string});
}
