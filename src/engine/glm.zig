const std = @import("std");
const math = std.math;



pub fn Vec(dim: usize) type {
    if (dim < 2 or dim > 4) {
        @compileError("Vec supports only dimensions between 2 and 4");
    }

    return struct {
        x: f32 = 0,
        y: f32 = 0,
        z: if (dim >= 3) f32 else void = if (dim >= 3) 0 else {},
        w: if (dim >= 4) f32 else void = if (dim >= 4) 0 else {},

        const Self = @This();

        pub fn length (self: Self) f32 {
            var acc: f64 = 0;

            inline for (@typeInfo(Self).@"struct".fields[0..dim]) |field| {
                acc += math.pow(f64, @field(self, field.name), 2);
            }

            return @floatCast(@sqrt(acc));
        }

        pub fn normalize(self: Self) Self {
            const l = self.length();

            if (l == 0.0) return self;

            var res: Self = .{};

            inline for (@typeInfo(Self).@"struct".fields[0..dim]) |field| {
                @field(res, field.name) = @field(self, field.name) / l;
            }

            return res;
        }

        pub fn sum(self: Self, other: anytype) Self {
            var res: Self = .{};

            inline for (@typeInfo(Self).@"struct".fields[0..dim]) |field| {
                const val = @field(self, field.name);
                @field(res, field.name) = val +
                    if (@TypeOf(other) == Self)
                        @field(other, field.name)
                    else
                        switch (@typeInfo(@TypeOf(other))) {
                            .float, .comptime_float => other,
                            .int, .comptime_int => @as(f32, @floatFromInt(other)),
                            else => @compileError(std.fmt.comptimePrint("only {s} or scalars supported", .{@typeName(Self)}))
                        };
            }

            return res;
        }

        pub fn mul(self: Self, other: anytype) Self {
            var res: Self = .{};

            inline for (@typeInfo(Self).@"struct".fields[0..dim]) |field| {
                const val = @field(self, field.name);
                @field(res, field.name) = val *
                    if (@TypeOf(other) == Self)
                        @field(other, field.name)
                    else
                        switch (@typeInfo(@TypeOf(other))) {
                            .float, .comptime_float => other,
                            .int, .comptime_int => @as(f32, @floatFromInt(other)),
                            else => @compileError(std.fmt.comptimePrint("only {s} or scalars supported", .{@typeName(Self)}))
                        };
            }

            return res;
        }

        pub fn dot(self: Self, other: Self) f32 {
            _ = self;
            _ = other;
            @panic("Not implemented");
        }

        pub fn toArray(self: Self) [dim]f32 {
            var a: [dim]f32 = undefined;

            inline for (@typeInfo(Self).@"struct".fields[0..dim], 0..dim) |field, i| {
                a[i] = @field(self, field.name);
            }

            return a;
        }
    };
}
