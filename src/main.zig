const std = @import("std");
const glfw = @import("zglfw");
const sim = @import("simulation");
const consts = @import("constants.zig");
const window = @import("window.zig");
const engine = @import("engine.zig");
const glm = @import("glm.zig");

pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    const context = try window.create(.{});
    defer context.destroy();

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.detectLeaks();

    var state = engine.State{
        .opengl = .{
            .context = context
        }
    };
    defer state.opengl.cleanup(allocator);

    context.setUserPointer(&state);
    defer context.setUserPointer(null);

    var stdout_buf: [64]u8 = undefined;
    var stderr_buf: [64]u8 = undefined;
    const Console = engine.Console;
    state.console.init(Console.Kind.stdout, &stdout_buf);
    state.console.init(Console.Kind.stderr, &stderr_buf);
    var stdout = try state.console.writer(Console.Kind.stdout);
    var stderr = try state.console.writer(Console.Kind.stderr);
    _ = &stderr;

    try state.opengl.setupPipeline(allocator);

    state.camera.position = .{.x = 6.5, .y = 0.0, .z = 3.6 };
    state.camera.rotation = glm.Quaternion.normalize(.{
        .i = 0.011,
        .j = -0.581,
        .k = 0.008,
        .w = 0.814
    });

    var last_dbg_update: f32 = 0;
    while (!state.opengl.context.shouldClose()) {
        const now = @as(f32, @floatCast(glfw.getTime()));
        state.time.dt = now - state.time.now;
        state.time.now = now;

        glfw.pollEvents();
        getInput(&state);

        state.opengl.ubo.update(&state.camera, &state.simulation);
        state.opengl.firstPass();
        state.opengl.secondPass();
        context.swapBuffers();

        state.performance.addFrametime(state.time.dt);
        if (now - last_dbg_update >= consts.DBG_UPDATE_INTERVAL) {
            last_dbg_update = now;
            try stdout.print("\x1b[2J\x1b[H", .{});
            try stdout.print("FPS: {:.0}\n", .{1 / state.performance.getAvgFrameTime()});
            try stdout.print("FOV: {:.0}\n", .{state.camera.fov});
            const cam_pos = &state.camera.position;
            try stdout.print("POS: {:.1} | {:.1} | {:.1}\n", .{cam_pos.x, cam_pos.y, cam_pos.z});
            const cam_rot = &state.camera.rotation;
            try stdout.print("ROT: {:.3} | {:.3} | {:.3} | {:.3}\n", .{cam_rot.i, cam_rot.j, cam_rot.k, cam_rot.w});
            try stdout.print("RPM: {:.0}\n", .{@as(u32, @intFromFloat(state.simulation.rpm))});
            try stdout.print("SPEED: {:.1} | {:.1} | {:.1}\n", .{cam_speed.x, cam_speed.y, cam_speed.z});
            try stdout.flush();
        }
    }
}

fn getInput(state: *engine.State) void {
    moveCamera(state);
    rotateCamera(state);
    advanceSimulation(state);
    detectQuit(state.opengl.context);
}

var cam_speed = consts.CAM_SPEED_DEF;
fn moveCamera(state: *engine.State) void {
    const context = state.opengl.context;
    const forward: f32 = @floatFromInt(@intFromBool(context.getKey(glfw.Key.w) == glfw.Action.press));
    const backwards: f32 = @floatFromInt(@intFromBool(context.getKey(glfw.Key.s) == glfw.Action.press));
    const right: f32 = @floatFromInt(@intFromBool(context.getKey(glfw.Key.d) == glfw.Action.press));
    const left: f32 = @floatFromInt(@intFromBool(context.getKey(glfw.Key.a) == glfw.Action.press));
    const up: f32 = @floatFromInt(@intFromBool(context.getKey(glfw.Key.e) == glfw.Action.press));
    const down: f32 = @floatFromInt(@intFromBool(context.getKey(glfw.Key.q) == glfw.Action.press));
    const jump: f32 = @floatFromInt(@intFromBool(context.getKey(glfw.Key.space) == glfw.Action.press));
    const crouch: f32 = @floatFromInt(@intFromBool(context.getKey(glfw.Key.left_control) == glfw.Action.press));

    const cam_mov: glm.Vec3 = .{ .x = right + -left, .y = up + -down, .z = forward + -backwards };
    var world_mov = glm.Vec3{ .y = jump + -crouch };
    world_mov = world_mov.sum(state.camera.rotation.rotateVec(cam_mov)).normalize();

    var pos = &state.camera.position;
    pos.* = pos.sum(world_mov.mul(cam_speed).mul(state.time.dt));
}

var prev_mx: f64 = 0;
var prev_my: f64 = 0;
fn rotateCamera(state: *engine.State) void {
    const mx, const my = state.opengl.context.getCursorPos();
    const dmx = @as(f32, @floatCast(mx - prev_mx));
    const dmy = @as(f32, @floatCast(my - prev_my));

    const rot = &state.camera.rotation;

    const y_angle = dmx * consts.CAM_SENS;
    const y_rot = glm.Quaternion.fromAxis(consts.Y_AXIS, y_angle);
    rot.* = y_rot.mul(rot.*);

    const x_angle = dmy * consts.CAM_SENS;
    const rotated_x_axis = rot.*.rotateVec(consts.X_AXIS);
    const x_rot = glm.Quaternion.fromAxis(rotated_x_axis, x_angle);

    rot.* = x_rot.mul(rot.*).normalize(); // normalize to stop errors from propagating through frames

    prev_mx = mx;
    prev_my = my;
}

fn advanceSimulation(state: *engine.State) void {
    const context = state.opengl.context;

    const gas: f32 = @floatFromInt(
        @intFromBool(
            context.getMouseButton(glfw.MouseButton.left) == glfw.Action.press
        )
    );

    const brake: f32 = @floatFromInt(
        @intFromBool(
            context.getMouseButton(glfw.MouseButton.right) == glfw.Action.press
        )
    );

    state.simulation.simulate(state.time.dt, gas, brake);
}

fn detectQuit(context: *glfw.Window) void {
    if (context.getKey(glfw.Key.escape) == glfw.Action.press) {
        context.setShouldClose(true);
    }
}

var cam_speed_mod: f32 = 1.0;
fn scrollCallback(context: *glfw.Window, x_offset: f64, y_offset: f64) callconv(.c) void {
    _ = x_offset;
    const scroll = @as(f32, @floatCast(y_offset));

    const state = context.getUserPointer(engine.State);

    if (context.getKey(glfw.Key.left_shift) == glfw.Action.press) {
        cam_speed_mod = std.math.clamp(cam_speed_mod + scroll * consts.CAM_SPEED_MOD_DEF, 0.1, 10.0);
        cam_speed = consts.CAM_SPEED_DEF.mul(cam_speed_mod);
    } else {
        state.?.camera.setFov(state.camera.fov + -scroll * consts.FOV_SENS);
    }
}
