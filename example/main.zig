const std = @import("std");
const Zli = @import("Zli");

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();
    _ = alloc;

    return 0;
}
