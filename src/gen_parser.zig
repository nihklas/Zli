const std = @import("std");
const Allocator = std.mem.Allocator;
const compPrint = std.fmt.comptimePrint;
const allocPrint = std.fmt.allocPrint;
const concat = std.mem.concat;

const exe_name = @import("config").program_name;

var already_generated = false;

pub fn generateParser(def: anytype) !void {
    if (already_generated) {
        std.debug.print("This function should only be called once\n", .{});
        std.process.exit(1);
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    var arena_state = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_state.deinit();
    const alloc = arena_state.allocator();

    const args = try std.process.argsAlloc(alloc);

    if (args.len != 2) {
        std.debug.print("Wrong amount of arguments", .{});
        std.process.exit(1);
    }

    const output_file_path = args[1];

    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        std.debug.print("unable to open '{s}': {s}", .{ output_file_path, @errorName(err) });
        std.process.exit(1);
    };
    defer output_file.close();

    // TODO: Add error msg field for better output on parse Error
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
        \\extra_args: [][]const u8 = &.{},
        \\args: ?[][:0]u8 = null,
        \\alloc: Allocator,
        \\arguments_found: usize = 0,
        \\
    );

    try output_file.writeAll(try getArgumentStruct(def, alloc));
    try output_file.writeAll(try getOptionsStruct(def, alloc));
    try output_file.writeAll(try getSubcommandsStruct(def, alloc, exe_name));

    try output_file.writeAll(try getHelpText(def, alloc, exe_name));
    try output_file.writeAll(
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
        \\    while (idx < args.len) : (idx += 1) {
        \\        const arg = args[idx];
        \\
        \\        if (std.mem.startsWith(u8, arg, "--")) {
        \\            idx = try self.parseLongOption(idx, args);
        \\            continue;
        \\        }
        \\
        \\        if (arg[0] == '-') {
        \\            if (arg.len == 2) {
        \\                idx = try self.parseSingleShortOption(idx, args);
        \\            } else {
        \\                try self.parseShortOptions(arg[1..]);
        \\            }
        \\            continue;
        \\        }
        \\
        \\        if (self.arguments_found == 0 and self.parseSubcommand(arg)) {
        \\            continue;
        \\        }
        \\
        \\        try self.parseArgument(arg, &extra_args);
        \\        self.arguments_found += 1;
        \\    }
        \\
        \\    self.extra_args = try extra_args.toOwnedSlice();
        \\}
        \\
        \\pub fn convertValue(target: type, value: []const u8) Error!target {
        \\    return switch (@typeInfo(target)) {
        \\        .int => std.fmt.parseInt(target, value, 0) catch return Error.TypeError,
        \\        .float => std.fmt.parseFloat(target, value) catch return Error.TypeError,
        \\        .bool => !std.mem.eql(u8, value, "false") and value.len > 0,
        \\        .pointer => value,
        \\        else => unreachable,
        \\    };
        \\}
        \\
    );

    try output_file.writeAll(try getArgumentParseFunc(def, &.{}, alloc));
    try output_file.writeAll(try getLongOptionParseFunc(def, alloc));
    try output_file.writeAll(try getShortOptionParseFunc(def, alloc));
    try output_file.writeAll(try getSingleShortOptionParseFunc(def, alloc));
    try output_file.writeAll(try getSubcommandParseFunc(def, &.{}, alloc));

    already_generated = true;
}

