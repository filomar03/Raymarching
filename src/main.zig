const std = @import("std");
const glfw = @import("zglfw");
const opengl = @import("zopengl");
const engine = @import("engine/engine.zig");
const glm = @import("engine/glm.zig");
const zm = @import("zmath");

const Console = engine.ConsoleInterface.Kind;
const Vec3 = glm.Vec(3);
const Vec2 = glm.Vec(2);

const OPENGL_MAJOR = 3;
const OPENGL_MINOR = 3;

const WINDOW_WIDTH = 600;
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
    var stderr = state.console.writer(Console.STDOUT);

    // GLFW & Context init
    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(glfw.WindowHint.context_version_major, OPENGL_MAJOR);
    glfw.windowHint(glfw.WindowHint.context_version_minor, OPENGL_MINOR);
    glfw.windowHint(glfw.WindowHint.opengl_profile, glfw.OpenGLProfile.opengl_core_profile);

    const window = try glfw.createWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Raymarching demo", null, null);
    defer window.destroy();

    glfw.makeContextCurrent(window);

    _ = glfw.setFramebufferSizeCallback(window, &fbResizeCallback);
    _ = glfw.setScrollCallback(window, &adjustFov);

    try opengl.loadCoreProfile(glfw.getProcAddress, OPENGL_MAJOR, OPENGL_MINOR);

    var fb_width: c_int = undefined;
    var fb_height: c_int = undefined;
    glfw.getFramebufferSize(window, &fb_width, &fb_height);
    gl.viewport(0, 0, fb_width, fb_height);

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
        try stderr.print("[Vertex shader compilation] {s}", .{info_log[0..@intCast(log_len)]});
        try stderr.flush();
        return;
    }

    gl.compileShader(frag_shad);
    gl.getShaderiv(frag_shad, gl.COMPILE_STATUS, &shader_compiled);
    if (shader_compiled != gl.TRUE) {
        gl.getShaderInfoLog(frag_shad, INFO_LOG_MAX, @ptrCast(&log_len), @ptrCast(&info_log));
        try stderr.print("[Fragment shader compilation] {s}", .{info_log[0..@intCast(log_len)]});
        try stderr.flush();
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
        try stderr.print("[Program linking] {s}", .{info_log[0..@intCast(log_len)]});
        try stderr.flush();
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
        }
    };

    state.shader = shader_interface;

    gl.uniform2f(shader_interface.uniforms.resolution, @floatFromInt(fb_width), @floatFromInt(fb_height));
    gl.uniform1f(shader_interface.uniforms.cam_fov, state.camera.fov);
    gl.uniform1f(shader_interface.uniforms.cam_near, state.camera.near);
    gl.uniform3fv(shader_interface.uniforms.cam_pos, 1, &state.camera.position.toArray());

    // Render loop
    while (!window.shouldClose()) {
        glfw.pollEvents();

        getInput(window);

        // gl.clearColor(0.0, 0.0, 0.0, 1.0);
        // gl.clear(gl.COLOR_BUFFER_BIT);

        gl.uniform1f(shader_interface.uniforms.time, @floatCast(glfw.getTime()));

        // gl.useProgram(program); // Should i call these?
        // gl.bindVertexArray(vao);
        gl.drawArrays(gl.TRIANGLES, 0, vertices.len / VERT_VEC_SIZE);

        window.swapBuffers();
    }
}

const CAM_SPEED = Vec3{.x = 0.1, .y = 0.05, .z = 0.1};

fn getInput(window: *glfw.Window) void {
    const stderr = state.console.writer(Console.STDOUT);

    const forward: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.w) == glfw.Action.press));
    const backwards: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.s) == glfw.Action.press));
    const right: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.d) == glfw.Action.press));
    const left: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.a) == glfw.Action.press));
    const up: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.q) == glfw.Action.press));
    const down: f32 = @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.e) == glfw.Action.press));
    var input: Vec3 = .{.x = right + -left, .y = up + -down, .z = forward + -backwards};
    input = input.normalize();

    // TODO: direzioni tutte da invertire
    // e traslare con dt

    const dt: f32 = 1;
    state.camera.position = state.camera.position.sum(input.mul(CAM_SPEED).mul(dt));
    const shader = state.shader orelse return;
    gl.uniform3fv(shader.uniforms.cam_pos, 1, &state.camera.position.toArray());

    // DEBUG!!!
    if (input.length() != 0) {
        stderr.print("POS: {:5.1}, {:5.1}, {:5.1}\n", .{state.camera.position.x, state.camera.position.y, state.camera.position.z}) catch unreachable;
        stderr.flush() catch unreachable;
    }
}

const FOV_SENS = 1;
const MIN_FOV = 30;
const MAX_FOV = 120;

fn adjustFov(window: *glfw.Window, x_offset: f64 , y_offset: f64) callconv(.c) void {
    _ = window;
    _ = x_offset;

    const shader = state.shader orelse return;
    const new_fov = state.camera.fov + @as(f32, @floatCast(-y_offset)) * FOV_SENS;
    state.camera.fov = std.math.clamp(new_fov, MIN_FOV, MAX_FOV);
    gl.uniform1f(shader.uniforms.cam_fov, state.camera.fov);

    // DEBUG!!!
    const stderr = state.console.writer(Console.STDOUT);
    stderr.print("FOV: {}\n", .{state.camera.fov}) catch unreachable;
    stderr.flush() catch unreachable;
}

fn fbResizeCallback(window: *glfw.Window, width: c_int, height: c_int) callconv(.c) void {
    _ = window;

    const shader = state.shader orelse return;
    gl.uniform2f(shader.uniforms.resolution, @floatFromInt(width), @floatFromInt(height));
    gl.viewport(0, 0, width, height);
}
