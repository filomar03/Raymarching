const glfw = @import("zglfw");
const opengl = @import("zopengl");
const consts = @import("constants.zig");

const Options = struct {
     width: ?c_int = null,
     height: ?c_int = null,
     resizable: ?bool = null,
     swap_int: ?c_int = null,
     title: ?[:0]const u8 = null,
     scroll_cllbck: ?*const fn (*glfw.Window, f64, f64) callconv(.c) void = null,
     resize_cllbck: ?*const fn (*glfw.Window, c_int, c_int) callconv(.c) void = null,
     cursor_mode: ?glfw.Cursor.Mode = null,
 };

 pub fn create(opts: Options) !*glfw.Window {
     glfw.windowHint(glfw.WindowHint.context_version_major, consts.OPENGL_MAJOR);
     glfw.windowHint(glfw.WindowHint.context_version_minor, consts.OPENGL_MINOR);
     glfw.windowHint(glfw.WindowHint.opengl_profile, glfw.OpenGLProfile.opengl_core_profile);

     glfw.windowHint(glfw.WindowHint.resizable, opts.resizable orelse consts.WINDOW_RESIZABLE);

     const window = try glfw.createWindow(
         opts.width orelse consts.WINDOW_WIDTH,
         opts.height orelse consts.WINDOW_HEIGHT,
         opts.title orelse consts.WINDOW_TITLE,
         null,
         null
     );

     glfw.makeContextCurrent(window);
     glfw.swapInterval(opts.swap_int orelse consts.WINDOW_SWAP_INT);

     try opengl.loadCoreProfile(
         glfw.getProcAddress,
         consts.OPENGL_MAJOR,
         consts.OPENGL_MAJOR
     );

     _ = glfw.setScrollCallback(window, opts.scroll_cllbck);
     _ = glfw.setFramebufferSizeCallback(window, opts.resize_cllbck);

     try glfw.setInputMode(window, glfw.InputMode.cursor, opts.cursor_mode orelse consts.WINDOW_CURSOR_MODE);
     if (glfw.rawMouseMotionSupported()) {
         try glfw.setInputMode(window, glfw.InputMode.raw_mouse_motion, true);
     }

     return window;
 }
