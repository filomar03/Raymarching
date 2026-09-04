pub const State = @import("state.zig").State;
pub const Action = @import("state.zig").Action;
pub const simulate = @import("state.zig").simulate;

pub const SimulationOptions = struct {
    idle: ?f32 = null,
    limiter: ?f32 = null,
    accel_rate: ?f32 = null,
    stop_time: ?f32 = null,
};

pub fn new(options: SimulationOptions) State {
    var s = State{};
    if (options.idle) |idle| s.idle = idle;
    if (options.limiter) |limiter| s.limiter = limiter;
    if (options.accel_rate) |accel_rate| s.accel_rate = accel_rate;
    if (options.stop_time) |stop_time| s.decel_rate = (s.limiter - s.idle) / stop_time;
}
