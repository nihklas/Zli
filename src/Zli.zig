const std = @import("std");
const Allocator = std.mem.Allocator;

const Zli = @This();

pub const Error = error{
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
    NotParsedYet,
    ArgumentMissing,
};

arguments: std.StringHashMap(Argument),
arg_positions: std.AutoHashMap(u32, []const u8),
options: std.StringHashMap(Option),
short_options: std.AutoHashMap(u8, []const u8),
alloc: Allocator,
is_parsed: bool,

/// Create a new Zli Parser
/// Call `.deinit()` after usage
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

/// Calls `.deinit()` on every backing hashmap and sets itself to undefined. Usage after this is not safe
pub fn deinit(self: *Zli) void {
    self.arguments.deinit();
    self.arg_positions.deinit();
    self.options.deinit();
    self.short_options.deinit();
    self.* = undefined;
}

/// Add an Option to the parsers list of available options. `long` will be the key to access it later, everything else is optional.
/// Description will be printed in the generated help message
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

/// Access an option. The passed type will be used to cast/parse the raw value into.
/// If `T` is a bool, the returned value will be either true or false, only checking for the presence of the flag and ignoring
/// any value.
/// If `T` is any other type, it will return an optional value, depending on the existence of the flag and a value.
/// If the option is present, but without a value, this function will return Error.NoOptionValue.
pub fn option(self: *Zli, comptime T: type, long: []const u8) !(if (T == bool) bool else ?T) {
    if (!self.is_parsed) {
        try self.parse();
    }

    if (self.options.get(long)) |option_value| {
        return getValueAs(option_value.value, T);
    }

    return Error.UnrecognizedOption;
}

/// Add an Argument to the parsers list of positional arguments. `name` will be the key to access it later.
/// Description will be printed in the generated help message
/// The Order in which this gets called dictates the expected order of arguments when parsing
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

/// Access an argument. The passed type will be used to cast/parse the raw value into.
/// Arguments are required by default. So to make one optional, you have to catch Error.ArgumentMissing.
/// Note that this will only work on the trailing arguments
pub fn argument(self: *Zli, comptime T: type, comptime name: []const u8) !T {
    if (!self.is_parsed) {
        try self.parse();
    }

    if (self.arguments.get(name)) |arg| {
        return try getValueAs(arg.value, T) orelse return Error.ArgumentMissing;
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
        if (arg_raw[0] == '-') {
            var arg: []const u8 = arg_raw[1..];
            // first, check if there is more coming after '-'
            if (arg.len > 0) {
                // FIXME: There is a possible error, if somehow, someone passes '-='
                // for now it does not matter, but maybe someday ill fix it

                // if there is an '=' we split it first to get the value
                // if no '=' present, default to empty string
                const value = value: {
                    if (std.mem.indexOf(u8, arg_raw, "=")) |split| {
                        arg = arg_raw[1..split];
                        break :value arg_raw[split + 1 ..];
                    }
                    break :value "";
                };

                if (arg[0] == '-') {
                    const option_ptr = self.options.getPtr(arg[1..]);
                    if (option_ptr == null) {
                        return Error.UnrecognizedOption;
                    }
                    option_ptr.?.value = value;
                } else {
                    for (arg) |s| {
                        const long_name = self.short_options.get(s);
                        if (long_name == null) {
                            return Error.UnrecognizedOption;
                        }
                        const option_ptr = self.options.getPtr(long_name.?);
                        if (option_ptr == null) {
                            return Error.UnrecognizedOption;
                        }
                        option_ptr.?.value = "";
                        last_key = long_name;
                    }
                    self.options.getPtr(last_key.?).?.value = value;
                }
            }
        } else if (last_key) |key| {
            const option_ptr = self.options.getPtr(key);
            option_ptr.?.value = arg_raw;
            last_key = null;
        } else {
            if (self.arg_positions.get(found_args)) |arg_name| {
                const arg = self.arguments.getPtr(arg_name);
                arg.?.value = arg_raw;
                found_args += 1;
            }
        }
    }

    self.is_parsed = true;
}

/// Print a help message using all registered options and arguments
/// This will only print options and arguments registered before help() is called
/// Takes in a Writer
/// The passed return code is passed right back to allow one-liners on missing argument catches to return with the corrent exit code
pub fn help(self: *Zli, writer: anytype, return_code: u8) !u8 {
    const program_name = try programName(self.alloc);
    defer self.alloc.free(program_name);

    try writer.print("USAGE: {s}", .{program_name});
    if (self.options.count() > 0) {
        try writer.print(" [OPTIONS]", .{});
    }
    var argument_iter = self.arguments.iterator();
    while (argument_iter.next()) |arg| {
        try writer.print(" <{s}>", .{arg.value_ptr.name});
    }
    try writer.print("\n", .{});

    if (self.arguments.count() > 0) {
        try writer.print("\n", .{});
        try writer.print("ARGUMENTS:\n", .{});

        argument_iter = self.arguments.iterator();
        while (argument_iter.next()) |arg| {
            try writer.print("    {s: <25}", .{arg.value_ptr.name});
            if (arg.value_ptr.description) |desc| {
                try writer.print("{s}", .{desc});
            }
            try writer.print("\n", .{});
        }
    }

    if (self.options.count() > 0) {
        try writer.print("\n", .{});
        try writer.print("OPTIONS:\n", .{});
        var option_iter = self.options.iterator();
        while (option_iter.next()) |opt| {
            if (opt.value_ptr.short) |s| {
                try writer.print("    --{s}, -{c}", .{ opt.value_ptr.long, s });
                for (0..(19 - opt.value_ptr.long.len)) |_| {
                    try writer.print(" ", .{});
                }
            } else {
                try writer.print("    --{s}", .{opt.value_ptr.long});
                for (0..(23 - opt.value_ptr.long.len)) |_| {
                    try writer.print(" ", .{});
                }
            }
            if (opt.value_ptr.description) |desc| {
                try writer.print("{s}", .{desc});
            }
            try writer.print("\n", .{});
        }
    }

    return return_code;
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

fn getValueAs(raw_value: ?[]const u8, comptime T: type) !(if (T == bool) bool else ?T) {
    if (raw_value == null) {
        if (T == bool) {
            return false;
        }
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

fn programName(alloc: Allocator) ![]const u8 {
    const path = try std.fs.selfExePathAlloc(alloc);
    defer alloc.free(path);
    return try alloc.dupe(u8, std.fs.path.basename(path));
}
