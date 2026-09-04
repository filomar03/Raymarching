const std = @import("std");
const glfw = @import("zglfw");
const engine = @import("engine");
const sim = @import("simulation");
const consts = @import("constants.zig");
const window = @import("window.zig");
const pipeline = @import("pipeline.zig");

pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    const context = try window.create(.{});
    defer context.destroy();

    var state = engine.state.State{
        .context = context,
    };
    defer state.opengl.cleanup();

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var stdout_buf: [64]u8 = undefined;
    var stderr_buf: [64]u8 = undefined;

    const Console = engine.state.Console;
    state.console.init(Console.Kind.stdout, &stdout_buf);
    state.console.init(Console.Kind.stderr, &stderr_buf);

    var stdout = state.console.writer(Console.Kind.stdout);
    var stderr = state.console.writer(Console.Kind.stderr);

    pipeline.setupCanvas(&state.opengl.vbo, &state.opengl.vao);

    pipeline.setupPipeline(stateObj: (unknown type))
}
//     const shaders = try loadShaders(allocator);
//     defer allocator.free(shaders.vertex);
//     defer allocator.free(shaders.fragment[0]);
//     defer allocator.free(shaders.fragment[1]);

//     try setupPipeline(shaders, window);
//     const pipeline = &state.opengl.pipeline.?;
//     defer gl.deleteShader(pipeline.vertex);
//     defer gl.deleteShader(pipeline.fragment[0]);
//     defer gl.deleteShader(pipeline.fragment[1]);
//     defer gl.deleteProgram(pipeline.program[0]);
//     defer gl.deleteProgram(pipeline.program[1]);

//     // Camera in posizione piu ottimale
//     state.*.camera.position = .{.x = 6.5, .y = 0.0, .z = 3.6 };
//     state.*.camera.rotation = glm.Quaternion.normalize(.{.i = 0.011, .j = -0.581, .k = 0.008, .w = 0.814});

//     const unifs = &state.opengl.uniforms.?;
//     gl.uniform1i(unifs[1].depth_tex, 0);
//     var last_dbg_update: f32 = 0;
//     while (!window.shouldClose()) {
//         const now = @as(f32, @floatCast(glfw.getTime()));
//         state.dt = now - state.now;
//         state.now = now;

//         glfw.pollEvents();
//         getInput(window);

//         // 1st pass
//         gl.bindFramebuffer(gl.FRAMEBUFFER, pipeline.alt_fb);
//         gl.useProgram(pipeline.program[0]);
//         updateUniforms(unifs[0], 0);
//         gl.viewport(0, 0, pipeline.fb_size[0][0], pipeline.fb_size[0][1]);
//         gl.drawArrays(gl.TRIANGLES, 0, canvas.len / VERT_SIZE);

//         // 2nd pass
//         gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
//         gl.useProgram(pipeline.program[1]);
//         updateUniforms(unifs[1], 1);
//         gl.viewport(0, 0, pipeline.fb_size[1][0], pipeline.fb_size[1][1]);
//         gl.drawArrays(gl.TRIANGLES, 0, canvas.len / VERT_SIZE);

//         window.swapBuffers();

//         state.debug.performance.addFrametime(state.dt);
//         if (now - last_dbg_update >= DBG_UPDATE_INTERVAL) {
//             last_dbg_update = now;
//             try stdout.print("\x1b[2J\x1b[H", .{});
//             try stdout.print("FPS: {:.0}\n", .{1 / state.debug.performance.getAvgFrameTime()});
//             try stdout.print("FOV: {:.0}\n", .{state.camera.fov});
//             try stdout.print("SPEED: {:.1} | {:.1} | {:.1}\n", .{cam_speed.x, cam_speed.y, cam_speed.z});
//             const cam_pos = &state.*.camera.position;
//             try stdout.print("POS: {:.1} | {:.1} | {:.1}\n", .{cam_pos.x, cam_pos.y, cam_pos.z});
//             const cam_rot = &state.camera.rotation;
//             try stdout.print("ROT: {:.3} | {:.3} | {:.3} | {:.3}\n", .{cam_rot.i, cam_rot.j, cam_rot.k, cam_rot.w});
//             try stdout.print("RPM: {:.0}\n", .{@as(u32, @intFromFloat(state.simulation.rpm))});
//             try stdout.flush();
//         }
//     }
// }

