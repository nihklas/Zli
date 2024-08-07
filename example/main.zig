const std = @import("std");
const zli = @import("zli");

pub fn main() void {
    std.debug.print("1 + 2 = {d}\n", .{zli.add(1, 2)});
}
