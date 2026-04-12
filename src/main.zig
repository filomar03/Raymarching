const std = @import("std");
const glfw = @import("zglfw");
const opengl = @import("zopengl");
const engine = @import("engine/engine.zig");
const glm = @import("engine/glm.zig");
const zm = @import("zmath");

const Console = engine.ConsoleInterface.Kind;

const OPENGL_MAJOR = 3;
const OPENGL_MINOR = 3;

const WINDOW_WIDTH = 1200;
const WINDOW_HEIGHT = 800;

const SRC_DIR = "src";
const SHADER_DIR = "shaders";
const VERTEX_SHADER_FILE = "vertex.glsl";
const FRAGMENT_SHADER_FILE = "fragment.glsl";
const MAX_SHADER_SIZE = 1024 * 1024; // 1 Mib

const INFO_LOG_MAX = 512;

const gl = opengl.bindings;

var state: engine.State = .{};

pub fn main() !void {
    // Allocator & Console
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var buf: [64]u8 = undefined;
    state.console.init(Console.STDOUT, &buf);
    var console = state.console.writer(Console.STDOUT);

    // GLFW & Context init
    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(glfw.WindowHint.context_version_major, OPENGL_MAJOR);
    glfw.windowHint(glfw.WindowHint.context_version_minor, OPENGL_MINOR);
    glfw.windowHint(glfw.WindowHint.opengl_profile, glfw.OpenGLProfile.opengl_core_profile);

    const window = try glfw.createWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Raymarching demo", null, null);
    defer window.destroy();

    glfw.makeContextCurrent(window);

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

    // Setup pipeline
    const VERT_VEC_SIZE = 3;
    const vertices = [_]gl.Float{
        -1.0, -1.0, -1.0,
        -1.0,  1.0, -1.0,
         1.0,  1.0, -1.0,

        -1.0, -1.0, -1.0,
         1.0,  1.0, -1.0,
         1.0, -1.0, -1.0,
    };

    var vbo: gl.Uint = undefined;
    var vao: gl.Uint = undefined;

    gl.genBuffers(1, @ptrCast(&vbo));
    gl.genVertexArrays(1, @ptrCast(&vao));

    defer gl.deleteBuffers(1, @ptrCast(&vbo));
    defer gl.deleteVertexArrays(1, @ptrCast(&vao));

    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.bindVertexArray(vao);

    gl.bufferData(gl.ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, gl.STATIC_DRAW);

    gl.vertexAttribPointer(0, VERT_VEC_SIZE, gl.FLOAT, gl.FALSE, @sizeOf([VERT_VEC_SIZE]gl.Float), @ptrFromInt(0));
    gl.enableVertexAttribArray(0);

    // Setup shaders
    const shader_path = try std.fs.path.join(allocator, &[_][]const u8{SRC_DIR, SHADER_DIR});
    defer allocator.free(shader_path);

    var shader_dir = try std.fs.cwd().openDir(shader_path, .{});
    defer shader_dir.close();

    const vert_src = try shader_dir.readFileAllocOptions(
        allocator,
        VERTEX_SHADER_FILE,
        MAX_SHADER_SIZE,
        null,
        .of(u8),
        0
    );
    defer allocator.free(vert_src);

    const frag_src = try shader_dir.readFileAllocOptions(
        allocator,
        FRAGMENT_SHADER_FILE,
        MAX_SHADER_SIZE,
        null,
        .of(u8),
        0
    );
    defer allocator.free(frag_src);

    const vert_shad = gl.createShader(gl.VERTEX_SHADER);
    defer gl.deleteShader(vert_shad);
    const frag_shad = gl.createShader(gl.FRAGMENT_SHADER);
    defer gl.deleteShader(frag_shad);

    gl.shaderSource(vert_shad, 1, @ptrCast(&vert_src), null);
    gl.shaderSource(frag_shad, 1, @ptrCast(&frag_src), null);

    var info_log: [INFO_LOG_MAX:0]u8 = undefined;
    var log_len: c_int = undefined;
    var shader_compiled: gl.Int = undefined;

    gl.compileShader(vert_shad);
    gl.getShaderiv(vert_shad, gl.COMPILE_STATUS, &shader_compiled);
    if (shader_compiled != gl.TRUE) {
        gl.getShaderInfoLog(vert_shad, INFO_LOG_MAX, @ptrCast(&log_len), @ptrCast(&info_log));
        try console.print("[Vertex shader compilation] {s}", .{info_log[0..@intCast(log_len)]});
        try console.flush();
        return;
    }

    gl.compileShader(frag_shad);
    gl.getShaderiv(frag_shad, gl.COMPILE_STATUS, &shader_compiled);
    if (shader_compiled != gl.TRUE) {
        gl.getShaderInfoLog(frag_shad, INFO_LOG_MAX, @ptrCast(&log_len), @ptrCast(&info_log));
        try console.print("[Fragment shader compilation] {s}", .{info_log[0..@intCast(log_len)]});
        try console.flush();
        return;
    }

    const program = gl.createProgram();
    defer gl.deleteProgram(program);

    gl.attachShader(program, vert_shad);
    gl.attachShader(program, frag_shad);

    gl.linkProgram(program);

    var program_linked: gl.Int = undefined;
    gl.getProgramiv(program, gl.LINK_STATUS, &program_linked);
    if (program_linked != gl.TRUE) {
        gl.getProgramInfoLog(program, INFO_LOG_MAX, @ptrCast(&log_len), @ptrCast(&info_log));
        try console.print("[Program linking] {s}", .{info_log[0..@intCast(log_len)]});
        try console.flush();
        return;
    }

    gl.useProgram(program);

    const shader_interface: engine.ShaderInterface = .{
        .program = &program,
        .uniforms = .{
            .resolution = gl.getUniformLocation(program, "uResolution"),
            .time = gl.getUniformLocation(program, "uTime"),
            .cam_fov = gl.getUniformLocation(program, "uFov"),
            .cam_near = gl.getUniformLocation(program, "uNear"),
            .cam_pos = gl.getUniformLocation(program, "uCamPos"),
            .cam_rot = gl.getUniformLocation(program, "uCamRot"),
        }
    };

    state.shader = shader_interface;

    gl.uniform2f(shader_interface.uniforms.resolution, @floatFromInt(fb_width), @floatFromInt(fb_height));
    gl.uniform1f(shader_interface.uniforms.cam_fov, state.camera.fov);
    gl.uniform1f(shader_interface.uniforms.cam_near, state.camera.near);
    gl.uniform3fv(shader_interface.uniforms.cam_pos, 1, &state.camera.position.toArray());

    var last_time: f32 = @floatCast(glfw.getTime());

    // Render loop
    while (!window.shouldClose()) {
        glfw.pollEvents();

        getInput(window);

        // gl.clearColor(0.0, 0.0, 0.0, 1.0); // TODO: should i call these?
        // gl.clear(gl.COLOR_BUFFER_BIT); // TODO: should i call these?

        gl.uniform1f(shader_interface.uniforms.time, @floatCast(glfw.getTime()));

        // gl.useProgram(program); // TODO: should i call these?
        // gl.bindVertexArray(vao); // TODO: should i call these?
        gl.drawArrays(gl.TRIANGLES, 0, vertices.len / VERT_VEC_SIZE);

        window.swapBuffers();

        try console.print("FRAMETIME: {}\n", .{state.dt});
        try console.flush();

        state.dt = @as(f32, @floatCast(glfw.getTime())) - last_time;
        last_time = @floatCast(glfw.getTime());
    }
}

