const std = @import("std");
const engine = @import("engine/engine.zig");
const glm = @import("engine/glm.zig");
const Kind = engine.ConsoleInterface.Kind;

test "engine console interface" {
    var state = engine.State{};
    var buf: [1]u8 = undefined;
    state.console.init(Kind.STDERR, &buf);
    var writer = state.console.writer(Kind.STDERR);
    try writer.print("print test");
    try writer.flush();
}

test "vectors" {

}
