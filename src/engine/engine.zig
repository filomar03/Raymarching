const std = @import("std");
const glm = @import("zmath");

pub const State = struct {
    console: ConsoleInterface = .{},
    shader: ?ShaderInterface = null,
    camera: ?CameraObject = null,
};

pub const ConsoleInterface = struct {
    stdout: ?std.fs.File.Writer = null,
    stderr: ?std.fs.File.Writer = null,

    pub const Kind = enum {
        STDOUT,
        STDERR,
    };

    const Self = @This();

    pub fn init(buf: []u8) Self {
        // TOOD: avere un buf a testa
        return .{
            .stdout = std.fs.File.stdout().writer(buf),
            .stderr = std.fs.File.stderr().writer(buf)
        };
    }

    pub fn writer(self: *Self, console: Kind) *std.Io.Writer {
        // TODO: fare panic dicendo di chiamare init prima
        //       e verificare che vada bene prendere il
        //       puntatore del tipo restituiuto dallo switch
        return &switch (console) {
            .STDOUT => self.stdout.?,
            .STDERR => self.stderr.?,
        }.interface;
    }
};

pub const ShaderInterface = struct {
    program: *const c_uint,
    uniforms: UniformLocations,

    const UniformLocations = struct {
        resolution: c_int,
        time: c_int,
        mouse: c_int,
        fov: c_int,
    };
};

pub const CameraObject = struct {
    fov: f32,
    near_plane: f32,
    position: [3]f32,
    speed: f32,
    speed_modifier: f32,
};
