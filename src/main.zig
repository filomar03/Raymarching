const std = @import("std");
const glfw = @import("zglfw");

pub fn main() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Hello world!\n", .{});

    try stdout.flush(); // Don't forget to flush!
}
