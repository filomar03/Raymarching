// Parametri finestra
const WINDOW_WIDTH = 800;
const WINDOW_HEIGHT = 800;
const VSYNC_SETTING = VSYNC_ON;

// Update console
const DBG_UPDATE_INTERVAL: f32 = 0.5;

// Path shader
const SHADER_DIR = "src/shaders";
const VERTEX_SHADER_FILE = "vertex.glsl";
const FRAGMENT_SHADER_FILE = "fragment.glsl";

// Parametri shader
const MAX_SHADER_SIZE = 1024 * 1024; // 1 Mib
const INFO_LOG_MAX = 512;

// Versione opengl
const OPENGL_MAJOR = 3;
const OPENGL_MINOR = 3;

const VSYNC_ON = 1;
const VSYNC_OFF = 0;

const std = @import("std");
const glfw = @import("zglfw");
const opengl = @import("zopengl");
const engine = @import("engine/state.zig");
const glm = @import("engine/glm.zig");
const zm = @import("zmath");
const sim = @import("simulation.zig");

const gl = opengl.bindings;
const Console = engine.ConsoleInterface.Kind;

const state = &engine.state;

fn createWindow(title: [:0]const u8) !*glfw.Window {
    glfw.windowHint(glfw.WindowHint.context_version_major, OPENGL_MAJOR);
    glfw.windowHint(glfw.WindowHint.context_version_minor, OPENGL_MINOR);
    glfw.windowHint(glfw.WindowHint.opengl_profile, glfw.OpenGLProfile.opengl_core_profile);

    const window = try glfw.createWindow(WINDOW_WIDTH, WINDOW_HEIGHT, title, null, null);

    glfw.makeContextCurrent(window);
    glfw.swapInterval(VSYNC_SETTING);

    try opengl.loadCoreProfile(glfw.getProcAddress, OPENGL_MAJOR, OPENGL_MINOR);

    var fb_width: c_int = undefined;
    var fb_height: c_int = undefined;
    glfw.getFramebufferSize(window, &fb_width, &fb_height);
    gl.viewport(0, 0, fb_width, fb_height);

    _ = glfw.setFramebufferSizeCallback(window, &fbResizeCallback);
    _ = glfw.setScrollCallback(window, &scrollCallback);

    try glfw.setInputMode(window, glfw.InputMode.cursor, glfw.Cursor.Mode.disabled);
    if (glfw.rawMouseMotionSupported()) {
        try glfw.setInputMode(window, glfw.InputMode.raw_mouse_motion, true);
    }

    return window;
}

const VERT_SIZE = 3;
const canvas = [_]gl.Float{
    -1.0, -1.0, -1.0,
    -1.0,  1.0, -1.0,
     1.0,  1.0, -1.0,

    -1.0, -1.0, -1.0,
     1.0,  1.0, -1.0,
     1.0, -1.0, -1.0,
};

fn setupCanvas(vbo: [*c]gl.Uint, vao: [*c]gl.Uint) void {
    gl.genBuffers(1, vbo);
    gl.genVertexArrays(1, vao);

    gl.bindBuffer(gl.ARRAY_BUFFER, vbo.*);
    gl.bindVertexArray(vao.*);

    gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(canvas)), &canvas, gl.STATIC_DRAW);

    gl.vertexAttribPointer(0, VERT_SIZE, gl.FLOAT, gl.FALSE, @sizeOf([VERT_SIZE]gl.Float), @ptrFromInt(0));
    gl.enableVertexAttribArray(0);
}

const Shaders = struct {
    vertex: [:0]const u8,
    fragment: [:0]const u8,
};

fn loadShaders(allocator: std.mem.Allocator) !Shaders {
    var shader_dir = try std.fs.cwd().openDir(SHADER_DIR, .{});
    defer shader_dir.close();
    return .{
        .vertex = try shader_dir.readFileAllocOptions(
            allocator,
            VERTEX_SHADER_FILE,
            MAX_SHADER_SIZE,
            null,
            .of(u8),
            0
        ),
        .fragment = try shader_dir.readFileAllocOptions(
            allocator,
            FRAGMENT_SHADER_FILE,
            MAX_SHADER_SIZE,
            null,
            .of(u8),
            0
        ),
    };
}