fn getHelpText(def: anytype, alloc: Allocator, program_name: []const u8) ![]const u8 {
    const def_type = @TypeOf(def);
    const has_options = @hasField(def_type, "options");
    const sorted_arguments: [][]const u8 = comptime blk: {
        if (!@hasField(def_type, "arguments")) {
            break :blk &.{};
        }

        const arguments_def = def.arguments;
        const arguments = std.meta.fields(@TypeOf(arguments_def));

        var sorted: [arguments.len][]const u8 = undefined;
        for (arguments) |arg| {
            const arg_def = @field(arguments_def, arg.name);
            sorted[arg_def.pos] = arg.name;
        }

        break :blk &sorted;
    };

    var text: std.ArrayList([]const u8) = .init(alloc);
    try text.append("help: []const u8 =\n");

    try text.append(try allocPrint(alloc, "\\\\USAGE: {s}", .{program_name}));

    if (has_options) {
        try text.append(" [OPTIONS]");
    }

    if (sorted_arguments.len > 0) {
        inline for (sorted_arguments) |arg| {
            try text.append(compPrint(" <{s}>", .{arg}));
        }

        try text.append("\n");
        try text.append("\\\\\n");
        try text.append("\\\\ARGUMENTS:");

        inline for (sorted_arguments) |arg| {
            try text.append("\n");
            try text.append("\\\\    ");
            const arg_def = @field(def.arguments, arg);
            const arg_hint = hint: {
                if (@hasField(@TypeOf(arg_def), "value_hint")) {
                    break :hint compPrint("{s}={s}", .{ arg, arg_def.value_hint });
                }
                break :hint arg;
            };
            try text.append(compPrint("{s: <30}", .{arg_hint}));
            if (@hasField(@TypeOf(arg_def), "desc")) {
                try text.append(arg_def.desc);
            }
        }
    }

    if (has_options) {
        try text.append("\n");
        try text.append("\\\\\n");
        try text.append("\\\\OPTIONS:");

        const options = std.meta.fields(@TypeOf(def.options));
        inline for (options) |option| {
            try text.append("\n");
            try text.append("\\\\    ");
            const option_def = @field(def.options, option.name);
            const option_names = blk: {
                if (@hasField(@TypeOf(option_def), "short")) {
                    break :blk compPrint("-{c}, --{s}", .{ option_def.short, option.name });
                }

                break :blk compPrint("--{s}", .{option.name});
            };
            const option_hint = blk: {
                if (@hasField(@TypeOf(option_def), "value_hint")) {
                    break :blk compPrint("{s}={s}", .{ option_names, option_def.value_hint });
                }

                break :blk option_names;
            };
            try text.append(compPrint("{s: <30}", .{option_hint}));
            if (@hasField(@TypeOf(option_def), "desc")) {
                try text.append(option_def.desc);
            }
        }
    }

    if (@hasField(@TypeOf(def), "subcommands")) {
        try text.append("\n");
        try text.append("\\\\\n");
        try text.append("\\\\COMMANDS:");

        const subcommands = def.subcommands;
        inline for (std.meta.fields(@TypeOf(subcommands))) |field| {
            try text.append("\n");
            try text.append("\\\\    ");
            const sub_def = @field(subcommands, field.name);
            try text.append(compPrint("{s: <30}", .{field.name}));
            if (@hasField(@TypeOf(sub_def), "desc")) {
                try text.append(sub_def.desc);
            }
        }
    }

    try text.append("\n\\\\\n,\n");
    return concat(alloc, u8, try text.toOwnedSlice());
}

fn getArgumentStruct(def: anytype, alloc: Allocator) ![]const u8 {
    if (!@hasField(@TypeOf(def), "arguments")) {
        return getEmptyStruct("arguments");
    }
    const arguments = def.arguments;

    const fields_def = std.meta.fields(@TypeOf(arguments));

    if (fields_def.len == 0) {
        return getEmptyStruct("arguments");
    }

    var fields: std.ArrayList([]const u8) = .init(alloc);

    inline for (fields_def) |argument_field| {
        const type_def = @field(arguments, argument_field.name).type;
        try fields.append(compPrint("    {s}: ?{} = null,\n", .{ argument_field.name, type_def }));
    }

    const fields_array = try fields.toOwnedSlice();
    const fields_raw = try concat(alloc, u8, fields_array);
    return allocPrint(alloc,
        \\arguments: struct {{
        \\{s}}} = .{{}},
        \\
    , .{fields_raw});
}

fn getOptionsStruct(def: anytype, alloc: Allocator) ![]const u8 {
    if (!@hasField(@TypeOf(def), "options")) {
        return getEmptyStruct("options");
    }

    const options = def.options;
    const fields_def = std.meta.fields(@TypeOf(options));

    if (fields_def.len == 0) {
        return getEmptyStruct("options");
    }

    var fields: std.ArrayList([]const u8) = .init(alloc);

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
            const typeinfo = @typeInfo(@TypeOf(default_val));
            if (typeinfo == .pointer and typeinfo.pointer.size == .Slice) {
                try fields.append(compPrint("    {s}: {} = &.{any},\n", .{ option_field.name, option.type, default_val }));
            } else {
                try fields.append(compPrint("    {s}: {} = {any},\n", .{ option_field.name, option.type, default_val }));
            }
        } else {
            try fields.append(compPrint("    {s}: ?{} = null,\n", .{ option_field.name, option.type }));
        }
    }

    const fields_array = try fields.toOwnedSlice();
    const fields_raw = try concat(alloc, u8, fields_array);
    return allocPrint(alloc,
        \\options: struct {{
        \\{s}}} = .{{}},
        \\
    , .{fields_raw});
}

