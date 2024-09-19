const std = @import("std");
const zli = @import("zli");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    var arena_state = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = try std.process.argsAlloc(arena);

    if (args.len != 2) {
        std.debug.print("Wrong amount of arguments", .{});
        std.process.exit(1);
    }

    const output_file_path = args[1];

    try zli.generateParser(output_file_path, arena, "demo", .{
        .arguments = .{
            .age = .{ .type = u8, .pos = 0, .desc = "Put your age here", .value_hint = "AGE" },
            .number = .{ .type = i32, .pos = 1, .desc = "Some weird number", .value_hint = "NUMBER" },
        },
        .options = .{
            .help = .{ .type = bool, .short = 'h', .desc = "Show this help message" },
            .boolean = .{ .type = bool, .short = 'b' },
            .name = .{ .type = []const u8, .desc = "Put your name if you want, idc" },
        },
    });
}
