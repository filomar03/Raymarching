const std = @import("std");
const consts = @import("constants.zig").Constants;

pub const Action = enum {
    idle,
    gas,
    brake,
};

pub const State = struct {
    rpm: f32 = 0,
    crank_angle: f64 = 0,
    idle: f32 = consts.IDLE,
    limiter: f32 = consts.LIMITER,
    decel_rate: f32 = (consts.LIMITER - consts.IDLE) / consts.STOP_TIME,
    accel_rate: f32 = consts.ACCELL_RATE,
};

pub fn simulate(self: *State, dt: f32, action: Action) void {
    switch (action) {
        Action.idle => self.idle(dt),
        Action.gas => self.gas(dt),
        Action.brake => self.brake(dt),
    }

    self.crank_angle += self.rpm * (dt / 60.0);
}

fn idle(self: *State, dt: f32) void {
    if (self.rpm >= self.idle) {
        self.rpm = std.math.clamp(self.rpm - self.decel_rate * dt, self.idle, self.limiter);
    } else {
        self.rpm = std.math.clamp(self.rpm - self.decel_rate * dt, 0, self.idle);
    }
}

fn gas(self: *State, dt: f32) void {
    self.rpm = std.math.clamp(self.rpm + self.accel_rate * dt, 0, self.limiter);
}

fn brake(self: *State, dt: f32) void {
    self.rpm = std.math.clamp(self.rpm - std.math.pow(f32, self.decel_rate, 1) * dt, 0, self.limiter);
}
