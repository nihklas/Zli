const std = @import("std");
const Allocator = std.mem.Allocator;

const Zli = @This();

const Error = error{
    UnrecognizedOption,
    OptionAlreadyExists,
    ShortOptionAlreadyExists,
    IllegalShortName,
    UnsupportedType,
    NoOptionValue,
    ArgumentAlreadyExists,
    UnrecognizedArgument,
    TooManyArguments,
    TooFewArguments,
};

arguments: std.StringHashMap(Argument),
arg_positions: std.AutoHashMap(u32, []const u8),
options: std.StringHashMap(Option),
short_options: std.AutoHashMap(u8, []const u8),
alloc: Allocator,
is_parsed: bool,

pub fn init(alloc: Allocator) Zli {
    return .{
        .arguments = std.StringHashMap(Argument).init(alloc),
        .arg_positions = std.AutoHashMap(u32, []const u8).init(alloc),
        .options = std.StringHashMap(Option).init(alloc),
        .short_options = std.AutoHashMap(u8, []const u8).init(alloc),
        .alloc = alloc,
        .is_parsed = false,
    };
}

pub fn deinit(self: *Zli) void {
    self.arguments.deinit();
    self.arg_positions.deinit();
    self.options.deinit();
    self.short_options.deinit();
}

pub fn addOption(self: *Zli, comptime long: []const u8, comptime short: ?u8, comptime description: ?[]const u8) !void {
    comptime if (short) |s| {
        if (!std.ascii.isAlphabetic(s)) {
            @compileError("Short Options must be alhpabetic");
        }
    };

    const result = try self.options.getOrPut(long);

    if (result.found_existing) {
        return Error.OptionAlreadyExists;
    }

    if (short) |s| {
        const short_gop = try self.short_options.getOrPut(s);
        if (short_gop.found_existing) {
            return Error.ShortOptionAlreadyExists;
        }

        short_gop.value_ptr.* = long;
    }

    result.value_ptr.* = .{
        .long = long,
        .short = short,
        .description = description,
        .value = null,
    };
}

pub fn optionRaw(self: *Zli, long: []const u8) ?[]const u8 {
    return self.option([]const u8, long) catch unreachable;
}

pub fn option(self: *Zli, comptime T: type, long: []const u8) !?T {
    if (!self.is_parsed) {
        try self.parse();
    }

    if (self.options.get(long)) |option_value| {
        return getValueAs(option_value.value, T);
    }

    return Error.UnrecognizedOption;
}

pub fn addArgument(self: *Zli, comptime name: []const u8, comptime description: ?[]const u8) !void {
    const result = try self.arguments.getOrPut(name);

    if (result.found_existing) {
        return Error.ArgumentAlreadyExists;
    }

    const arg_count = self.arg_positions.count();
    try self.arg_positions.put(arg_count, name);

    result.value_ptr.* = .{
        .name = name,
        .description = description,
        .value = null,
    };
}

pub fn argumentRaw(self: *Zli, comptime name: []const u8) ?[]const u8 {
    return self.argument([]const u8, name) catch unreachable;
}

pub fn argument(self: *Zli, comptime T: type, comptime name: []const u8) !T {
    if (!self.is_parsed) {
        try self.parse();
    }

    if (self.arguments.get(name)) |arg| {
        return try getValueAs(arg.value, T) orelse unreachable;
    }

    unreachable;
}

fn parse(self: *Zli) !void {
    if (self.is_parsed) {
        return;
    }

    var arg_iter = try std.process.argsWithAllocator(self.alloc);
    defer arg_iter.deinit();
    _ = arg_iter.skip(); // Skip program name

    var last_key: ?[]const u8 = null;
    var found_args: u32 = 0;
    while (arg_iter.next()) |arg_raw| {
        if (std.mem.startsWith(u8, arg_raw, "--")) {
            const arg = arg_raw[2..];
            const key = key: {
                if (std.mem.containsAtLeast(u8, arg, 1, "=")) {
                    var iter = std.mem.splitAny(u8, arg, "=");
                    break :key iter.next().?;
                }
                break :key arg;
            };
            const value = value: {
                if (std.mem.containsAtLeast(u8, arg, 1, "=")) {
                    var iter = std.mem.splitAny(u8, arg, "=");
                    _ = iter.next();
                    last_key = null;
                    break :value iter.next() orelse return Error.NoOptionValue;
                }
                last_key = key;
                break :value "";
            };

            const option_ptr = self.options.getPtr(key);
            if (option_ptr == null) {
                return Error.UnrecognizedOption;
            }
            option_ptr.?.value = value;
        } else if (std.mem.startsWith(u8, arg_raw, "-") and last_key == null) {
            const short_names = arg_raw[1..];
            for (short_names) |s| {
                const long_name = self.short_options.get(s);
                if (long_name == null) {
                    return Error.UnrecognizedOption;
                }
                const option_ptr = self.options.getPtr(long_name.?);
                if (option_ptr == null) {
                    return Error.UnrecognizedOption;
                }
                option_ptr.?.value = "";
            }
            last_key = null;
        } else if (last_key) |key| {
            const option_ptr = self.options.getPtr(key);
            option_ptr.?.value = arg_raw;
            last_key = null;
        } else {
            if (self.arg_positions.get(found_args)) |arg_name| {
                const arg = self.arguments.getPtr(arg_name);
                arg.?.value = arg_raw;
                found_args += 1;
            } else {
                return Error.TooManyArguments;
            }
        }
    }

    if (found_args != self.arguments.count()) {
        return Error.TooFewArguments;
    }

    self.is_parsed = true;
}

const Option = struct {
    long: []const u8,
    short: ?u8,
    description: ?[]const u8,
    value: ?[]const u8,
};

const Argument = struct {
    name: []const u8,
    description: ?[]const u8,
    value: ?[]const u8,
};

fn getValueAs(raw_value: ?[]const u8, comptime T: type) !?T {
    if (raw_value == null) {
        return null;
    }

    const value = raw_value.?;
    if (T == bool) {
        return true;
    }

    // Everything besides flags should have values
    if (value.len == 0) {
        return Error.NoOptionValue;
    }

    if (T == []const u8) {
        return value;
    }

    if (@typeInfo(T) == .Int) {
        return try std.fmt.parseInt(T, value, 10);
    }

    if (@typeInfo(T) == .Float) {
        return try std.fmt.parseFloat(T, value);
    }

    return Error.UnsupportedType;
}
