const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

const Error = error{
    TypeError,
};

arguments: struct {
    // ARGUMENT_DEFINITION
} = .{},
extra_args: [][]const u8 = &.{},
args: ?[][:0]u8 = null,
alloc: Allocator,

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

        arguments_found = try self.parseArgument(arg, arguments_found, &extra_args);
    }

    self.extra_args = try extra_args.toOwnedSlice();
}

pub fn convertValue(target: type, value: []const u8) Error!target {
    return switch (@typeInfo(target)) {
        .int => std.fmt.parseInt(target, value, 0) catch return Error.TypeError,
        .float => std.fmt.parseFloat(target, value) catch return Error.TypeError,
        .bool => value.len > 0,
        .pointer => value,
        else => unreachable,
    };
}

fn parseArgument(self: *Self, arg: [:0]const u8, arguments_found: usize, extra_args: *std.ArrayList([]const u8)) !usize {
    if (arguments_found >= 1) { // ARGUMENTS_AMOUNT
        try extra_args.append(std.mem.span(arg.ptr));
        return arguments_found;
    }

    // FOR EACH ARGUMENT
    if (arguments_found == 0) { // ARGUMENT POSITION
        self.arguments.age = try convertValue(u8, arg); // ARGUMENT ACCESS / ARGUMENT TYPE
    }

    return arguments_found + 1;
}
