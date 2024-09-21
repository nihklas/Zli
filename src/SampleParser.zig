const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

const Error = error{
    TypeError,
    UnknownOption,
    MissingValue,
};

extra_args: [][]const u8 = &.{},
args: ?[][:0]u8 = null,
alloc: Allocator,
arguments_found: usize = 0,
arguments: struct {
    age: ?u8 = null,
} = .{},
options: struct {
    bool: bool = false,
    str: []const u8 = &.{ 104, 97, 108, 108, 111 },
    int: i32 = 0,
    help: bool = false,
    long_name: ?f32 = null,
} = .{},
subcommand: union(enum) {
    _non: void,
    hello: struct {
        arguments: struct {
            name: ?[]const u8 = null,
        } = .{},
        options: struct {} = .{},
        subcommand: union(enum) {
            _non: void,
        } = ._non,
        help: []const u8 =
            \\USAGE: demo_buildtime hello <name>
            \\
            \\ARGUMENTS:
            \\    name=NAME                     Put the name to be greeted
            \\
        ,
    },
} = ._non,
help: []const u8 =
    \\USAGE: demo_buildtime [OPTIONS] <age>
    \\
    \\ARGUMENTS:
    \\    age=INT                       Put in your age as the first argument
    \\
    \\OPTIONS:
    \\    -b, --bool                    Just some random flag
    \\    --str=STRING                  Put something to say here, it's a string, duh
    \\    -i, --int=INT                 If you have a number, put it here
    \\    -h, --help                    Print this help text
    \\    --long_name=FLOAT             A long option-name, just to pass a float
    \\
    \\COMMANDS:
    \\    hello                         Greet someone special
    \\
,

pub fn init(alloc: Allocator) Self {
    return .{
        .alloc = alloc,
    };
}

pub fn deinit(self: *Self) void {
    if (self.args) |args| {
        std.process.argsFree(self.alloc, args);
    }
    self.alloc.free(self.extra_args);
}

pub fn parse(self: *Self) !void {
    const args = try std.process.argsAlloc(self.alloc);
    self.args = args;

    var extra_args: std.ArrayList([]const u8) = .init(self.alloc);
    defer extra_args.deinit();

    var idx: usize = 1;
    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];

        if (std.mem.startsWith(u8, arg, "--")) {
            idx = try self.parseLongOption(idx, args);
            continue;
        }

        if (arg[0] == '-') {
            if (arg.len == 2) {
                idx = try self.parseSingleShortOption(idx, args);
            } else {
                try self.parseShortOptions(arg[1..]);
            }
            continue;
        }

        if (self.arguments_found == 0 and self.parseSubcommand(arg)) {
            continue;
        }

        try self.parseArgument(arg, &extra_args);
        self.arguments_found += 1;
    }

    self.extra_args = try extra_args.toOwnedSlice();
}

pub fn convertValue(target: type, value: []const u8) Error!target {
    return switch (@typeInfo(target)) {
        .int => std.fmt.parseInt(target, value, 0) catch return Error.TypeError,
        .float => std.fmt.parseFloat(target, value) catch return Error.TypeError,
        .bool => !std.mem.eql(u8, value, "false") and value.len > 0,
        .pointer => value,
        else => unreachable,
    };
}

fn parseArgument(self: *Self, arg: [:0]const u8, extra_args: *std.ArrayList([]const u8)) !void {
    if (self.arguments_found >= 1) {
        try extra_args.append(std.mem.span(arg.ptr));
        return;
    }

    if (self.arguments_found == 0) {
        self.arguments.age = try convertValue(u8, arg);
        return;
    }
}

fn parseLongOption(self: *Self, idx: usize, args: [][:0]const u8) !usize {
    const current_option = args[idx][2..];
    const option_name, const maybe_value = blk: {
        const separator = std.mem.indexOf(u8, current_option, "=");
        if (separator) |sep| {
            break :blk .{ current_option[0..sep], current_option[sep + 1 ..] };
        }
        break :blk .{ current_option, null };
    };

    if (std.mem.eql(u8, option_name, "bool")) {
        self.options.bool = if (maybe_value) |value| try convertValue(bool, value) else true;
        return idx;
    }

    if (std.mem.eql(u8, option_name, "str")) {
        const value, const ret_idx = blk: {
            if (maybe_value) |value| {
                break :blk .{ value, idx };
            }
            if (idx < args.len - 1 and args[idx + 1][0] != '-') {
                break :blk .{ args[idx + 1], idx + 1 };
            }

            return Error.MissingValue;
        };

        self.options.str = try convertValue([]const u8, value);
        return ret_idx;
    }

    if (std.mem.eql(u8, option_name, "int")) {
        const value, const ret_idx = blk: {
            if (maybe_value) |value| {
                break :blk .{ value, idx };
            }
            if (idx < args.len - 1 and args[idx + 1][0] != '-') {
                break :blk .{ args[idx + 1], idx + 1 };
            }

            return Error.MissingValue;
        };

        self.options.int = try convertValue(i32, value);
        return ret_idx;
    }

    if (std.mem.eql(u8, option_name, "help")) {
        self.options.help = if (maybe_value) |value| try convertValue(bool, value) else true;
        return idx;
    }

    if (std.mem.eql(u8, option_name, "long_name")) {
        const value, const ret_idx = blk: {
            if (maybe_value) |value| {
                break :blk .{ value, idx };
            }
            if (idx < args.len - 1 and args[idx + 1][0] != '-') {
                break :blk .{ args[idx + 1], idx + 1 };
            }

            return Error.MissingValue;
        };

        self.options.long_name = try convertValue(f32, value);
        return ret_idx;
    }

    return Error.UnknownOption;
}

fn parseShortOptions(self: *Self, flags: []const u8) !void {
    for (flags) |flag| {
        if (flag == 'b') {
            self.options.bool = true;
            continue;
        }
        if (flag == 'h') {
            self.options.help = true;
            continue;
        }

        return Error.UnknownOption;
    }
}

fn parseSingleShortOption(self: *Self, idx: usize, args: [][:0]const u8) !usize {
    const option = args[idx][1..];
    const flag = option[0];

    if (flag == 'i') {
        const value, const ret_idx = blk: {
            if (idx < args.len - 1 and args[idx + 1][0] != '-') {
                break :blk .{ args[idx + 1], idx + 1 };
            }
            return Error.MissingValue;
        };
        self.options.int = try convertValue(i32, value);
        return ret_idx;
    }

    try self.parseShortOptions(option);
    return idx;
}

fn parseSubcommand(self: *Self, arg: []const u8) bool {
    switch (self.subcommand) {
        ._non => {
            if (std.mem.eql(u8, arg, "hello")) {
                self.subcommand = .{ .hello = .{} };
                return true;
            }
        },
        .hello => return self.parseSubcommand_hello(arg),
    }
    return false;
}

fn parseSubcommand_hello(_: *Self, _: []const u8) bool {
    return false;
}
