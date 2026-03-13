const std = @import("std");

pub const EngineState = struct {
    console: ConsoleInterface = .{},
    uniforms: ?UniformLocations = null,
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
            // TODO: capire se il buffer viene copiato o preso l'indirizzo
            // TODO: capire se con anytype viene fatto il check del tipo
            .stdout = std.fs.File.stdout().writer(buf),
            .stderr = std.fs.File.stderr().writer(buf)
        };
    }

    pub fn writer(self: *Self, console: Kind) *std.Io.Writer {
        return &switch (console) {
            .STDOUT => self.stdout,
            .STDERR => self.stderr,
        }.?.interface;
    }
};

pub const UniformLocations = struct {
    resolution: c_int,
    time: c_int,
    mouse: c_int,
    wheel: c_int,
};