fn getSubcommandsStruct(def: anytype, alloc: Allocator, previous_command_name: []const u8) ![]const u8 {
    if (!@hasField(@TypeOf(def), "subcommands")) {
        return 
        \\subcommand: union(enum) {
        \\    _non: void,
        \\} = ._non,
        \\
        ;
    }
    const subcommands = def.subcommands;
    const field_defs = std.meta.fields(@TypeOf(subcommands));

    if (field_defs.len == 0) {
        return 
        \\subcommand: union(enum) {
        \\    _non: void,
        \\} = ._non,
        \\
        ;
    }

    var fields = std.ArrayList([]const u8).init(alloc);
    try fields.append(
        \\subcommand: union(enum) {
        \\    _non: void,
        \\
    );

    inline for (field_defs) |field| {
        const subcommand = @field(subcommands, field.name);
        const full_command = try concat(alloc, u8, &.{ previous_command_name, " ", field.name });
        try fields.append(compPrint("{s}: struct {{\n", .{field.name}));
        try fields.append(try getArgumentStruct(subcommand, alloc));
        try fields.append(try getOptionsStruct(subcommand, alloc));
        try fields.append(try getSubcommandsStruct(subcommand, alloc, full_command));
        try fields.append(try getHelpText(subcommand, alloc, full_command));
        try fields.append("},\n");
    }

    try fields.append("} = ._non,\n");
    const fields_raw = try fields.toOwnedSlice();
    return try concat(alloc, u8, fields_raw);
}

fn getArgumentParseFunc(def: anytype, cmd_path: [][]const u8, alloc: Allocator) ![]const u8 {
    const func_template =
        \\
        \\fn parseArgument{s}(self: *Self, arg: [:0]const u8, extra_args: *std.ArrayList([]const u8)) !void {{
        \\    switch(self{s}.subcommand) {{
        \\        ._non => {{
        \\{s}
        \\        }},
        \\{s}
        \\    }}
        \\}}
        \\
    ;

    const empty_func_template =
        \\
        \\fn parseArgument{s}(_: *Self, arg: [:0]const u8, arguments_found: usize, extra_args: *std.ArrayList([]const u8)) !usize {{
        \\    try extra_args.append(std.mem.span(arg.ptr));
        \\    return arguments_found;
        \\}}
        \\
    ;

    const func_name = try getFunctionSuffix(cmd_path, alloc);
    const subcommand_path = try getSubcommandPath(cmd_path, alloc);

    if (!@hasField(@TypeOf(def), "arguments")) {
        return try allocPrint(alloc, empty_func_template, .{func_name});
    }

    const arguments = def.arguments;
    const fields = std.meta.fields(@TypeOf(arguments));

    if (fields.len == 0) {
        return try allocPrint(alloc, empty_func_template, .{func_name});
    }

    var checks = std.ArrayList([]const u8).init(alloc);

    try checks.append(compPrint(
        \\    if (self.arguments_found >= {d}) {{
        \\        try extra_args.append(std.mem.span(arg.ptr));
        \\        return;
        \\    }}
        \\
    , .{fields.len}));

    inline for (fields) |field| {
        const arg = @field(arguments, field.name);
        const type_def = arg.type;
        const idx = arg.pos;

        const field_access = access: {
            if (subcommand_path.len == 0) {
                break :access ".arguments." ++ field.name;
            }
            break :access try concat(alloc, u8, &.{ subcommand_path, ".arguments.", field.name });
        };
        try checks.append(try allocPrint(alloc,
            \\
            \\    if (self.arguments_found == {d}) {{
            \\        self{s} = try convertValue({}, arg);
            \\        return;
            \\    }}
            \\
        , .{ idx, field_access, type_def }));
    }

    const additional_functions, const switch_prongs = funcs: {
        const subcommand_fields = getSubcommandFields(def);

        if (subcommand_fields.len == 0) {
            break :funcs .{ "", "" };
        }

        const subcommands = def.subcommands;

        var funcs = std.ArrayList([]const u8).init(alloc);
        var switch_prongs = std.ArrayList([]const u8).init(alloc);

        inline for (subcommand_fields) |field| {
            const sub = @field(subcommands, field.name);
            const path = try concat(alloc, []const u8, &.{ cmd_path, &.{field.name} });
            try funcs.append(try getArgumentParseFunc(sub, path, alloc));
            try switch_prongs.append(try allocPrint(alloc, "        .{s} => return self.parseArgument{s}_{s}(arg, extra_args),\n", .{
                field.name,
                func_name,
                field.name,
            }));
        }

        const funcs_raw = try funcs.toOwnedSlice();
        const switch_prongs_raw = try switch_prongs.toOwnedSlice();

        break :funcs .{ try concat(alloc, u8, funcs_raw), try concat(alloc, u8, switch_prongs_raw) };
    };

    const check_string = try concat(alloc, u8, try checks.toOwnedSlice());
    const rendered_func = try allocPrint(alloc, func_template, .{ func_name, subcommand_path, check_string, switch_prongs });

    return concat(alloc, u8, &.{ rendered_func, additional_functions });
}

fn getLongOptionParseFunc(def: anytype, alloc: Allocator) ![]const u8 {
    // TODO: Add subcommand support

    if (!@hasField(@TypeOf(def), "options")) {
        return getEmptyOptionsFunc();
    }

    const options = def.options;
    const fields = std.meta.fields(@TypeOf(options));

    if (fields.len == 0) {
        return getEmptyOptionsFunc();
    }

    var checks: std.ArrayList([]const u8) = .init(alloc);

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
            try checks.append(try allocPrint(alloc,
                \\
                \\    if (std.mem.eql(u8, option_name, "{s}")) {{
                \\        self.options.{s} = if (maybe_value) |value| try convertValue(bool, value) else true;
                \\        return idx;
                \\    }}
                \\
            , .{ field.name, field.name }));
        } else {
            try checks.append(try allocPrint(alloc,
                \\
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
                \\
            , .{ field.name, field.name, type_def }));
        }
    }

    const check_string = try concat(alloc, u8, try checks.toOwnedSlice());

    return allocPrint(alloc,
        \\
        \\fn parseLongOption(self: *Self, idx: usize, args: [][:0]const u8) !usize {{
        \\{s}
        \\    return Error.UnknownOption;
        \\}}
        \\
    , .{check_string});
}

