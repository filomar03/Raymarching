// Parametri rendering
const RES_REDUCTION = 1.0 / 3.0;

// Parametri finestra
const WINDOW_WIDTH = 800;
const WINDOW_HEIGHT = 800;
const VSYNC_SETTING = VSYNC_ON;

// Update console
const DBG_UPDATE_INTERVAL: f32 = 0.5;

// Path shader
const SHADER_DIR = "src/shaders";
const VERTEX_SHADER_FILE = "vertex.glsl";
const PASS1_SHADER_FILE = "fragment fast.glsl";
const PASS2_SHADER_FILE = "frag2 test.glsl";

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
const assert = std.debug.assert;

const state = &engine.state;

fn createWindow(title: [:0]const u8) !*glfw.Window {
    glfw.windowHint(glfw.WindowHint.context_version_major, OPENGL_MAJOR);
    glfw.windowHint(glfw.WindowHint.context_version_minor, OPENGL_MINOR);
    glfw.windowHint(glfw.WindowHint.opengl_profile, glfw.OpenGLProfile.opengl_core_profile);

    const window = try glfw.createWindow(WINDOW_WIDTH, WINDOW_HEIGHT, title, null, null);

    glfw.makeContextCurrent(window);
    glfw.swapInterval(VSYNC_SETTING);

    try opengl.loadCoreProfile(glfw.getProcAddress, OPENGL_MAJOR, OPENGL_MINOR);

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
    fragment: [2][:0]const u8,
};
fn loadShaders(allocator: std.mem.Allocator) !Shaders {
    var shader_dir = try std.fs.cwd().openDir(SHADER_DIR, .{});
    defer shader_dir.close();
    return .{
        .vertex = try shader_dir.readFileAllocOptions(allocator, VERTEX_SHADER_FILE, MAX_SHADER_SIZE, null, .of(u8), 0),
        .fragment = .{
            try shader_dir.readFileAllocOptions(allocator, PASS1_SHADER_FILE, MAX_SHADER_SIZE, null, .of(u8), 0),
            try shader_dir.readFileAllocOptions(allocator, PASS2_SHADER_FILE, MAX_SHADER_SIZE, null, .of(u8), 0),
        }
    };
}

