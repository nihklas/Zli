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
};

options: std.StringHashMap(Option),
short_options: std.AutoHashMap(u8, []const u8),
alloc: Allocator,
is_parsed: bool,

pub fn init(alloc: Allocator) Zli {
    return .{
        .options = std.StringHashMap(Option).init(alloc),
        .short_options = std.AutoHashMap(u8, []const u8).init(alloc),
        .alloc = alloc,
        .is_parsed = false,
    };
}

pub fn deinit(self: *Zli) void {
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
        return option_value.getValueAs(T);
    }

    return Error.UnrecognizedOption;
}

fn parse(self: *Zli) !void {
    if (self.is_parsed) {
        return;
    }

    var arg_iter = try std.process.argsWithAllocator(self.alloc);
    defer arg_iter.deinit();

    var last_key: ?[]const u8 = null;
    while (arg_iter.next()) |argument| {
        if (std.mem.startsWith(u8, argument, "--")) {
            const arg = argument[2..];
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
                    break :value iter.next() orelse return Error.NoOptionValue;
                }
                break :value "";
            };

            const option_ptr = self.options.getPtr(key);
            if (option_ptr == null) {
                return Error.UnrecognizedOption;
            }
            option_ptr.?.value = value;
            last_key = key;
        } else if (std.mem.startsWith(u8, argument, "-") and last_key == null) {
            const short_names = argument[1..];
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
            option_ptr.?.value = argument;
            last_key = null;
        }
    }

    self.is_parsed = true;
}

const Option = struct {
    long: []const u8,
    short: ?u8,
    description: ?[]const u8,
    value: ?[]const u8,

    fn getValueAs(self: Option, comptime T: type) !?T {
        if (self.value == null) {
            return null;
        }

        const value = self.value.?;
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
};
