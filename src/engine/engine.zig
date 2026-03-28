const std = @import("std");
const glm = @import("glm.zig");

const Vec3 = glm.Vec(3);

pub const State = struct {
    console: ConsoleInterface = .{},
    shader: ?ShaderInterface = null,
    camera: CameraObject = .{},
    dt: f32 = 0,
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
        // TOOD: non devo produrre un valore per evitare di creare
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
    };
};

const CAM_DEF_FOV = 70;
const CAM_DEF_NEAR = 1;

pub const CameraObject = struct {
    fov: f32 = CAM_DEF_FOV,
    near: f32 = CAM_DEF_NEAR,
    position: Vec3 = .{},
};
