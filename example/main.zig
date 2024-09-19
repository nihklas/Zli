const std = @import("std");
const Zli = @import("Zli");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var parser = Zli.init(alloc);
    defer parser.deinit();
    try parser.parse();

    std.debug.print("argument age: {any}\n", .{parser.arguments.age});
    std.debug.print("argument number: {any}\n", .{parser.arguments.number});
    std.debug.print("option help: {any}\n", .{parser.options.help});
    std.debug.print("option boolean: {any}\n", .{parser.options.boolean});
    std.debug.print("option name: {?s}\n", .{parser.options.name});
    std.debug.print("extra arguments: {any}\n", .{parser.extra_args});
}
