const std = @import("std");
const glfw = @import("zglfw");
const opengl = @import("zopengl");

const OPENGL_MAJOR = 3;
const OPENGL_MINOR = 3;

const WINDOW_WIDTH = 1280;
const WINDOW_HEIGHT = 720;

pub fn main() !void {
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

    var r: gl.Float = 0;
    var g: gl.Float = 0;
    var b: gl.Float = 0;

    // Render loop
    while (!window.shouldClose()) {
        glfw.pollEvents();

        r += 0.001;
        g += 0.002;
        b += 0.003;

        gl.clearBufferfv(gl.COLOR, 0, &[_]gl.Float{ @rem(r, 1), @rem(g, 1), @rem(b, 1), 1.0 });

        gl.flush();

        window.swapBuffers();
    }
}

fn resizeCallback(window: *glfw.Window, width: c_int, height: c_int) callconv(.c) void {
    _ = window;
    _ = width;
    _ = height;
    @panic("Framebuffer resize callbakc not implemente");
}
