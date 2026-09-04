const glfw = @import("zglfw");
const gl = @import("zopengl").bindings;

// WINDOW
pub const WINDOW_TITLE = "Raymarching demo";
pub const WINDOW_WIDTH = 800;
pub const WINDOW_HEIGHT = 800;
pub const WINDOW_RESIZABLE = true;
pub const WINDOW_SWAP_INT = 1;
pub const WINDOW_CURSOR_MODE = glfw.Cursor.Mode.normal;

// OPENGL
pub const OPENGL_MAJOR = 3;
pub const OPENGL_MINOR = 3;

pub const VERT_SIZE = 3;
pub const CANVAS_VERTS = [_]gl.Float{
    -1.0, -1.0, -1.0,
    -1.0,  1.0, -1.0,
     1.0,  1.0, -1.0,

    -1.0, -1.0, -1.0,
     1.0,  1.0, -1.0,
     1.0, -1.0, -1.0,
};

pub const RES_REDUCTION = 3;


// CAMERA
pub const CAM_DEF_FOV = 60;
pub const FOV_MIN = 30;
pub const FOV_MAX = 120;

// PROFILING
pub const FRAMETIME_RBUF_DIM = 2048; // power of 2 to enable modulo optimization (& insted of %)

// DEBUG
pub const DBG_UPDATE_INTERVAL: f32 = 0.5;

// SHADERS
pub const MAX_SHADER_SIZE = 1024 * 1024; // 1 Mib
pub const INFO_LOG_MAX = 512;

pub const SHADER_DIR = "";
pub const VERTEX_FILE = "";
pub const SCENE_FILE = "";
pub const PASS1_FILE = "";
pub const PASS2_FILE = "";

pub const MAX_DEFINES = 5;
pub const PASS1_DEFINE = "#define FIRST_PASS";
pub const PASS2_DEFINE = "#define SECOND_PASS";
