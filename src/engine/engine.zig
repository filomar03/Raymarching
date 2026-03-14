const std = @import("std");
const glm = @import("glm.zig");

pub const EngineState = struct {
    console: ConsoleInterface = .{},
    pipeline: ?Pipeline = null,
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
        return .{
            .stdout = std.fs.File.stdout().writer(buf),
            .stderr = std.fs.File.stderr().writer(buf)
        };
    }

    pub fn writer(self: *Self, console: Kind) *std.Io.Writer {
        return &switch (console) {
            .STDOUT => self.stdout.?,
            .STDERR => self.stderr.?,
        }.interface;
    }
};

pub const Pipeline = struct {
    program: *const c_uint,
    uniforms: UniformLocations,

    const UniformLocations = struct {
        resolution: c_int,
        time: c_int,
        mouse: c_int,
        fov: c_int,
    };
};

// const DEF_FOV = 70.0;

// pub const CameraOptions = struct {
//     def_fov: f32 = DEF_FOV,
// };

// pub const Camera = fn (comptime options: CameraOptions) type {
//     return struct {

//     }
// };
