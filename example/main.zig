const std = @import("std");
const Zli = @import("Zli");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var parser = Zli.init(alloc);
    defer parser.deinit();
    try parser.addOption("test", null, null);
    try parser.addOption("bool", 'b', null);
    try parser.addOption("str", null, null);
    try parser.addOption("int", null, null);

    const value = try parser.option(bool, "test") orelse false;
    const b = try parser.option(bool, "bool") orelse false;
    const str = try parser.option([]const u8, "str") orelse "";
    const int = try parser.option(i32, "int") orelse -1;

    std.debug.print("flag test: {}\n", .{value});
    std.debug.print("flag bool: {}\n", .{b});
    std.debug.print("option str: {s}\n", .{str});
    std.debug.print("option int: {d}\n", .{int});
}
