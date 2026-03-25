// const std = @import("std");
// const math = std.math;

// pub const Vec3 = struct {
//     x: f32 = 0,
//     y: f32 = 0,
//     z: f32 = 0,

//     const Self = @This();

//     pub fn length (self: *Self) f32 {
//         var acc: f32 = 0;

//         var y: [1]u8 = undefined;

//         var stderr = std.fs.File.stderr().writer(&y);
//         inline for (@typeInfo(Self).@"struct".fields, 0..) |field, i| {
//             stderr.interface.print("{}: {s}, {*}, {s}\n", .{i, field.name, &field.default_value_ptr.?, @typeName(field.type)}) catch unreachable;
//             acc += math.pow(f32, @field(self, field.name), 2);
//         }

//         for (@typeInfo(Self).@"struct".decls, 0..) |decl, i| {
//             stderr.interface.print("{}: {s}\n", .{i, decl.name}) catch unreachable;
//         }

//         return @sqrt(acc);
//     }

//     pub fn normalize(self: Self) Self {
//         const l = self.length();

//         var res: Self = .{};

//         for (@typeInfo(Self).@"struct".fields) |field| {
//             @field(res, field.name) = @field(self, field.name) / l;
//         }

//         return res;
//     }

//     pub fn normalized(self: *Self) void {
//         self = self.normalize();
//     }

//     pub fn sum(self: *Self, other: anytype) Self {
//         var res: Self = .{};

//         for (@typeInfo(Self).@"struct".fields) |field| {
//             const val = @field(self, field.name);
//             @field(res, field.name) = val + {
//                 if (@TypeOf(other) == Self) {
//                     @field(other, field.name);
//                 } else {
//                     switch (@typeInfo(@TypeOf(other))) {
//                         .float, .comptime_float => other,
//                         .int, .comptime_int => @as(f32, @floatFromInt(other)),
//                         else => @compileError(std.fmt.comptimePrint("{} only support {} or scalar types ", .{@src().fn_name, @typeName(Self)}))
//                     }
//                 }
//             };
//         }

//         return res;
//     }

//     pub fn mul(self: *Self, other: anytype) Self {
//         var res: Self = .{};

//         for (@typeInfo(Self).@"struct".fields) |field| {
//             const val = @field(self, field.name);
//             @field(res, field.name) = val * {
//                 if (@TypeOf(other) == Self) {
//                     @field(other, field.name);
//                 } else {
//                     switch (@typeInfo(@TypeOf(other))) {
//                         .float, .comptime_float => other,
//                         .int, .comptime_int => @as(f32, @floatFromInt(other)),
//                         else => @compileError(std.fmt.comptimePrint("{} only support {} or scalar types ", .{@src().fn_name, @typeName(Self)}))
//                     }
//                 }
//             };
//         }

//         return res;
//     }

//     pub fn dot(self: Self, other: Self) f32 {
//         _ = self;
//         _ = other;
//         @panic("Not implemented");
//     }
// };

// const vec_def_val: f32 = 0;
// pub fn Vec(dim: usize) type {
//     if (dim < 2 or dim > 4) {
//         @compileError("Vec supports only dimensions between 2 and 4");
//     }

//     const names = [_][]const u8{"x", "y", "z", "w"};

//     var fields: [dim]std.builtin.Type.StructField = undefined;

//     inline for (0..dim) |i| {
//         fields[i] = .{
//             .alignment = @alignOf(f32),
//             .default_value_ptr = &vec_def_val,
//             .is_comptime = false,
//             .name = names[i],
//             .type = f32,
//         };
//     }

//     const vec_struct = struct {
//         pub fn length (self: anytype) f32 {
//             var acc: f32 = 0;

//             inline for (@typeInfo(@TypeOf(self)).@"struct".fields) |field| {
//                 acc += math.pow(f32, @field(self, field.name), 2);
//             }

//             return @sqrt(acc);
//         }

//         pub fn sum(self: anytype, other: anytype) @TypeOf(self)  {
//             const Self = @TypeOf(self);
//             const Other = @TypeOf(other);

//             var res: Self = .{};

//             inline for (@typeInfo(Self).@"struct".fields) |field| {
//                 const val = @field(self, field.name);
//                 @field(res, field.name) = val + {
//                     if (Other == Self) {
//                         @field(other, field.name);
//                     } else {
//                         switch (@typeInfo(Other)) {
//                             .float, .comptime_float => other,
//                             .int, .comptime_int => @as(f32, @floatFromInt(other)),
//                             else => @compileError(std.fmt.comptimePrint("{} only support {} or scalar types ", .{@src().fn_name, @typeName(Self)}))
//                         }
//                     }
//                 };
//             }

//             return res;
//         }
//     };

//     const type_info: std.builtin.Type = .{
//         .@"struct" = .{
//             .decls = @typeInfo(vec_struct).@"struct".decls,
//             .fields = fields, // i should pass a slice but don't know how without allocating memory on heap
//             .is_tuple = false,
//             .layout = .auto
//         },
//     };

//     return @Type(type_info);
// }