const CAM_SPEED = glm.Vec3{.x = 7.5, .y = 3, .z = 7.5};

const NEAR_SENS = 7;
const NEAR_MIN = 0.1;
const NEAR_MAX = 100;

const FOV_SENS = 1;
const FOV_MIN = 30;
const FOV_MAX = 120;

const CAM_VERT_SENS = 1;
const CAM_HORZ_SENS = 1;

fn moveCamera(window: *glfw.Window) void {
    const forward: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.w) == glfw.Action.press));
    const backwards: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.s) == glfw.Action.press));
    const right: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.d) == glfw.Action.press));
    const left: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.a) == glfw.Action.press));
    const up: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.q) == glfw.Action.press));
    const down: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.e) == glfw.Action.press));
    var input: glm.Vec3 = .{.x = right + -left, .y = up + -down, .z = forward + -backwards};
    input = input.normalize();

    var pos = &state.camera.position;
    pos.* = pos.sum(input.mul(CAM_SPEED).mul(state.dt));
    const shader = state.shader orelse return;
    gl.uniform3fv(shader.uniforms.cam_pos, 1, &state.camera.position.toArray());

    // DEBUG!!!
    if (input.lenght() != 0) {
        const console = state.console.writer(Console.STDOUT);
        console.print("POS: {:0>5.1}, {:0<5.1}, {:0<5.1}\n", .{pos.x, pos.y, pos.z}) catch unreachable;
        console.flush() catch unreachable;
    }
}