fn getShortOptionParseFunc(def: anytype, alloc: Allocator) ![]const u8 {
    // TODO: Add subcommand support

    if (!@hasField(@TypeOf(def), "options")) {
        return getEmptyShortOptionsFunc();
    }

    const options = def.options;
    const fields = std.meta.fields(@TypeOf(options));
    if (fields.len == 0) {
        return getEmptyShortOptionsFunc();
    }

    var checks: std.ArrayList([]const u8) = .init(alloc);

    inline for (fields) |field| {
        const option = @field(options, field.name);
        const type_def = option.type;
        if (@hasField(@TypeOf(option), "short")) {
            const short_name = option.short;
            if (type_def == bool) {
                try checks.append(compPrint(
                    \\        if (flag == '{c}') {{
                    \\            self.options.{s} = true;
                    \\            continue;
                    \\        }}
                    \\
                , .{ short_name, field.name }));
            }
        }
    }

    const check_string = try concat(alloc, u8, try checks.toOwnedSlice());
    return allocPrint(alloc,
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

fn getSingleShortOptionParseFunc(def: anytype, alloc: Allocator) ![]const u8 {
    // TODO: Add subcommand support

    if (!@hasField(@TypeOf(def), "options")) {
        return getEmptySingleShortOptionsFunc();
    }

    const options = def.options;
    const fields = std.meta.fields(@TypeOf(options));
    if (fields.len == 0) {
        return getEmptySingleShortOptionsFunc();
    }

    var checks: std.ArrayList([]const u8) = .init(alloc);

    inline for (fields) |field| {
        const option = @field(options, field.name);
        const type_def = option.type;
        if (@hasField(@TypeOf(option), "short")) {
            const short_name = option.short;
            if (type_def != bool) {
                try checks.append(compPrint(
                    \\
                    \\    if (flag == '{c}') {{
                    \\        const value, const ret_idx = blk: {{
                    \\            if (idx < args.len - 1 and args[idx + 1][0] != '-') {{
                    \\                break :blk .{{ args[idx + 1], idx + 1 }};
                    \\            }}
                    \\            return Error.MissingValue;
                    \\        }};
                    \\        self.options.{s} = try convertValue({}, value);
                    \\        return ret_idx;
                    \\    }}
                    \\
                , .{ short_name, field.name, type_def }));
            }
        }
    }

    if (checks.items.len == 0) {
        try checks.append("    _ = flag;");
    }

    const check_string = try concat(alloc, u8, try checks.toOwnedSlice());
    return allocPrint(alloc,
        \\
        \\fn parseSingleShortOption(self: *Self, idx: usize, args: [][:0]const u8) !usize {{
        \\    const option = args[idx][1..];
        \\    const flag = option[0];
        \\{s}
        \\    try self.parseShortOptions(option);
        \\    return idx;
        \\}}
        \\
    , .{check_string});
}

fn getSubcommandParseFunc(def: anytype, cmd_path: [][]const u8, alloc: Allocator) ![]const u8 {
    const func_template =
        \\
        \\fn parseSubcommand{s}(self: *Self, arg: []const u8) bool {{
        \\    switch (self{s}.subcommand) {{
        \\        ._non => {{{s}}},
        \\{s}
        \\    }}
        \\    return false;
        \\}}
        \\
    ;

    const empty_func_template =
        \\
        \\fn parseSubcommand{s}(_: *Self, _: []const u8) bool {{
        \\    return false;
        \\}}
        \\
    ;

    const func_name = try getFunctionSuffix(cmd_path, alloc);
    const subcommand_path = try getSubcommandPath(cmd_path, alloc);

    const subcommand_fields = getSubcommandFields(def);

    if (subcommand_fields.len == 0) {
        return try allocPrint(alloc, empty_func_template, .{func_name});
    }

    const subcommands = def.subcommands;
    var switch_prongs = std.ArrayList([]const u8).init(alloc);
    var if_statements = std.ArrayList([]const u8).init(alloc);
    var additional_functions = std.ArrayList([]const u8).init(alloc);

    inline for (subcommand_fields) |field| {
        const sub = @field(subcommands, field.name);
        const path = try concat(alloc, []const u8, &.{ cmd_path, &.{field.name} });

        try switch_prongs.append(try allocPrint(alloc, "        .{s} => return self.parseSubcommand{s}_{s}(arg),\n", .{
            field.name,
            func_name,
            field.name,
        }));

        try if_statements.append(try allocPrint(alloc,
            \\
            \\            if (std.mem.eql(u8, arg, "{s}")) {{
            \\                self{s}.subcommand = .{{ .{s} = .{{}} }};
            \\                return true;
            \\            }}   
            \\
        , .{ field.name, subcommand_path, field.name }));

        try additional_functions.append(try getSubcommandParseFunc(sub, path, alloc));
    }
    try if_statements.append("        ");

    const switch_prongs_raw = try concat(alloc, u8, try switch_prongs.toOwnedSlice());
    const if_statements_raw = try concat(alloc, u8, try if_statements.toOwnedSlice());

    const rendered_func = try allocPrint(alloc, func_template, .{
        func_name,
        subcommand_path,
        if_statements_raw,
        switch_prongs_raw,
    });

    const additional_functions_raw = try concat(alloc, u8, try additional_functions.toOwnedSlice());

    return try concat(alloc, u8, &.{ rendered_func, additional_functions_raw });
}

fn getEmptyStruct(comptime name: []const u8) []const u8 {
    return compPrint("{s}: struct{{}} = .{{}},\n", .{name});
}

fn getEmptyArgumentsFunc() []const u8 {
    return 
    \\
    \\fn parseArgument(_: *Self, arg: [:0]const u8, arguments_found: usize, extra_args: *std.ArrayList([]const u8)) !usize {
    \\    try extra_args.append(std.mem.span(arg.ptr));
    \\    return arguments_found;
    \\}
    \\
    ;
}

fn getEmptyOptionsFunc() []const u8 {
    return 
    \\
    \\fn parseLongOption(_: *Self, _: usize, _: [][:0]const u8) !usize {
    \\    return Error.UnknownOption;
    \\}
    \\
    ;
}

fn getEmptyShortOptionsFunc() []const u8 {
    return 
    \\
    \\fn parseShortOptions(_: *Self, _: []const u8) !void {
    \\    return Error.UnknownOption;
    \\}
    \\
    ;
}

fn getEmptySingleShortOptionsFunc() []const u8 {
    return 
    \\
    \\fn parseSingleShortOption(self: *Self, idx: usize, args: [][:0]const u8) !usize {
    \\    const option = args[idx][1..];
    \\    try self.parseShortOptions(option);
    \\    return idx;
    \\}
    \\
    ;
}

fn getFunctionSuffix(cmd_path: [][]const u8, alloc: Allocator) ![]const u8 {
    if (cmd_path.len == 0) {
        return "";
    }
    var acc: []const u8 = "";
    for (cmd_path) |cmd| {
        acc = try concat(alloc, u8, &.{ acc, "_", cmd });
    }

    return acc;
}

fn getSubcommandPath(cmd_path: [][]const u8, alloc: Allocator) ![]const u8 {
    if (cmd_path.len == 0) {
        return "";
    }
    var acc: []const u8 = "";
    for (cmd_path) |cmd| {
        acc = try concat(alloc, u8, &.{ acc, ".subcommand.", cmd });
    }
    return acc;
}

fn getSubcommandFields(def: anytype) []const std.builtin.Type.StructField {
    if (!@hasField(@TypeOf(def), "subcommands")) {
        return &.{};
    }

    const subcomands = def.subcommands;
    return std.meta.fields(@TypeOf(subcomands));
}
