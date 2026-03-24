const std = @import("std");
const math = std.math;

// TODO: finire e testare tuta sta merda

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    const Self = @This();

    pub fn length (self: *Self) f32 {
        var acc = 0;

        var stderr = std.fs.File.stderr().writer([0]u8);
        for (@typeInfo(Self).@"struct".fields) |field, i| {
            try stderr.interface.print("{}: {s}, {s}\n", .{i, field.name, @typeName(field.type)});
            acc += math.pow(f32, @field(self, field.name), 2);
        }

        for (@typeInfo(Self).@"struct".decls) |decl, i| {
            try stderr.interface.print("{}: {s}\n", .{i, decl.name});
        }

        return @sqrt(acc);
    }

    pub fn normalize(self: Self) Self {
        const l = self.length();

        var res: Self = .{};

        for (@typeInfo(Self).@"struct".fields) |field| {
            @field(res, field.name) = @field(self, field.name) / l;
        }

        return res;
    }

    pub fn normalized(self: *Self) void {
        self = self.normalize();
    }

    pub fn sum(self: *Self, other: anytype) Self {
        var res: Self = .{};

        for (@typeInfo(Self).@"struct".fields) |field| {
            const val = @field(self, field.name);
            @field(res, field.name) = val + {
                if (@TypeOf(other) == Self) {
                    @field(other, field.name);
                } else {
                    switch (@typeInfo(@TypeOf(other))) {
                        .float, .comptime_float => other,
                        .int, .comptime_int => @as(f32, @floatFromInt(other)),
                        else => @compileError(std.fmt.comptimePrint("{} only support {} or scalar types ", .{@src().fn_name, @typeName(Self)}))
                    }
                }
            };
        }

        return res;
    }

    pub fn mul(self: *Self, other: anytype) Self {
        var res: Self = .{};

        for (@typeInfo(Self).@"struct".fields) |field| {
            const val = @field(self, field.name);
            @field(res, field.name) = val * {
                if (@TypeOf(other) == Self) {
                    @field(other, field.name);
                } else {
                    switch (@typeInfo(@TypeOf(other))) {
                        .float, .comptime_float => other,
                        .int, .comptime_int => @as(f32, @floatFromInt(other)),
                        else => @compileError(std.fmt.comptimePrint("{} only support {} or scalar types ", .{@src().fn_name, @typeName(Self)}))
                    }
                }
            };
        }

        return res;
    }

    pub fn dot(self: Self, other: Self) f32 {
        @compileError("Not implemented");
    }
};

pub fn Vec(comptime usize) type {
    var vec_struct = struct {

    }

    var vec_type = @typeInfo(@TypeOf(vec_struct));

    vec_type.@"struct".decls
}