fn setupPipeline(shaders: Shaders, window: *glfw.Window) !void {
    var stderr = state.console.writer(Console.STDERR);

    const vert_shad = gl.createShader(gl.VERTEX_SHADER);
    const frag_shad = gl.createShader(gl.FRAGMENT_SHADER);

    gl.shaderSource(vert_shad, 1, @ptrCast(&shaders.vertex), null);
    gl.shaderSource(frag_shad, 1, @ptrCast(&shaders.fragment), null);

    var info_log: [INFO_LOG_MAX:0]u8 = undefined;
    var log_len: c_int = undefined;
    var shader_compiled: gl.Int = undefined;

    gl.compileShader(vert_shad);
    gl.getShaderiv(vert_shad, gl.COMPILE_STATUS, &shader_compiled);
    if (shader_compiled != gl.TRUE) {
        gl.getShaderInfoLog(vert_shad, INFO_LOG_MAX, @ptrCast(&log_len), @ptrCast(&info_log));
        try stderr.print("[Vertex shader] {s}", .{info_log[0..@intCast(log_len)]});
        try stderr.flush();
        return;
    }

    gl.compileShader(frag_shad);
    gl.getShaderiv(frag_shad, gl.COMPILE_STATUS, &shader_compiled);
    if (shader_compiled != gl.TRUE) {
        gl.getShaderInfoLog(frag_shad, INFO_LOG_MAX, @ptrCast(&log_len), @ptrCast(&info_log));
        try stderr.print("[Fragment shader] {s}", .{info_log[0..@intCast(log_len)]});
        try stderr.flush();
        return;
    }

    const program = gl.createProgram();

    gl.attachShader(program, vert_shad);
    gl.attachShader(program, frag_shad);

    gl.linkProgram(program);

    var program_linked: gl.Int = undefined;
    gl.getProgramiv(program, gl.LINK_STATUS, &program_linked);
    if (program_linked != gl.TRUE) {
        gl.getProgramInfoLog(program, INFO_LOG_MAX, @ptrCast(&log_len), @ptrCast(&info_log));
        try stderr.print("[Shader program] {s}", .{info_log[0..@intCast(log_len)]});
        try stderr.flush();
        return;
    }

    gl.useProgram(program);

    state.opengl.shader = .{
        .vertex = vert_shad,
        .fragment = frag_shad,
        .program = program,
    };

    state.opengl.uniforms = .{
        .resolution = gl.getUniformLocation(program, "uResolution"),
        .time = gl.getUniformLocation(program, "uTime"),
        .cam_fov = gl.getUniformLocation(program, "uFov"),
        .cam_pos = gl.getUniformLocation(program, "uCamPos"),
        .cam_rot = gl.getUniformLocation(program, "uCamRot"),
        .crank_angle = gl.getUniformLocation(program, "uCrankAngle"),
    };
    const uniforms = &state.opengl.uniforms.?;

    var fb_width: c_int = undefined;
    var fb_height: c_int = undefined;
    glfw.getFramebufferSize(window, &fb_width, &fb_height);

    gl.uniform2f(uniforms.resolution, @floatFromInt(fb_width), @floatFromInt(fb_height));
    gl.uniform1f(uniforms.cam_fov, state.camera.fov);
    gl.uniform3fv(uniforms.cam_pos, 1, &state.camera.position.toArray());
}

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var stdout_buf: [64]u8 = undefined;
    var stderr_buf: [64]u8 = undefined;
    state.console.init(Console.STDOUT, &stdout_buf);
    state.console.init(Console.STDERR, &stderr_buf);
    var stdout = state.console.writer(Console.STDOUT);

    try glfw.init();
    defer glfw.terminate();

    const window = try createWindow("Raymarching demo");
    defer window.destroy();

    var vbo: gl.Uint = undefined;
    var vao: gl.Uint = undefined;
    setupCanvas(@ptrCast(&vbo), @ptrCast(&vao));
    defer gl.deleteBuffers(1, @ptrCast(&vbo));
    defer gl.deleteVertexArrays(1, @ptrCast(&vao));

    const shaders = try loadShaders(allocator);
    defer allocator.free(shaders.vertex);
    defer allocator.free(shaders.fragment);

    try setupPipeline(shaders, window);
    const shader = &state.opengl.shader.?;
    defer gl.deleteShader(shader.vertex);
    defer gl.deleteShader(shader.fragment);
    defer gl.deleteProgram(shader.program);

    const uniform = &state.opengl.uniforms.?;
    var last_dbg_update: f32 = 0;
    while (!window.shouldClose()) {
        const now = @as(f32, @floatCast(glfw.getTime()));
        state.dt = now - state.now;
        state.now = now;

        glfw.pollEvents();
        getInput(window);

        gl.uniform1f(uniform.time, now);
        gl.drawArrays(gl.TRIANGLES, 0, canvas.len / VERT_SIZE);
        window.swapBuffers();

        state.debug.performance.addFrametime(state.dt);
        if (now - last_dbg_update >= DBG_UPDATE_INTERVAL) {
            last_dbg_update = now;
            try stdout.print("\x1b[2J\x1b[H", .{});
            try stdout.print("FPS: {:.0}\n", .{1 / state.debug.performance.getAvgFrameTime()});
            try stdout.print("FOV: {:.0}\n", .{state.camera.fov});
            try stdout.print("SPEED: {:.1} {:.1} {:.1}\n", .{cam_speed.x, cam_speed.y, cam_speed.z});
            try stdout.print("RPM: {:.0}\n", .{@as(u32, @intFromFloat(state.simulation.rpm))});
            try stdout.flush();
        }
    }
}

