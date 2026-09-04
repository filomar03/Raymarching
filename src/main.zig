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

    var state = engine.State{
        .context = context,
    };
    defer state.opengl.cleanup();

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    _ = allocator;

    var stdout_buf: [64]u8 = undefined;
    var stderr_buf: [64]u8 = undefined;

    const Console = engine.state.Console;
    state.console.init(Console.Kind.stdout, &stdout_buf);
    state.console.init(Console.Kind.stderr, &stderr_buf);

    var stdout = state.console.writer(Console.Kind.stdout);
    var stderr = state.console.writer(Console.Kind.stderr);

    _ = &stdout;
    _ = &stderr;

    state.opengl.setupCanvas();
    state.opengl.setupPipeline();

    state.*.camera.position = .{.x = 6.5, .y = 0.0, .z = 3.6 };
    state.*.camera.rotation = glm.Quaternion.normalize(.{
        .i = 0.011,
        .j = -0.581,
        .k = 0.008,
        .w = 0.814
    });

    var last_dbg_update: f32 = 0;
    while (!state.opengl.context.shouldClose()) {
        const now = @as(f32, @floatCast(glfw.getTime()));
        state.dt = now - state.now;
        state.now = now;

        glfw.pollEvents();
        getInput(state);

        // 1st pass
        

        // 2nd pass
        gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
        gl.useProgram(pipeline.program[1]);
        updateUniforms(unifs[1], 1);
        gl.viewport(0, 0, pipeline.fb_size[1][0], pipeline.fb_size[1][1]);
        gl.drawArrays(gl.TRIANGLES, 0, canvas.len / VERT_SIZE);

        glfw.window.swapBuffers();

        state.debug.performance.addFrametime(state.dt);
        if (now - last_dbg_update >= DBG_UPDATE_INTERVAL) {
            last_dbg_update = now;
            try stdout.print("\x1b[2J\x1b[H", .{});
            try stdout.print("FPS: {:.0}\n", .{1 / state.debug.performance.getAvgFrameTime()});
            try stdout.print("FOV: {:.0}\n", .{state.camera.fov});
            try stdout.print("SPEED: {:.1} | {:.1} | {:.1}\n", .{cam_speed.x, cam_speed.y, cam_speed.z});
            const cam_pos = &state.*.camera.position;
            try stdout.print("POS: {:.1} | {:.1} | {:.1}\n", .{cam_pos.x, cam_pos.y, cam_pos.z});
            const cam_rot = &state.camera.rotation;
            try stdout.print("ROT: {:.3} | {:.3} | {:.3} | {:.3}\n", .{cam_rot.i, cam_rot.j, cam_rot.k, cam_rot.w});
            try stdout.print("RPM: {:.0}\n", .{@as(u32, @intFromFloat(state.simulation.rpm))});
            try stdout.flush();
        }
    }

    gpa.detectLeaks();
}

fn getInput(state: engine.State) void {
    // moveCamera(context);
    // rotateCamera(context);
    detectQuit(state.opengl.context);
}

// fn updateUniforms(locations: engine.OpenGL.UniformLocations, pass: u32) void {
//     const fb_size = state.*.opengl.pipeline.?.fb_size;
//     gl.uniform2f(locations.resolution, @as(f32, @floatFromInt(fb_size[pass][0])), @as(f32, @floatFromInt(fb_size[pass][1])));
//     gl.uniform3fv(locations.cam_pos, 1, &state.camera.position.toArray());
//     const rot = &state.*.camera.rotation;
//     gl.uniform4f(locations.cam_rot, rot.*.i, rot.*.j, rot.*.k, rot.*.w);
//     gl.uniform1f(locations.cam_fov, state.camera.fov);
//     gl.uniform1f(locations.time, state.now);
//     gl.uniform1f(locations.crank_angle, @floatCast(state.simulation.crank_angle));
// }

var cam_speed = consts.CAM_SPEED_DEF;

fn moveCamera(context: *glfw.Window) void {
    const forward: f32 = @floatFromInt(@intFromBool(glfw.getKey(context, glfw.Key.w) == glfw.Action.press));
    const backwards: f32 = @floatFromInt(@intFromBool(glfw.getKey(context, glfw.Key.s) == glfw.Action.press));
    const right: f32 = @floatFromInt(@intFromBool(glfw.getKey(context, glfw.Key.d) == glfw.Action.press));
    const left: f32 = @floatFromInt(@intFromBool(glfw.getKey(context, glfw.Key.a) == glfw.Action.press));
    const up: f32 = @floatFromInt(@intFromBool(glfw.getKey(context, glfw.Key.e) == glfw.Action.press));
    const down: f32 = @floatFromInt(@intFromBool(glfw.getKey(context, glfw.Key.q) == glfw.Action.press));
    const jump: f32 = @floatFromInt(@intFromBool(glfw.getKey(context, glfw.Key.space) == glfw.Action.press));
    const crouch: f32 = @floatFromInt(@intFromBool(glfw.getKey(context, glfw.Key.left_control) == glfw.Action.press));

    const world_mov: glm.Vec3 = .{ .x = 0, .y = (jump + -crouch) * cam_speed.y, .z = 0 };
    const cam_mov: glm.Vec3 = .{ .x = right + -left, .y = up + -down, .z = forward + -backwards };
    var cam_forward = state.camera.rotation.rotateVec(cam_mov);

    cam_forward = cam_forward.sum(world_mov).normalize();

    var pos = &state.camera.position;
    pos.* = pos.sum(cam_forward.mul(cam_speed).mul(state.dt));
}

var prev_mx: f64 = 0;
var prev_my: f64 = 0;

fn rotateCamera(context: *glfw.Window) void {
    var mx: f64 = undefined;
    var my: f64 = undefined;
    glfw.getCursorPos(context, &mx, &my);

    const dmx = @as(f32, @floatCast(mx - prev_mx));
    const dmy = @as(f32, @floatCast(my - prev_my));

    const rot = &state.camera.rotation;

    const y_angle = dmx * consts.CAM_SENS;
    const y_rot = glm.Quaternion.fromAxis(Y_AXIS, y_angle);
    rot.* = y_rot.mul(rot.*);

    const x_angle = dmy * consts.CAM_SENS;
    const rotated_x_axis = rot.*.rotateVec(X_AXIS);
    const x_rot = glm.Quaternion.fromAxis(rotated_x_axis, x_angle);

    rot.* = x_rot.mul(rot.*).normalize(); // normalize to stop errors from propagating through frames

    prev_mx = mx;
    prev_my = my;
}

fn detectQuit(context: *glfw.Window) void {
    if (glfw.getKey(context, glfw.Key.escape) == glfw.Action.press) {
        glfw.setWindowShouldClose(context, true);
    }
}

fn adjustCamFov(scroll: f32) void {
    _ = scroll;
    // state.camera.setFOV(state.camera.fov + -scroll * consts.FOV_SENS);
}

var cam_speed_mod: f32 = 1.0;

fn scrollCallback(context: *glfw.Window, x_offset: f64, y_offset: f64) callconv(.c) void {
    _ = x_offset;
    const scroll = @as(f32, @floatCast(y_offset));

    if (glfw.getKey(context, glfw.Key.left_shift) != glfw.Action.press) {
        adjustCamFov(scroll);
    } else {
        cam_speed_mod = std.math.clamp(cam_speed_mod + scroll * consts.CAM_SPEED_MOD_DEF, 0.1, 10.0);
        cam_speed = consts.CAM_SPEED_DEF.mul(cam_speed_mod);
    }
}
