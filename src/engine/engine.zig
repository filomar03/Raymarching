const std = @import("std");

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

    pub fn init(self: *Self, kind: Kind, buf: []u8) void {
        switch (kind) {
            .STDOUT => self.stdout = std.fs.File.stdout().writer(buf),
            .STDERR => self.stderr = std.fs.File.stderr().writer(buf),
        }
    }

    pub fn writer(self: *Self, console: Kind) *std.Io.Writer {
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