// Input handling
fn getInput(window: *glfw.Window) void {
    moveCamera(window);
    rotateCamera(window);
    sim.modifyRpm(window);
    detectQuit(window);
}

const CAM_SPEED_DEF = glm.Vec3{ .x = 7.5, .y = 3, .z = 7.5 };
var cam_speed = CAM_SPEED_DEF;

fn moveCamera(window: *glfw.Window) void {
    const forward: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.w) == glfw.Action.press));
    const backwards: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.s) == glfw.Action.press));
    const right: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.d) == glfw.Action.press));
    const left: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.a) == glfw.Action.press));
    const down: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.q) == glfw.Action.press));
    const up: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.e) == glfw.Action.press));
    var input: glm.Vec3 = .{ .x = right + -left, .y = up + -down, .z = forward + -backwards };
    input = input.normalize();

    const cam_forward = state.camera.rotation.rotateVec(input);

    var pos = &state.camera.position;
    pos.* = pos.sum(cam_forward.mul(cam_speed).mul(state.dt));
    const uniforms = &(state.opengl.uniforms orelse return);
    gl.uniform3fv(uniforms.cam_pos, 1, &state.camera.position.toArray());
}

var prev_mx: f64 = 0;
var prev_my: f64 = 0;

const CAM_SENS = 0.002;

pub const Y_AXIS: glm.Vec3 = .{
    .x = 0,
    .y = 1,
    .z = 0,
};

pub const X_AXIS: glm.Vec3 = .{
    .x = 1,
    .y = 0,
    .z = 0,
};

fn rotateCamera(window: *glfw.Window) void {
    var mx: f64 = undefined;
    var my: f64 = undefined;
    glfw.getCursorPos(window, &mx, &my);

    const dmx = @as(f32, @floatCast(mx - prev_mx));
    const dmy = @as(f32, @floatCast(my - prev_my));

    const rot = &state.camera.rotation;
    const uniforms = &(state.opengl.uniforms orelse return);

    const y_angle = dmx * CAM_SENS;
    const y_rot = glm.Quaternion.fromAxis(Y_AXIS, y_angle);
    rot.* = y_rot.mul(rot.*);

    const x_angle = dmy * CAM_SENS;
    const rotated_x_axis = rot.*.rotateVec(X_AXIS);
    const x_rot = glm.Quaternion.fromAxis(rotated_x_axis, x_angle);

    rot.* = x_rot.mul(rot.*).normalize(); // normalize to stop errors from propagating through frames

    gl.uniform4f(uniforms.cam_rot, rot.*.i, rot.*.j, rot.*.k, rot.*.w);

    prev_mx = mx;
    prev_my = my;
}

fn detectQuit(window: *glfw.Window) void {
    if (glfw.getKey(window, glfw.Key.escape) == glfw.Action.press) {
        glfw.setWindowShouldClose(window, true);
    }
}

const FOV_SENS: f32 = 1.0;

fn adjustCamFov(scroll: f32) void {
    const uniforms = &(state.opengl.uniforms orelse return);
    state.camera.setFOV(state.camera.fov + -scroll * FOV_SENS);
    gl.uniform1f(uniforms.cam_fov, state.camera.fov);
}

const CAM_SPEED_MOD_DEF: f32 = 0.25;
var cam_speed_mod: f32 = 1.0;

fn scrollCallback(window: *glfw.Window, x_offset: f64, y_offset: f64) callconv(.c) void {
    _ = x_offset;
    const scroll = @as(f32, @floatCast(y_offset));

    if (glfw.getKey(window, glfw.Key.left_control) == glfw.Action.press) {
        adjustCamFov(scroll);
    } else {
        cam_speed_mod = std.math.clamp(cam_speed_mod + scroll * CAM_SPEED_MOD_DEF, 0.1, 10.0);
        cam_speed = CAM_SPEED_DEF.mul(cam_speed_mod);
    }
}

fn fbResizeCallback(window: *glfw.Window, width: c_int, height: c_int) callconv(.c) void {
    _ = window;

    const uniforms = &(state.opengl.uniforms orelse return);
    gl.uniform2f(uniforms.resolution, @floatFromInt(width), @floatFromInt(height));
    gl.viewport(0, 0, width, height);
}
