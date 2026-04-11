const std = @import("std");
const math = std.math;

const Vec3 = Vec(3);

const EPS = 1e-6;
inline fn approxEq(a: f32, b: f32) bool {
    return std.math.approxEqAbs(f32, a, b, EPS);
}

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

        pub fn lenghtSq(self: Self) f32 {
            var acc: f32 = 0;

            inline for (@typeInfo(Self).@"struct".fields[0..dim]) |field| {
                acc += math.pow(f32, @field(self, field.name), 2);
            }

            return acc;
        }

        pub fn lenght(self: Self) f32 {
            return @sqrt(self.lenghtSq());
        }

        pub fn isUnit(self: Self) bool {
            return approxEq(self.lenghtSq(), 1);
        }

        pub fn normalize(self: Self) Self {
            const l = self.lenght();

            if (approxEq(l, 0) or approxEq(l, 1)) return self;

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

        pub fn cross(self: Self, other: Self) f32 {
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

pub const Quaternion = struct {
    w: f32 = 1,
    i: f32 = 0,
    j: f32 = 0,
    k: f32 = 0,

    const Self = @This();

    pub fn fromAxis(axis: Vec3, angle: f32) Self {
        if (axis.lenght() != 1.0) {
            @panic("Cannot create a quaternion from a non normalized axis");
        }

        const cos = math.cos(angle / 2);
        const sin = math.sin(angle / 2);

        return .{
            .w = cos,
            .i = sin * axis.x,
            .j = sin * axis.y,
            .k = sin * axis.z,
        };
    }

    pub fn createPure(point: Vec3) Self {
        return .{
            .w = 0,
            .i = point.x,
            .j = point.y,
            .k = point.z
        };
    }

    pub fn sum(self: Self, other: Self) Self {
        return .{
            .w = self.w + other.w,
            .i = self.i + other.i,
            .j = self.j + other.j,
            .k = self.k + other.k,
        };
    }

    pub fn mul(self: Self, other: Self) Self {
        return .{
            .w = self.w * other.w - self.i * other.i - self.j * other.j - self.k * other.k,
            .i = self.w * other.i + self.i * other.w + self.j * other.k - self.k * other.j,
            .j = self.w * other.j - self.i * other.k + self.j * other.w + self.k * other.i,
            .k = self.w * other.k + self.i * other.j - self.j * other.i + self.k * other.w
        };
    }

    pub fn lenghtSq(self: Self) f32 {
        return self.w * self.w + self.i * self.i + self.j * self.j + self.k * self.k;
    }

    pub fn lenght(self: Self) f32 {
        return math.sqrt(self.lenghtSq());
    }

    pub fn isUnit(self: Self) bool {
        return approxEq(self.lenghtSq(), 1);
    }

    pub fn normalize(self: Self) Self {
        const l = self.lenght();

        if (approxEq(l, 0)) {
            return .{};
        }

        return .{
            .w = self.w / l,
            .i = self.i / l,
            .j = self.j / l,
            .k = self.k / l
        };
    }

    pub fn conjugate(self: Self) Self {
        return .{
            .w = self.w,
            .i = -self.i,
            .j = -self.j,
            .k = -self.k,
        };
    }

    pub fn inverse(self: Self) Self {
        if (self.isUnit()) return self.conjugate();

        const len_sq = self.lenghtSq();

        if (approxEq(len_sq, 0)) {
            @panic("Cannot compute inverse of a zero quaternion");
        }

        return .{
            .w = self.w / len_sq,
            .i = -self.i / len_sq,
            .j = -self.j / len_sq,
            .k = -self.k / len_sq,
        };
    }

    pub fn composeRotation(self: Self, q2: Self) Self {
        const q1 = self.normalize();
        return q1.mul(q2.normalize()).mul(q1.inverse());
    }

    pub fn rotateVec(self: Self, other: Vec3) Vec3 {
        const s = self.normalize();
        return s.mul(Self.createPure(other)).mul(s.inverse()).toVec3();
    }

    pub fn slerp(self: Self, other: Self, alpha: f32) Self {
        _ = self;
        _ = other;
        _ = alpha;
        @panic("Not implemented");
    }

    pub fn toVec3(self: Self) Vec3 {
        return .{
            .x = self.i,
            .y = self.j,
            .z = self.k,
        };
    }
};
