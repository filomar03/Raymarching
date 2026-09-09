// You can edit this code!
// Click into the editor and start typing.
const std = @import("std");
const builtin = @import("builtin");

pub fn main() void {
    const x: comptime_int = 5;
    const y: comptime_int = 2;

    const z = x / y;
    std.testing.expectEqual(2.5, z) catch {};
}
