const std = @import("std");
const Zli = @import("Zli");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var parser = Zli.init(alloc);
    defer parser.deinit();
    try parser.addOption("test", null, "Just a random test flag");
    try parser.addOption("bool", 'b', "Another Flag");
    try parser.addOption("str", null, "Put something to say here, as a string, duh");
    try parser.addOption("int", null, "If you want a number, you can put it here");

    try parser.addArgument("name", "The name of the user, who wants to be called out");
    try parser.addArgument("lastname", "The lastname of the user, who wants to be calling");

    try parser.help(std.io.getStdErr().writer());
    if (1 == 1) {
        return;
    }

    const value = try parser.option(bool, "test") orelse false;
    const b = try parser.option(bool, "bool") orelse false;
    const str = try parser.option([]const u8, "str") orelse "";
    const int = try parser.option(i32, "int") orelse -1;

    const name = try parser.argument([]const u8, "name");

    std.debug.print("flag test: {}\n", .{value});
    std.debug.print("flag bool: {}\n", .{b});
    std.debug.print("option str: {s}\n", .{str});
    std.debug.print("option int: {d}\n", .{int});
    std.debug.print("arg name: {s}\n", .{name});
}
