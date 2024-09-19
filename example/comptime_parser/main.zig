const std = @import("std");
const Parser = @import("cli.zig").Parser;

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var parser = try Parser.init(alloc);
    defer parser.deinit(); // Remember to call .deinit()
    // Call .parse() before accessing any value
    parser.parse() catch {
        try parser.help(std.io.getStdOut().writer());
        return 64;
    };

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

    std.debug.print("arguments: name '{s}', age {d}\n", .{ name, age });

    std.debug.print("'bool' - typeof: {}, value: {any}\n", .{ @TypeOf(parser.options.bool), parser.options.bool });
    std.debug.print("'str'  - typeof: {}, value: {?s}\n", .{ @TypeOf(parser.options.str), parser.options.str });
    std.debug.print("'int' - typeof: {}, value: {any}\n", .{ @TypeOf(parser.options.int), parser.options.int });
    std.debug.print("'help' - typeof: {}, value: {any}\n", .{ @TypeOf(parser.options.help), parser.options.help });
    std.debug.print("'long-name' - typeof: {}, value: {any}\n", .{ @TypeOf(parser.options.@"long-name"), parser.options.@"long-name" });

    return 0;
}
