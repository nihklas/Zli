const std = @import("std");
const zli = @import("zli");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var parser = try zli.Parser(.{
        .options = .{
            .bool = .{ .type = bool, .short = 'b', .desc = "Simple flag", .default = false },
            .a = .{ .type = bool, .short = 'a', .default = false },
            .int = .{ .type = i32, .short = 'i', .desc = "Simple integer", .default = 0 },
            .help = .{ .type = bool, .short = 'h', .default = false },
        },
        .arguments = .{
            .name = .{ .type = []const u8, .pos = 2, .desc = "Just a name" },
            .age = .{ .type = u8, .pos = 1, .desc = "Put in your age" },
        },
    }).init(alloc);
    defer parser.deinit();
    try parser.parse();

    if (parser.options.help) {
        try parser.help(std.io.getStdOut().writer());
        return 0;
    }

    std.debug.print("flag bool: {any}\n", .{parser.options.bool});
    std.debug.print("flag a: {any}\n", .{parser.options.a});
    std.debug.print("option int: {any}\n", .{parser.options.int});
    std.debug.print("argument name: {?s}\n", .{parser.arguments.name});
    std.debug.print("argument age: {any}\n", .{parser.arguments.age});
    std.debug.print("extra args: {s}\n", .{parser.extra_args});

    return 0;
}
