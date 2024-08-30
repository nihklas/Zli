const std = @import("std");
const zli = @import("zli");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var parser = try zli.Parser(.{
        .bool = .{
            .type = bool,
            .short = 'b',
            .desc = "Simple flag",
        },
    }).init(alloc);

    _ = parser.option("bool");

    return 0;
}
