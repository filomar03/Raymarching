const std = @import("std");
const glfw = @import("zglfw");
const engine = @import("engine/state.zig");
const opengl = @import("zopengl");

const gl = opengl.bindings;

const state = &engine.state;

const LIMITER = 7000;
const IDLE = 800;

pub const SimulState = struct {
    rpm: f32 = 0,
    crank_angle: f64 = 0,
    idle: f32 = IDLE,
    limiter: f32 = LIMITER,
    decel_rate: f32 = (LIMITER - IDLE) / 5.0,
    accel_rate: f32 = 1000,
};

pub fn modifyRpm(window: *glfw.Window) void {
    var sim = &state.simulation;

    if (glfw.getMouseButton(window, glfw.MouseButton.right) == glfw.Action.press) {
        sim.rpm = std.math.clamp(sim.rpm - std.math.pow(f32, sim.decel_rate, 1) * state.dt, 0, sim.limiter);
    }

    if (glfw.getMouseButton(window, glfw.MouseButton.left) == glfw.Action.press) {
        sim.rpm = std.math.clamp(sim.rpm + sim.accel_rate * state.dt, 0, sim.limiter);
    } else {
        if (sim.rpm >= sim.idle) {
            sim.rpm = std.math.clamp(sim.rpm - sim.decel_rate * state.dt, sim.idle, sim.limiter);
        } else {
            sim.rpm = std.math.clamp(sim.rpm - sim.decel_rate * state.dt, 0, sim.idle);
        }
    }

    sim.crank_angle += sim.rpm * (state.dt / 60.0);
}
