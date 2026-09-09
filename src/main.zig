const std = @import("std");
const glfw = @import("zglfw");
const sim = @import("simulation");
const consts = @import("constants.zig");
const Window = @import("window.zig");
const engine = @import("engine.zig");
const glm = @import("glm.zig");
const simState = @TypeOf(sim.new(.{}));

pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    const window = try Window.create(.{});
    defer window.destroy();

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.detectLeaks();

    var state = try engine.State.init(
        window.getFramebufferSize(),
        glfw.getProcAddress
    );
    defer state.opengl.cleanup(allocator);

    window.setUserPointer(&state);
    defer window.setUserPointer(null);

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
    while (!window.shouldClose()) {
        const now = @as(f32, @floatCast(glfw.getTime()));
        state.time.dt = now - state.time.now;
        state.time.now = now;

        glfw.pollEvents();
        getInput(window, &state);

        state.opengl.ubo.update(&state.camera, &state.simulation);
        state.opengl.firstPass();
        state.opengl.secondPass();
        window.swapBuffers();

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

fn getInput(window: *glfw.Window, state: *engine.State) void {
    moveCamera(window, &state.camera, state.time.dt);
    rotateCamera(window, &state.camera);
    advanceSimulation(window, &state.simulation, state.time.dt);
    detectQuit(window);
}

var cam_speed = consts.CAM_SPEED_DEF;
fn moveCamera(window: *glfw.Window, cam: *engine.Camera, dt: f32) void {
    const forward: f32 = @floatFromInt(@intFromBool(window.getKey(glfw.Key.w) == glfw.Action.press));
    const backwards: f32 = @floatFromInt(@intFromBool(window.getKey(glfw.Key.s) == glfw.Action.press));
    const right: f32 = @floatFromInt(@intFromBool(window.getKey(glfw.Key.d) == glfw.Action.press));
    const left: f32 = @floatFromInt(@intFromBool(window.getKey(glfw.Key.a) == glfw.Action.press));
    const up: f32 = @floatFromInt(@intFromBool(window.getKey(glfw.Key.e) == glfw.Action.press));
    const down: f32 = @floatFromInt(@intFromBool(window.getKey(glfw.Key.q) == glfw.Action.press));
    const jump: f32 = @floatFromInt(@intFromBool(window.getKey(glfw.Key.space) == glfw.Action.press));
    const crouch: f32 = @floatFromInt(@intFromBool(window.getKey(glfw.Key.left_control) == glfw.Action.press));

    const cam_mov: glm.Vec3 = .{ .x = right + -left, .y = up + -down, .z = forward + -backwards };
    var world_mov = glm.Vec3{ .y = jump + -crouch };
    world_mov = world_mov.sum(cam.rotation.rotateVec(cam_mov)).normalize();

    cam.position = cam.position.sum(world_mov.mul(cam_speed).mul(dt));
}

var prev_mx: f64 = 0;
var prev_my: f64 = 0;
var have_prev_cursor = false;
fn rotateCamera(window: *glfw.Window, cam: *engine.Camera) void {
    const mx, const my = window.getCursorPos();
    defer {
        prev_mx = mx;
        prev_my = my;
        have_prev_cursor = true;
    }

    // The cursor starts wherever the OS put it, so the first frame's delta is
    // measured against a position we never saw. Skip it instead of slamming the
    // camera away from its initial orientation.
    if (!have_prev_cursor) return;

    const dmx = @as(f32, @floatCast(mx - prev_mx));
    const dmy = @as(f32, @floatCast(my - prev_my));

    const y_angle = dmx * consts.CAM_SENS;
    const x_angle = dmy * consts.CAM_SENS;

    // Yaw around the world up axis, so the horizon never rolls.
    const world_up = glm.Quaternion.fromAxis(consts.Y_AXIS, y_angle);
    const y_rot = world_up.mul(cam.rotation);

    // Pitch around the camera's own right axis, taken after the yaw.
    // rotateVec can drift a few ulps off unit length and fromAxis panics on that.
    const x_axis_local = y_rot.rotateVec(consts.X_AXIS).normalize();
    const x_rot_local = glm.Quaternion.fromAxis(x_axis_local, x_angle);

    // normalize to stop errors from propagating through frames
    const new_rot = x_rot_local.mul(y_rot).normalize();

    // Reject just the pitch when it would tip the camera past vertical and flip
    // the view upside down; the yaw for this frame still applies.
    const forward = new_rot.rotateVec(consts.Z_AXIS);
    cam.rotation = if (@abs(forward.y) > consts.CAM_PITCH_LIMIT)
        y_rot.normalize()
    else
        new_rot;
}

fn advanceSimulation(window: *glfw.Window, simulation: *simState, dt: f32) void {
    const gas: f32 = @floatFromInt(
        @intFromBool(
            window.getMouseButton(glfw.MouseButton.left) == glfw.Action.press
        )
    );
    const brake: f32 = @floatFromInt(
        @intFromBool(
            window.getMouseButton(glfw.MouseButton.right) == glfw.Action.press
        )
    );
    simulation.simulate(dt, gas, brake);
}

fn detectQuit(window: *glfw.Window) void {
    if (window.getKey(glfw.Key.escape) == glfw.Action.press) {
        window.setShouldClose(true);
    }
}

var cam_speed_mod: f32 = 1.0;
fn scrollCallback(window: *glfw.Window, x_offset: f64, y_offset: f64) callconv(.c) void {
    _ = x_offset;
    const scroll = @as(f32, @floatCast(y_offset));

    const state = window.getUserPointer(engine.State);

    if (window.getKey(glfw.Key.left_shift) == glfw.Action.press) {
        cam_speed_mod = std.math.clamp(cam_speed_mod + scroll * consts.CAM_SPEED_MOD_DEF, 0.1, 10.0);
        cam_speed = consts.CAM_SPEED_DEF.mul(cam_speed_mod);
    } else {
        state.?.camera.setFov(state.camera.fov + -scroll * consts.FOV_SENS);
    }
}