// fn getInput(window: *glfw.Window) void {
//     // Disabilitati per testare diffferenze visive con parametri diversi
//     // moveCamera(window);
//     // rotateCamera(window);
//     sim.modifyRpm(window);
//     detectQuit(window);
// }

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

// const CAM_SPEED_DEF = glm.Vec3{ .x = 7.5, .y = 3, .z = 7.5 };
// var cam_speed = CAM_SPEED_DEF;

// fn moveCamera(window: *glfw.Window) void {
//     const forward: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.w) == glfw.Action.press));
//     const backwards: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.s) == glfw.Action.press));
//     const right: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.d) == glfw.Action.press));
//     const left: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.a) == glfw.Action.press));
//     const up: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.e) == glfw.Action.press));
//     const down: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.q) == glfw.Action.press));
//     const jump: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.space) == glfw.Action.press));
//     const crouch: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.left_control) == glfw.Action.press));

//     const world_mov: glm.Vec3 = .{ .x = 0, .y = (jump + -crouch) * cam_speed.y, .z = 0 };
//     const cam_mov: glm.Vec3 = .{ .x = right + -left, .y = up + -down, .z = forward + -backwards };
//     var cam_forward = state.camera.rotation.rotateVec(cam_mov);

//     cam_forward = cam_forward.sum(world_mov).normalize();

//     var pos = &state.camera.position;
//     pos.* = pos.sum(cam_forward.mul(cam_speed).mul(state.dt));
// }

// var prev_mx: f64 = 0;
// var prev_my: f64 = 0;

// const CAM_SENS = 0.002;

// pub const Y_AXIS: glm.Vec3 = .{
//     .x = 0,
//     .y = 1,
//     .z = 0,
// };

// pub const X_AXIS: glm.Vec3 = .{
//     .x = 1,
//     .y = 0,
//     .z = 0,
// };

// fn rotateCamera(window: *glfw.Window) void {
//     var mx: f64 = undefined;
//     var my: f64 = undefined;
//     glfw.getCursorPos(window, &mx, &my);

//     const dmx = @as(f32, @floatCast(mx - prev_mx));
//     const dmy = @as(f32, @floatCast(my - prev_my));

//     const rot = &state.camera.rotation;

//     const y_angle = dmx * CAM_SENS;
//     const y_rot = glm.Quaternion.fromAxis(Y_AXIS, y_angle);
//     rot.* = y_rot.mul(rot.*);

//     const x_angle = dmy * CAM_SENS;
//     const rotated_x_axis = rot.*.rotateVec(X_AXIS);
//     const x_rot = glm.Quaternion.fromAxis(rotated_x_axis, x_angle);

//     rot.* = x_rot.mul(rot.*).normalize(); // normalize to stop errors from propagating through frames

//     prev_mx = mx;
//     prev_my = my;
// }

// fn detectQuit(window: *glfw.Window) void {
//     if (glfw.getKey(window, glfw.Key.escape) == glfw.Action.press) {
//         glfw.setWindowShouldClose(window, true);
//     }
// }

// const FOV_SENS: f32 = 1.0;

// fn adjustCamFov(scroll: f32) void {
//     state.camera.setFOV(state.camera.fov + -scroll * FOV_SENS);
// }

// const CAM_SPEED_MOD_DEF: f32 = 0.25;
// var cam_speed_mod: f32 = 1.0;

// fn scrollCallback(window: *glfw.Window, x_offset: f64, y_offset: f64) callconv(.c) void {
//     _ = x_offset;
//     const scroll = @as(f32, @floatCast(y_offset));

//     if (glfw.getKey(window, glfw.Key.left_shift) != glfw.Action.press) {
//         adjustCamFov(scroll);
//     } else {
//         cam_speed_mod = std.math.clamp(cam_speed_mod + scroll * CAM_SPEED_MOD_DEF, 0.1, 10.0);
//         cam_speed = CAM_SPEED_DEF.mul(cam_speed_mod);
//     }
// }

// fn fbResizeCallback(window: *glfw.Window, width: c_int, height: c_int) callconv(.c) void {
//     _ = window;
//     _ = width;
//     _ = height;

//     std.debug.panic("Resizing should be disabled", .{});
// }
