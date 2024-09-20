const zli = @import("zli");

pub fn main() !void {
    try zli.generateParser(.{
        .options = .{
            .bool = .{ .type = bool, .short = 'b', .desc = "Just some random flag" },
            .str = .{ .type = []const u8, .desc = "Put something to say here, it's a string, duh", .value_hint = "STRING" },
            .int = .{ .type = i32, .short = 'i', .desc = "If you have a number, put it here", .default = 0, .value_hint = "INT" },
            .help = .{ .type = bool, .short = 'h', .desc = "Print this help text" },
            .long_name = .{ .type = f32, .desc = "A long option-name, just to pass a float", .value_hint = "FLOAT" },
        },
        .arguments = .{
            .age = .{ .type = u8, .pos = 0, .desc = "Put in your age as the first argument", .value_hint = "INT" },
            .name = .{ .type = []const u8, .pos = 1, .desc = "Put your name as the second argument", .value_hint = "STRING" },
        },
    });
}
