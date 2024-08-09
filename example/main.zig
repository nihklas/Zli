const std = @import("std");
const Zli = @import("Zli");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    // Initialize Parser, it uses Hashmaps internally, so it needs to be deinited after usage.
    // This also makes getting the arguments and options unsafe
    var parser = Zli.init(alloc);
    defer parser.deinit();

    // Add Options with a long name and optionally a short, single character name and a description for the help message
    try parser.addOption("test", 't', "Just a random test flag");
    try parser.addOption("bool", 'b', "Another Flag");
    try parser.addOption("str", null, "Put something to say here, as a string, duh");
    try parser.addOption("int", 'i', "If you want a number, you can put it here");
    try parser.addOption("help", 'h', "Print this help message");
    try parser.addOption("long-name", 'l', "Just some longer message to test out the help printing");

    // The same with positional arguments, just without the short name. The order of these calls dictate the position in the cli
    try parser.addArgument("age", "The age of the user, who wants to be greeted");
    try parser.addArgument("name", "The name of the user, who wants to be called out");

    // The parsing happens lazily on the first access, so you don't need to start it by yourself

    // You can print an automatically generated Usage message
    if (try parser.option(bool, "help")) {
        return parser.help(std.io.getStdErr().writer(), 0);
    }

    // To access an option, pass the datatype you want to have. It can fail if the value cannot be parsed into the expected type
    // bools default to false, everything else returns a nullable, so you can use zigs `orelse` keyword for default/fallback values or the capture syntax
    const value = try parser.option(bool, "test");
    const b = try parser.option(bool, "bool");
    const str = try parser.option([]const u8, "str") orelse "";
    const int = try parser.option(i32, "int") orelse -1;

    // To access an argument, pass the expected datatype. Just as .options, it can fail while trying to parse.
    // As Arguments are required, it does not return a nullable, but it returns an error when the argument is missing
    // The help function takes a return code, to make this pattern very easy.
    const name = parser.argument([]const u8, "name") catch return parser.help(std.io.getStdErr().writer(), 64);
    const age = parser.argument(u8, "age") catch return parser.help(std.io.getStdErr().writer(), 64);

    std.debug.print("flag test: {}\n", .{value});
    std.debug.print("flag bool: {}\n", .{b});
    std.debug.print("option str: {s}\n", .{str});
    std.debug.print("option int: {d}\n", .{int});
    std.debug.print("arg name: {s}\n", .{name});
    std.debug.print("arg age: {d}\n", .{age});

    return 0;
}
