const std = @import("std");
const glfw = @import("zglfw");
const opengl = @import("zopengl");
const engine = @import("engine/engine.zig");

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

// Camera config
const FOV = 70.0;
const NEAR = 1.0;
const CAM_SPEED = 1.0;

const FOV_SENS = 1;
const MIN_FOV = 30.0;
const MAX_FOV = 120.0;

const gl = opengl.bindings;

var state: engine.State = .{};

pub fn main() !void {
    var x: glm.Vec3 = .{};
    _ = x.length();

    // Allocator & Console
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var buf: [64]u8 = undefined;
    state.console = .init(&buf);
    var stderr = state.console.writer(engine.ConsoleInterface.Kind.STDERR);

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
            .mouse = gl.getUniformLocation(program, "uMouse"),
            .fov = gl.getUniformLocation(program, "uFov"),
        }
    };

    state.shader = shader_interface;

    gl.uniform2f(shader_interface.uniforms.resolution, @floatFromInt(fb_width), @floatFromInt(fb_height));
    gl.uniform1f(shader_interface.uniforms.fov, FOV);

    // Render loop
    while (!window.shouldClose()) {
        glfw.pollEvents();

        getInput(window);

        gl.clearColor(0.0, 0.0, 0.0, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT);

        gl.uniform1f(shader_interface.uniforms.time, @floatCast(glfw.getTime()));

        // gl.useProgram(program); // Should i call these?
        // gl.bindVertexArray(vao);
        gl.drawArrays(gl.TRIANGLES, 0, vertices.len / VERT_VEC_SIZE);

        window.swapBuffers();
    }
}

fn getInput(window: *glfw.Window) void {
    // var cam = state.camera;
    var z_input: f32 = 0;
    var x_input: f32 = 0;
    z_input += @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.w) == glfw.Action.press));
    z_input += @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.s) == glfw.Action.press));
    x_input += @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.d) == glfw.Action.press));
    z_input += @floatFromInt(@intFromBool(glfw.getKey(window, glfw.Key.a) == glfw.Action.press));

    // TODO: modifica posizione camera
    //       e aggiornare uniform
}

fn fbResizeCallback(window: *glfw.Window, width: c_int, height: c_int) callconv(.c) void {
    _ = window;
    const pipeline = &(state.shader orelse return);
    gl.uniform2f(pipeline.uniforms.resolution, @floatFromInt(width), @floatFromInt(height));
    gl.viewport(0, 0, width, height);
}

fn adjustFov(window: *glfw.Window, x_offset: f64 , y_offset: f64) callconv(.c) void {
    _ = window;
    _ = x_offset;

    // TODO: utilizzare CameraObject

    var fov: f32 = undefined;
    const pipeline = &(state.shader orelse return);
    gl.getUniformfv(pipeline.program.*, pipeline.uniforms.fov, &fov);
    fov = std.math.clamp(fov + @as(f32, @floatCast(FOV_SENS * -y_offset)), MIN_FOV, MAX_FOV);
    gl.uniform1f(pipeline.uniforms.fov, fov);

    // DEBUG!!!
    const stderr = state.console.writer(engine.ConsoleInterface.Kind.STDERR);
    stderr.print("FOV: {}\n", .{fov}) catch unreachable;
    stderr.flush() catch unreachable;
}
