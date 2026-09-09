const std = @import("std");
const consts = @import("constants.zig");

pub const State = struct {
    rpm: f32 = 0,
    crank_angle: f64 = 0,
    idle: f32 = consts.IDLE,
    limiter: f32 = consts.LIMITER,
    decel_rate: f32 = (consts.LIMITER - consts.IDLE) / consts.STOP_TIME,
    accel_rate: f32 = consts.ACCEL_RATE,

    pub fn simulate(self: *State, dt: f32, gas: f32, brake: f32) void {
        const accel = self.accel_rate * gas;
        const decel = self.decel_rate * (1 - gas + brake * consts.BRAKE_MUL);
        const new_rpm = self.rpm + (accel - decel) * dt;
        if (brake > 0) {
            self.rpm = std.math.clamp(new_rpm, 0, self.limiter);
        } else {
            self.rpm = std.math.clamp(new_rpm, self.idle, self.limiter);
        }

        self.crank_angle += self.rpm / 60.0 * dt * 360;
        self.crank_angle = @mod(self.crank_angle, 360);
    }
};
