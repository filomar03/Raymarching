const std = @import("std");
const glm = @import("glm.zig");

pub const State = struct {
    console: ConsoleInterface = .{},
    shader: ?ShaderInterface = null,
    camera: CameraObject = .{},
    dt: f32 = 0,
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
        // TODO: non devo produrre un valore per evitare di creare
        // un local e quindi ritornare un puntatore invalido
        return &switch (console) {
            .STDOUT => self.stdout orelse @panic("stdout not initialized"),
            .STDERR => self.stderr orelse @panic("stderr not initialized"),
        }.interface;
    }
};

pub const ShaderInterface = struct {
    program: *const c_uint,
    uniforms: UniformLocations,

    const UniformLocations = struct {
        resolution: c_int,
        time: c_int,
        cam_fov: c_int,
        cam_near: c_int,
        cam_pos: c_int,
        cam_rot: c_int,
    };
};

const CAM_DEF_FOV = 70;
const CAM_DEF_NEAR = 1;

pub const CameraObject = struct {
    fov: f32 = CAM_DEF_FOV,
    near: f32 = CAM_DEF_NEAR,
    position: glm.Vec3 = .{},
    rotation: glm.Quaternion = .{},
};

const FRAMETIME_RBUF_DIM = 60;

pub const DebugInfo = struct {
    frametime_rbuf: @Vector(FRAMETIME_RBUF_DIM, f32) = @splat(0),
    rbuf_idx: u32 = 0,

    const Self = @This();

    pub fn addFrametime(self: *Self, ft: f32) void {
        self.frametime_rbuf[self.rbuf_idx] = ft;
        self.rbuf_idx = (self.rbuf_idx + 1) % FRAMETIME_RBUF_DIM;
    }

    pub fn getAvgFrameTime(self: Self) f32 {
        const acc: f32 = @reduce(std.builtin.ReduceOp.Add, self.frametime_rbuf);
        return acc / FRAMETIME_RBUF_DIM;
    }
};
