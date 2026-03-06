const glfw = @import("zglfw");
const opengl = @import("zopengl");

pub fn main() !void {
    try glfw.init();
    defer glfw.terminate();

    const window = try glfw.createWindow(600, 600, "Raymarching demo", null, null);
    defer window.destroy();

    glfw.makeContextCurrent(window);

    try opengl.loadCoreProfile(getProcAddress, 4, 0);

    const gl = opengl.bindings;

    while (!window.shouldClose()) {
        glfw.pollEvents();

        gl.clearBufferfv(gl.COLOR, 0, &[_]gl.Float{ 0.2, 0.4, 0.8, 1.0 });

        window.swapBuffers();
    }
}

fn getProcAddress(name: [*:0]const u8) callconv(.c) ?*const anyopaque {
    return glfw.getProcAddress(name);
}
