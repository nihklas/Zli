const zli = @import("zli");

pub fn main() !void {
    try zli.generateParser(.{
        .options = .{
            .bool = .{ .type = bool, .short = 'b', .desc = "Just some random flag" },
            .str = .{
                .type = []const u8,
                .desc = "Put something to say here, it's a string, duh",
                .value_hint = "STRING",
                .default = "hallo",
            },
            .int = .{ .type = i32, .short = 'i', .desc = "If you have a number, put it here", .default = 0, .value_hint = "INT" },
            .help = .{ .type = bool, .short = 'h', .desc = "Print this help text" },
            .@"long-name" = .{ .type = f32, .desc = "A long option-name, just to pass a float", .value_hint = "FLOAT" },
        },
        .arguments = .{
            .age = .{ .type = u8, .pos = 0, .desc = "Put in your age as the first argument", .value_hint = "INT" },
        },
        .subcommands = .{
            .hello = .{
                .desc = "Greet someone special",
                .arguments = .{
                    .name = .{ .type = []const u8, .pos = 0, .desc = "Put the name to be greeted", .value_hint = "NAME" },
                },
                .options = .{
                    .help = .{ .type = bool, .short = 'h', .desc = "Print this help text" },
                },
                .subcommands = .{
                    .loudly = .{
                        .desc = "Greet someone a little louder",
                        .arguments = .{
                            .name = .{
                                .type = []const u8,
                                .pos = 0,
                                .desc = "Put the name to be greeted, loudly",
                                .value_hint = "NAME",
                            },
                        },
                        .options = .{
                            .scream = .{ .type = bool, .desc = "Use this to SCREAM at the person" },
                            .help = .{ .type = bool, .short = 'h', .desc = "Print this help text" },
                        },
                    },
                },
            },
            .@"with-minus" = .{
                .desc = "Just to test some things",
            },
        },
    });
}
