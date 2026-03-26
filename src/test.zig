const std = @import("std");
const engine = @import("engine/engine.zig");
const glm = @import("engine/glm.zig");
const Kind = engine.ConsoleInterface.Kind;

test "engine console interface" {
    var state = engine.State{};
    var buf: [1]u8 = undefined;
    state.console.init(Kind.STDERR, &buf);
    var writer = state.console.writer(Kind.STDERR);
    try writer.print("[TEST] print succesful!", .{});
    try writer.flush();
}

test "vectors" {
    const Vec3 = glm.Vec(3);
    var v: Vec3 = .{.x = 12, .y = 3, .z = -1};
    try std.testing.expectEqual(v.length(), 12.409673646);
    try std.testing.expectEqual(v.sum(1), Vec3{.x = 13, .y = 4, .z = 0});
}
