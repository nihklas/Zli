const std = @import("std");
const Zli = @import("Zli");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var parser = Zli.init(alloc);
    defer parser.deinit(); // Remember to call .deinit()
    // Call .parse() before accessing any value
    parser.parse() catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        std.debug.print("{s}", .{parser.help});
        return 64;
    };

    switch (parser.subcommand) {
        ._non => return baseCommand(&parser),
        .hello => return helloCommand(&parser, alloc),
    }
}

fn baseCommand(parser: *Zli) u8 {
    // Boolean flags automatically default to false, unless specified otherwise
    if (parser.options.help) {
        // print the auto-generated usage text
        std.debug.print("{s}", .{parser.help});
        return 0;
    }

    // For required arguments, this pattern leverages zigs 'orelse' keyword, to print the help text
    // and exit with a correct return code
    const age = parser.arguments.age orelse {
        std.debug.print("{s}", .{parser.help});
        return 64;
    };

    std.debug.print("arguments: age {d}\n", .{age});

    std.debug.print("'bool' - typeof: {}, value: {any}\n", .{ @TypeOf(parser.options.bool), parser.options.bool });
    std.debug.print("'str'  - typeof: {}, value: {?s}\n", .{ @TypeOf(parser.options.str), parser.options.str });
    std.debug.print("'int' - typeof: {}, value: {any}\n", .{ @TypeOf(parser.options.int), parser.options.int });
    std.debug.print("'help' - typeof: {}, value: {any}\n", .{ @TypeOf(parser.options.help), parser.options.help });
    std.debug.print("'long_name' - typeof: {}, value: {any}\n", .{ @TypeOf(parser.options.long_name), parser.options.long_name });

    return 0;
}

fn helloCommand(parser: *Zli, alloc: std.mem.Allocator) u8 {
    const hello_cmd = parser.subcommand.hello;
    switch (hello_cmd.subcommand) {
        ._non => {
            if (hello_cmd.options.help) {
                std.debug.print("{s}", .{hello_cmd.help});
                return 0;
            }

            const name = hello_cmd.arguments.name orelse {
                std.debug.print("{s}", .{hello_cmd.help});
                return 64;
            };

            std.debug.print("Hello {s}\n", .{name});
        },
        .loudly => |loud_cmd| {
            if (loud_cmd.options.help) {
                std.debug.print("{s}", .{loud_cmd.help});
                return 0;
            }

            const name = loud_cmd.arguments.name orelse {
                std.debug.print("{s}", .{loud_cmd.help});
                return 64;
            };

            const name_upper = alloc.alloc(u8, name.len) catch return 1;
            defer alloc.free(name_upper);
            _ = std.ascii.upperString(name_upper, name);

            if (loud_cmd.options.scream) {
                std.debug.print("HELLOOOOOOOO {s}!!!\n", .{name_upper});
            } else {
                std.debug.print("HELLO {s}\n", .{name_upper});
            }
        },
    }
    return 0;
}
