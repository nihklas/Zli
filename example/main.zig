const std = @import("std");
const Zli = @import("Zli");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var parser = Zli.init(alloc);
    defer parser.deinit();
    parser.parse() catch |err| {
        std.debug.print("{s}\n", .{@errorName(err)});
        std.debug.print("{s}\n", .{parser.help});
        return 1;
    };

    if (parser.options.help) {
        std.debug.print("{s}\n", .{parser.help});
        return 0;
    }

    std.debug.print("argument age: {any}\n", .{parser.arguments.age});
    std.debug.print("argument number: {any}\n", .{parser.arguments.number});
    std.debug.print("option help: {any}\n", .{parser.options.help});
    std.debug.print("option boolean: {any}\n", .{parser.options.boolean});
    std.debug.print("option name: {?s}\n", .{parser.options.name});
    std.debug.print("extra arguments: {any}\n", .{parser.extra_args});
    return 0;
}
