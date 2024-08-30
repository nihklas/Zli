const std = @import("std");
const zli = @import("zli");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var parser = try zli.Parser(.{
        .options = .{
            .bool = .{ .type = bool, .short = 'b', .desc = "Simple flag", .default = false },
            .int = .{ .type = i32, .short = 'i', .desc = "Simple integer", .default = 0 },
        },
        .arguments = .{
            .name = .{ .type = []u8, .pos = 1, .desc = "Just a name" },
        },
    }).init(alloc);
    defer parser.deinit();
    try parser.parse();

    std.debug.print("flag bool: {any}\n", .{parser.options.bool});
    std.debug.print("option int: {any}\n", .{parser.options.int});
    std.debug.print("argument name: {any}\n", .{parser.arguments.name});

    return 0;
}