const Y_AXIS: glm.Vec3 = .{
    .x = 0,
    .y = 1,
    .z = 0,
};

const X_AXIS: glm.Vec3 = .{
    .x = 1,
    .y = 0,
    .z = 0,
};

fn rotateCamera(window: *glfw.Window) void {
    var mx: f64 = undefined;
    var my: f64 = undefined;
    glfw.getCursorPos(window, &mx, &my);

    const rot = &state.camera.rotation;
    const shader = state.shader orelse return;

    const angle = @as(f32, @floatCast(mx)) * CAM_HORZ_SENS * state.dt;
    const new_rot = glm.Quaternion.fromAxis(Y_AXIS, angle).normalize();
    const q = rot.composeRotation(new_rot).normalize();
    rot.* = q;

    gl.uniform4f(shader.uniforms.cam_rot, q.i, q.j, q.k, q.w);

    // DEBUG!!!
    const console = state.console.writer(Console.STDOUT);
    console.print("QUAT: {:.3}, {:.3}, {:.3}, {:.3} {}\n", .{q.w, q.i, q.j, q.k, q.lenght()}) catch unreachable;
    console.flush() catch unreachable;
}

fn adjustCamNear(window: *glfw.Window) void {
    const up_arrow: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.up) == glfw.Action.press));
    const down_arrow: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.down) == glfw.Action.press));

    const shader = state.shader orelse return;
    state.camera.near = std.math.clamp(state.camera.near + (up_arrow - down_arrow) * NEAR_SENS * state.dt, NEAR_MIN, NEAR_MAX);
    gl.uniform1f(shader.uniforms.cam_near, state.camera.near);

    // DEBUG!!!
    if (up_arrow - down_arrow != 0) {
        const console = state.console.writer(Console.STDOUT);
        console.print("NEAR: {}\n", .{state.camera.near}) catch unreachable;
        console.flush() catch unreachable;
    }
}

fn detectQuit(window: *glfw.Window) void {
    glfw.setWindowShouldClose(window, glfw.getKey(window, glfw.Key.escape) == glfw.Action.press);
}

fn getInput(window: *glfw.Window) void {
    moveCamera(window);
    rotateCamera(window);
    adjustCamNear(window);
    detectQuit(window);
}

fn adjustCamFov(scroll: f32) void {
    const shader = state.shader orelse return;
    state.camera.fov = std.math.clamp(state.camera.fov + -scroll * FOV_SENS, FOV_MIN, FOV_MAX);
    gl.uniform1f(shader.uniforms.cam_fov, state.camera.fov);

    // DEBUG!!!
    const console = state.console.writer(Console.STDOUT);
    console.print("FOV: {}\n", .{state.camera.fov}) catch unreachable;
    console.flush() catch unreachable;
}

fn scrollCallback(window: *glfw.Window, x_offset: f64 , y_offset: f64) callconv(.c) void {
    _ = window;
    _ = x_offset;

    adjustCamFov(@floatCast(y_offset));
}

fn fbResizeCallback(window: *glfw.Window, width: c_int, height: c_int) callconv(.c) void {
    _ = window;

    const shader = state.shader orelse return;
    gl.uniform2f(shader.uniforms.resolution, @floatFromInt(width), @floatFromInt(height));
    gl.viewport(0, 0, width, height);
}
