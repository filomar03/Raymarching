const std = @import("std");
const glm = @import("zmath");

pub const EngineState = struct {
    console: ConsoleInterface = .{},
    pipeline: ?Pipeline = null,
    camera: CameraObject(.{}), // TODO: sistemare il problema nella creazione della cam default, probabilmente cambiare dato che non ha senso che i parametri def facciano parte della signature del tipo
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
            .STDOUT => self.stdout.?, // TODO: fare panic dicendo di chiamare init prima
            .STDERR => self.stderr.?, // TODO: fare panic dicendo di chiamare init prima
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
        cam_pos: c_int,
    };
};

const DEF_CAM_FOV = 70.0;
const DEF_CAM_SPEED = 1.0;

pub const CameraOptions = struct {
    def_fov: f32 = DEF_CAM_FOV,
    def_speed: f32 = DEF_CAM_SPEED
};

pub fn CameraObject (comptime opts: CameraOptions) type {
    return struct {
        const Self = @This();

        fov: f32 = opts.def_fov,
        position: [3]f32 = @splat(0.0),
        speed: f32 = opts.def_speed,

        pub fn reset(self: *Self) void {
            self.* = .{};
        }
    };
}
