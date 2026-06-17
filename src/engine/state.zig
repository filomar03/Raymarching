const std = @import("std");
const glm = @import("glm.zig");
const glfw = @import("zglfw");
const sim = @import("../simulation.zig");

pub var state: State = .{};

pub const State = struct {
    console: ConsoleInterface = .{},
    opengl: OpenGL = .{},
    camera: CameraObject = .{},
    now: f32 = 0,
    dt: f32 = 0,
    simulation: sim.SimulState = .{},
    debug: DebugInfo = .{},
};

pub const ConsoleInterface = struct {
    stdout: ?std.fs.File.Writer = null,
    stderr: ?std.fs.File.Writer = null,

    pub const Kind = enum {
        STDOUT,
        STDERR,
    };

    const Self = @This();

    pub fn init(self: *Self, kind: Kind, buf: []u8) void {
        switch (kind) {
            .STDOUT => self.stdout = std.fs.File.stdout().writer(buf),
            .STDERR => self.stderr = std.fs.File.stderr().writer(buf),
        }
    }

    pub fn writer(self: *Self, console: Kind) *std.Io.Writer {
        return &(switch (console) {
            .STDOUT => self.stdout,
            .STDERR => self.stderr,
        } orelse @panic("console not initialized")).interface;
    }
};

pub const OpenGL = struct {
    shader: ?ShaderInfo = null,
    uniforms: ?UniformLocations = null,

    const ShaderInfo = struct {
        vertex: c_uint,
        fragment: c_uint,
        program: c_uint,
    };

    const UniformLocations = struct {
        resolution: c_int,
        time: c_int,
        cam_fov: c_int,
        cam_pos: c_int,
        cam_rot: c_int,
        crank_angle: c_int,
    };
};

const CAM_DEF_FOV = 60;
pub const FOV_MIN = 30;
pub const FOV_MAX = 120;

pub const CameraObject = struct {
    fov: f32 = CAM_DEF_FOV,
    position: glm.Vec3 = .{},
    rotation: glm.Quaternion = .{},

    const Self = @This();

    pub fn setFOV(self: *Self, fov: f32) void {
        self.fov = std.math.clamp(fov, FOV_MIN, FOV_MAX);
    }
};


pub const DebugInfo = struct {
    performance: PerfInfo = .{},
};

const FRAMETIME_RBUF_DIM = 64; // power of 2 to enable modulo optimization (& insted of %)

pub const PerfInfo = struct {
    frametime_rbuf: [FRAMETIME_RBUF_DIM]f32 = [_]f32{0} ** FRAMETIME_RBUF_DIM,
    rbuf_idx: u32 = 0,
    frametimes_sum: f32 = 0,

    const Self = @This();

    pub fn addFrametime(self: *Self, ft: f32) void {
        self.frametimes_sum -= self.frametime_rbuf[self.rbuf_idx];
        self.frametimes_sum += ft;
        self.frametime_rbuf[self.rbuf_idx] = ft;
        self.rbuf_idx = (self.rbuf_idx + 1) & (FRAMETIME_RBUF_DIM - 1);
    }

    pub fn getAvgFrameTime(self: Self) f32 {
        return self.frametimes_sum / FRAMETIME_RBUF_DIM;
    }
};
