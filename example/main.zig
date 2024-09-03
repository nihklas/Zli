const std = @import("std");
const zli = @import("zli");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var parser = try zli.Parser(.{
        .options = .{
            .bool = .{ .type = bool, .short = 'b', .desc = "Just some random flag" },
            .str = .{ .type = []const u8, .desc = "Put something to say here, it's a string, duh" },
            .int = .{ .type = i32, .short = 'i', .desc = "If you have a number, put it here", .default = 0 },
            .help = .{ .type = bool, .short = 'h', .desc = "Print this help text" },
            .long_name = .{ .type = f32, .desc = "A long option-name, just to pass a float" },
        },
        .arguments = .{
            .age = .{ .type = u8, .pos = 1, .desc = "Put in your age as the first argument" },
            .name = .{ .type = []const u8, .pos = 2, .desc = "Put your name as the second argument" },
        },
    }).init(alloc);
    defer parser.deinit(); // Remember to call .deinit()
    try parser.parse(); // Call .parse() before accessing any value

    // Boolean flags automatically default to false, unless specified otherwise
    if (parser.options.help) {
        // print the auto-generated usage text
        try parser.help(std.io.getStdOut().writer());
        return 0;
    }

    // For required arguments, this pattern leverages zigs 'orelse' keyword, to print the help text
    // and exit with a correct return code
    const age = parser.arguments.age orelse {
        try parser.help(std.io.getStdOut().writer());
        return 64;
    };

    const name = parser.arguments.name orelse {
        try parser.help(std.io.getStdOut().writer());
        return 64;
    };

    std.debug.print("arguments: name '{s}', age: {d}\n", .{ name, age });

    std.debug.print("'bool' - typeof: {}, value: {any}\n", .{ @TypeOf(parser.options.bool), parser.options.bool });
    std.debug.print("'str'  - typeof: {}, value: {any}\n", .{ @TypeOf(parser.options.str), parser.options.str });
    std.debug.print("'int' - typeof: {}, value: {any}\n", .{ @TypeOf(parser.options.int), parser.options.int });
    std.debug.print("'help' - typeof: {}, value: {any}\n", .{ @TypeOf(parser.options.help), parser.options.help });
    std.debug.print("'long_name' - typeof: {}, value: {any}\n", .{ @TypeOf(parser.options.long_name), parser.options.long_name });

    return 0;
}
