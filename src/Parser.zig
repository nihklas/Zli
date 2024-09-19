const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

const Error = error{
    TypeError,
    UnknownOption,
    MissingValue,
};

arguments: struct {
    age: ?u8 = null,
} = .{},
options: struct {
    help: bool = false,
    name: ?[]const u8 = null,
},
extra_args: [][]const u8 = &.{},
args: ?[][:0]u8 = null,
alloc: Allocator,
help: []const u8 =
    \\USAGE: demo <age>
    \\
    \\ARGUMENTS:
    \\    age=AGE                  Put your age here
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
    var arguments_found: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];

        if (std.mem.startsWith(u8, arg, "--")) {
            idx = try self.parseLongOption(idx, args);
            continue;
        }

        if (arg[0] == '-') {
            try self.parseShortOptions(arg[1..]);
        }

        arguments_found = try self.parseArgument(arg, arguments_found, &extra_args);
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

fn parseArgument(self: *Self, arg: [:0]const u8, arguments_found: usize, extra_args: *std.ArrayList([]const u8)) !usize {
    if (arguments_found >= 1) {
        try extra_args.append(std.mem.span(arg.ptr));
        return arguments_found;
    }

    if (arguments_found == 0) {
        self.arguments.age = try convertValue(u8, arg);
    }

    return arguments_found + 1;
}

fn parseLongOption(self: *Self, idx: usize, args: [][:0]const u8) !usize {
    const current_option = args[idx][2..];
    const option_name, const maybe_value = blk: {
        const separator = std.mem.indexOf(u8, current_option, "=");
        if (separator) |sep| {
            break :blk .{ current_option[0..sep], current_option[sep..] };
        }
        break :blk .{ current_option, null };
    };

    if (std.mem.eql(u8, option_name, "help")) {
        self.options.help = if (maybe_value) |value| try convertValue(bool, value) else false;
        return idx;
    }

    if (std.mem.eql(u8, option_name, "name")) {
        const value, const ret_idx = blk: {
            if (maybe_value) |value| {
                break :blk .{ value, idx };
            }
            if (idx < args.len and args[idx + 1][0] != '-') {
                break :blk .{ args[idx + 1], idx + 1 };
            }

            return Error.MissingValue;
        };

        self.options.name = try convertValue([]const u8, value);
        return ret_idx;
    }

    return Error.UnknownOption;
}

fn parseShortOptions(self: *Self, flags: []const u8) !void {
    for (flags) |flag| {
        if (flag == 'h') {
            self.options.help = true;
        }
    }
    return Error.UnknownOption;
}
