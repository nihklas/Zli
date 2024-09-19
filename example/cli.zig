const std = @import("std");
const zli = @import("zli");

pub fn main() !void {
    try zli.generateParser("demo", .{
        .arguments = .{
            .age = .{ .type = u8, .pos = 0, .desc = "Put your age here", .value_hint = "AGE" },
            .number = .{ .type = i32, .pos = 1, .desc = "Some weird number", .value_hint = "NUMBER" },
        },
        .options = .{
            .help = .{ .type = bool, .short = 'h', .desc = "Show this help message" },
            .boolean = .{ .type = bool, .short = 'b' },
            .name = .{ .type = []const u8, .desc = "Put your name if you want, idc", .value_hint = "NAME" },
        },
    });
}