fn setupPipeline(shaders: Shaders, window: *glfw.Window) !void {
    var stderr = state.console.writer(Console.STDERR);

    const vertex = gl.createShader(gl.VERTEX_SHADER);
    const fragment1 = gl.createShader(gl.FRAGMENT_SHADER);
    const fragment2 = gl.createShader(gl.FRAGMENT_SHADER);

    gl.shaderSource(vertex, 1, @ptrCast(&shaders.vertex), null);
    gl.shaderSource(fragment1, 1, @ptrCast(&shaders.fragment[0]), null);
    gl.shaderSource(fragment2, 1, @ptrCast(&shaders.fragment[1]), null);

    var info_log: [INFO_LOG_MAX:0]u8 = undefined;
    var log_len: c_int = undefined;
    var shader_compiled: gl.Int = undefined;

    gl.compileShader(vertex);
    gl.getShaderiv(vertex, gl.COMPILE_STATUS, &shader_compiled);
    if (shader_compiled != gl.TRUE) {
        gl.getShaderInfoLog(vertex, INFO_LOG_MAX, @ptrCast(&log_len), @ptrCast(&info_log));
        try stderr.print("[Vertex shader] {s}", .{info_log[0..@intCast(log_len)]});
        try stderr.flush();
        return;
    }

    gl.compileShader(fragment1);
    gl.getShaderiv(fragment1, gl.COMPILE_STATUS, &shader_compiled);
    if (shader_compiled != gl.TRUE) {
        gl.getShaderInfoLog(fragment1, INFO_LOG_MAX, @ptrCast(&log_len), @ptrCast(&info_log));
        try stderr.print("[Fragment (pass 1) shader] {s}", .{info_log[0..@intCast(log_len)]});
        try stderr.flush();
        return;
    }

    gl.compileShader(fragment2);
    gl.getShaderiv(fragment2, gl.COMPILE_STATUS, &shader_compiled);
    if (shader_compiled != gl.TRUE) {
        gl.getShaderInfoLog(fragment2, INFO_LOG_MAX, @ptrCast(&log_len), @ptrCast(&info_log));
        try stderr.print("[Fragment (pass 2) shader] {s}", .{info_log[0..@intCast(log_len)]});
        try stderr.flush();
        return;
    }

    const program1 = gl.createProgram();
    const program2 = gl.createProgram();

    gl.attachShader(program1, vertex);
    gl.attachShader(program1, fragment1);
    gl.attachShader(program2, vertex);
    gl.attachShader(program2, fragment2);

    gl.linkProgram(program1);
    gl.linkProgram(program2);

    var program_linked: gl.Int = undefined;
    gl.getProgramiv(program1, gl.LINK_STATUS, &program_linked);
    if (program_linked != gl.TRUE) {
        gl.getProgramInfoLog(program1, INFO_LOG_MAX, @ptrCast(&log_len), @ptrCast(&info_log));
        try stderr.print("[Pass 1 program] {s}", .{info_log[0..@intCast(log_len)]});
        try stderr.flush();
        return;
    }

    gl.getProgramiv(program2, gl.LINK_STATUS, &program_linked);
    if (program_linked != gl.TRUE) {
        gl.getProgramInfoLog(program2, INFO_LOG_MAX, @ptrCast(&log_len), @ptrCast(&info_log));
        try stderr.print("[Pass 2 program] {s}", .{info_log[0..@intCast(log_len)]});
        try stderr.flush();
        return;
    }

    var fb_size: [2]c_int = undefined;
    glfw.getFramebufferSize(window, @constCast(&fb_size[0]), @constCast(&fb_size[1]));

    // genero texture
    var depth_tex: gl.Uint = undefined;
    gl.genTextures(1, @ptrCast(&depth_tex));
    // bindo texture
    gl.bindTexture(gl.TEXTURE_2D, depth_tex);
    // configuro 2d image texture
    const fb_size_red: [2]c_int = .{
        @intFromFloat(@as(gl.Float, @floatFromInt(fb_size[0])) * RES_REDUCTION),
        @intFromFloat(@as(gl.Float, @floatFromInt(fb_size[1])) * RES_REDUCTION)
    };
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.R32F, fb_size_red[0], fb_size_red[1], 0, gl.RED, gl.FLOAT, null);
    // assegno parametri texture
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);

    // genero fb
    var fb: gl.Uint = undefined;
    gl.genFramebuffers(1, @ptrCast(&fb));
    // bindo fb
    gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
    // assegno texture a fb
    gl.framebufferTexture(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, depth_tex, 0);

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, depth_tex);

    state.opengl.pipeline = .{
        .vertex = vertex,
        .fragment = .{fragment1, fragment2},
        .program = .{program1, program2},
        .alt_fb = fb,
        .viewport = .{fb_size[0], fb_size[1]},
    };

    // Bind uniforms
    state.opengl.uniforms = .{
        .{
            .resolution = gl.getUniformLocation(program1, "uResolution"),
            .time = gl.getUniformLocation(program1, "uTime"),
            .cam_fov = gl.getUniformLocation(program1, "uFov"),
            .cam_pos = gl.getUniformLocation(program1, "uCamPos"),
            .cam_rot = gl.getUniformLocation(program1, "uCamRot"),
            .crank_angle = gl.getUniformLocation(program1, "uCrankAngle"),
        },
        .{
            .resolution = gl.getUniformLocation(program2, "uResolution"),
            .time = gl.getUniformLocation(program2, "uTime"),
            .cam_fov = gl.getUniformLocation(program2, "uFov"),
            .cam_pos = gl.getUniformLocation(program2, "uCamPos"),
            .cam_rot = gl.getUniformLocation(program2, "uCamRot"),
            .crank_angle = gl.getUniformLocation(program2, "uCrankAngle"),
        },
    };

    // Init uniforms
    const uniforms = &state.opengl.uniforms.?;

    gl.uniform2f(uniforms[0].resolution, @floatFromInt(fb_size_red[0]), @floatFromInt(fb_size_red[1]));
    gl.uniform1f(uniforms[0].cam_fov, state.camera.fov);

    gl.uniform2f(uniforms[1].resolution, @floatFromInt(fb_size[0]), @floatFromInt(fb_size[1]));
    gl.uniform1f(uniforms[1].cam_fov, state.camera.fov);
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
    defer allocator.free(shaders.fragment[0]);
    defer allocator.free(shaders.fragment[1]);

    try setupPipeline(shaders, window);
    const pipeline = &state.opengl.pipeline.?;
    defer gl.deleteShader(pipeline.vertex);
    defer gl.deleteShader(pipeline.fragment[0]);
    defer gl.deleteShader(pipeline.fragment[1]);
    defer gl.deleteProgram(pipeline.program[0]);
    defer gl.deleteProgram(pipeline.program[1]);

    const uniform = &state.opengl.uniforms.?;
    var last_dbg_update: f32 = 0;
    while (!window.shouldClose()) {
        const now = @as(f32, @floatCast(glfw.getTime()));
        state.dt = now - state.now;
        state.now = now;

        glfw.pollEvents();
        getInput(window);

        // bindo fb 1
        gl.bindFramebuffer(gl.FRAMEBUFFER, pipeline.alt_fb);
        // setto viewport
        const viewport_red: [2]c_int = .{
            @intFromFloat(@as(gl.Float, @floatFromInt(pipeline.viewport[0])) * RES_REDUCTION),
            @intFromFloat(@as(gl.Float, @floatFromInt(pipeline.viewport[1])) * RES_REDUCTION),
        };
        gl.viewport(0, 0, viewport_red[0], viewport_red[1]);
        // uso prog 1
        gl.useProgram(pipeline.program[0]);
        // setto time
        gl.uniform1f(uniform[0].time, now);
        // draw call
        gl.drawArrays(gl.TRIANGLES, 0, canvas.len / VERT_SIZE);

        // bind fb 0
        gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
        // setto viewport
        gl.viewport(0, 0, pipeline.viewport[0], pipeline.viewport[1]);
        // uso prog 2
        gl.useProgram(pipeline.program[1]);
        // attivo texture
        // bindo texture
        // setto time
        gl.uniform1f(uniform[1].time, now);
        // draw call
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
    gl.uniform3fv(uniforms[0].cam_pos, 1, &state.camera.position.toArray());
    gl.uniform3fv(uniforms[1].cam_pos, 1, &state.camera.position.toArray());
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

    gl.uniform4f(uniforms[0].cam_rot, rot.*.i, rot.*.j, rot.*.k, rot.*.w);
    gl.uniform4f(uniforms[1].cam_rot, rot.*.i, rot.*.j, rot.*.k, rot.*.w);

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
    gl.uniform1f(uniforms[0].cam_fov, state.camera.fov);
    gl.uniform1f(uniforms[1].cam_fov, state.camera.fov);
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

    state.opengl.pipeline.?.viewport[0] = width;
    state.opengl.pipeline.?.viewport[1] = height;
    // const uniforms = &(state.opengl.uniforms orelse return);
    // gl.uniform2f(uniforms.resolution, @floatFromInt(width), @floatFromInt(height));
    // gl.viewport(0, 0, width, height);
}
