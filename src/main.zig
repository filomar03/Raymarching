const std = @import("std");
const glfw = @import("zglfw");
const opengl = @import("zopengl");

const OPENGL_MAJOR = 3;
const OPENGL_MINOR = 3;

const WINDOW_WIDTH = 600;
const WINDOW_HEIGHT = 600;

const SRC_DIR = "src";
const SHADER_DIR = "shaders";
const VERTEX_SHADER_FILE = "vertex.glsl";
const FRAGMENT_SHADER_FILE = "fragment.glsl";
const MAX_SHADER_SIZE = 1024 * 1024; // 1 Mib

const INFO_LOG_MAX = 512;

pub fn main() !void {
    // Allocator & Stdout
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var buf: [64]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buf);
    var stdout = &stdout_writer.interface;
    var stderr_writer = std.fs.File.stderr().writer(&buf);
    var stderr = &stderr_writer.interface;
    _ = &stdout; // autofix

    // GLFW init
    try glfw.init();
    defer glfw.terminate();

    // Window & Context creation
    glfw.windowHint(glfw.WindowHint.context_version_major, OPENGL_MAJOR);
    glfw.windowHint(glfw.WindowHint.context_version_minor, OPENGL_MINOR);
    glfw.windowHint(glfw.WindowHint.opengl_profile, glfw.OpenGLProfile.opengl_core_profile);

    const window = try glfw.createWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Raymarching demo", null, null);
    defer window.destroy();

    glfw.makeContextCurrent(window);

    // Callbacks setup
    // glfw.setFramebufferSizeCallback(window, &resizeCallback);

    // Loading OpenGL
    try opengl.loadCoreProfile(glfw.getProcAddress, OPENGL_MAJOR, OPENGL_MINOR);
    const gl = opengl.bindings;

    var fb_width: c_int = undefined;
    var fb_height: c_int = undefined;
    glfw.getFramebufferSize(window, &fb_width, &fb_height);
    try stderr.print("{} {}", .{fb_width, fb_height});
    try stderr.flush();
    gl.viewport(0, 0, fb_width, fb_height);

    // Load shaders from file
    const shader_path = try std.fs.path.join(allocator, &[_][]const u8{SRC_DIR, SHADER_DIR});
    defer allocator.free(shader_path);

    var shader_dir = try std.fs.cwd().openDir(shader_path, .{});
    defer shader_dir.close();

    const vert_src = try shader_dir.readFileAllocOptions(allocator, VERTEX_SHADER_FILE, MAX_SHADER_SIZE, null, .of(u8), 0);
    defer allocator.free(vert_src);

    const frag_src = try shader_dir.readFileAllocOptions(allocator, FRAGMENT_SHADER_FILE, MAX_SHADER_SIZE, null, .of(u8), 0);
    defer allocator.free(frag_src);

    // Setup quad
    const vertices = [_]gl.Float{
         1.0,  1.0,  0.0,
        -1.0,  1.0,  0.0,
        -1.0, -1.0,  0.0
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

    gl.vertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, @sizeOf([3]gl.Float), @ptrFromInt(0));
    gl.enableVertexAttribArray(0);

    // Setup shaders
    const vert_shad = gl.createShader(gl.VERTEX_SHADER);
    defer gl.deleteShader(vert_shad);
    const frag_shad = gl.createShader(gl.FRAGMENT_SHADER);
    defer gl.deleteShader(frag_shad);

    gl.shaderSource(vert_shad, 1, @ptrCast(&vert_src), null);
    gl.shaderSource(frag_shad, 1, @ptrCast(&frag_src), null);

    // Compile shaders
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

    // Render loop
    while (!window.shouldClose()) {
        glfw.pollEvents();

        gl.clearColor(0.0, 0.0, 0.0, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT);

        // gl.useProgram(program);
        // gl.bindVertexArray(vao);
        gl.drawArrays(gl.TRIANGLES, 0, vertices.len / 3);

        window.swapBuffers();
    }
}

// fn resizeCallback(window: *glfw.Window, width: c_int, height: c_int) callconv(.c) void {

// }
