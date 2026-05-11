const std = @import("std");
const engine = @import("engine/state.zig");
const glm = @import("engine/glm.zig");

const Kind = engine.ConsoleInterface.Kind;
const Vec3 = glm.Vec(3);

test "engine console interface" {
    var state = engine.State{};
    var buf: [1]u8 = undefined;
    state.console.init(Kind.STDERR, &buf);
    var writer = state.console.writer(Kind.STDERR);
    try writer.print("", .{});
    try writer.flush();
}

test "vectors" {
    const v: Vec3 = .{.x = 12, .y = 3, .z = -1};
    try std.testing.expectEqual(v.lenght(), 12.409673646);
    try std.testing.expectEqual(v.normalize().lenght(), 1);
    try std.testing.expectEqual(v.sum(1), Vec3{.x = 13, .y = 4, .z = 0});
    const v2: Vec3 = .{.x = 1.0/3.0, .y = 2, .z = 0};
    try std.testing.expectEqual(v.mul(v2), Vec3{.x = 4, .y = 6, .z = 0});
}

test "quaternions" {
    const y_axis: Vec3 = .{.x = 0, .y = 1, .z = 0};
    const q = glm.Quaternion.fromAxis(y_axis, 10);
    const p: Vec3 = .{.x = 1, .y = 12, .z = 3};
    _ = q.rotateVec(p);
}
