const std = @import("std");
const glfw = @import("zglfw");
const opengl = @import("zopengl");
const gl = opengl.bindings;
const consts = @import("constants");
const sim = @import("simulation");

pub const State = struct {
    context: *glfw.Window,
    console: Console = .{},
    opengl: OpenGL = .{},
    camera: Camera = .{},
    time: Time = .{},
    simulation: sim.State = .{},
    performance: Performance = .{},
};

pub const Console = struct {
    stdout: ?std.fs.File.Writer = null,
    stderr: ?std.fs.File.Writer = null,

    const ConsoleError = error {
        ConsoleNotInitialized
    };

    pub const Kind = enum {
        stdout,
        stderr,
    };

    const Self = @This();

    pub fn init(self: *Self, kind: Kind, buf: []u8) void {
        switch (kind) {
            .stdout => self.stdout = std.fs.File.stdout().writer(buf),
            .stderr => self.stderr = std.fs.File.stderr().writer(buf),
        }
    }

    pub fn writer(self: *Self, kind: Kind) !*std.Io.Writer {
        const console = &(switch (kind) {
            .stdout => self.stdout,
            .stderr => self.stderr,
        } orelse return ConsoleError.ConsoleNotInitialized);
        return console.*.interface;
    }
};

const OpenGL = struct {
    buffers: struct {
        vbo: ?gl.Uint = null,
        vao: ?gl.Uint = null,
    },
    shaders: struct {
        vertex: Shader,
        fragments: [2]Shader,
    },
    programs: [2]?c_int = .{ null, null },
    frame_buffer: ?c_int = null,
    texture: ?c_int = null,
    ubo: Ubo,

    const Self = OpenGL;

    const Shader = struct {
        id: ?c_uint = null,
        code: []u8 = undefined, // trasformare in un array di righe per permettere di aggiungere define senza concat

        const Type = enum(comptime_int) {
            vertex = gl.VERTEX_SHADER,
            fragment = gl.FRAGMENT_SHADER,
        };

        fn compile(self: *Shader, error_buf: []u8) !bool  {
            var shader_compiled: gl.Int = undefined;

            const shader = gl.createShader(type);
            self.id = shader ore;
            gl.shaderSource(shader, 1, @ptrCast(self.code), null);
            gl.compileShader(shader);

            gl.getShaderiv(shader, gl.COMPILE_STATUS, &shader_compiled);
            if (shader_compiled != gl.TRUE) {
                gl.getShaderInfoLog(shader, error_buf.len, null, @ptrCast(error_buf));
                return false;
            }

            return true;
        }
    };

    const Ubo = struct {
        resolution: c_int,
        time: c_int,
        cam_fov: c_int,
        cam_pos: c_int,
        cam_rot: c_int,
        crank_angle: c_int,
        depth_tex: c_int,
    };

    pub fn setupCanvas(self: *Self) void {
        gl.genBuffers(1, &self.vbo);
        gl.bindBuffer(gl.ARRAY_BUFFER, self.vbo);
        gl.bufferData(
            gl.ARRAY_BUFFER,
            @sizeOf(@TypeOf(consts.CANVAS_VERTS)),
            &consts.CANVAS_VERTS,
            gl.STATIC_DRAW
        );

        gl.genVertexArrays(1, &self.vao);
        gl.bindVertexArray(self.vao);
        gl.vertexAttribPointer(
            0,
            consts.VERT_SIZE,
            gl.FLOAT,
            gl.FALSE,
            @sizeOf([consts.VERT_SIZE]gl.Float),
            @ptrFromInt(0)
        );
        gl.enableVertexAttribArray(0);
    }

    fn loadFile(dir: std.fs.Dir, file: []u8, allocator: std.mem.Allocator) ![]u8 {
        return try dir.readFileAllocOptions(
            allocator,
            file,
            consts.MAX_SHADER_SIZE,
            null,
            .of(u8),
            0
        );
    }

    fn loadShaders(self: *@TypeOf(OpenGL.shaders), allocator: std.mem.Allocator) !void {
        var shader_dir = try std.fs.cwd().openDir(consts.SHADER_DIR, .{});
        defer shader_dir.close();

        const vertex_code = try loadFile(consts.VERTEX_FILE, allocator);
        const scene_code = try loadFile(consts.SCENE_FILE, allocator);
        var pass1_code = try loadFile(consts.PASS1_FILE, allocator);
        var pass2_code = try loadFile(consts.PASS2_FILE, allocator);

        var buf: [consts.INFO_LOG_MAX]u8 = undefined;

        self.vertex.code = vertex_code;
        self.vertex.compile(&buf);

        pass1_code = try std.mem.concat(allocator, []u8, .{consts.PASS1_DEFINE, scene_code, pass1_code});
        self.fragments[0].code = pass1_code;
        self.fragments[0].compile(&buf);

        pass2_code = try std.mem.concat(allocator, []u8, .{consts.PASS2_DEFINE, scene_code, pass2_code});
        self.shaders.fragments[1].code = pass2_code;
    }


    pub fn setupPipeline(self: *Self, allocator: std.mem.Allocator) !void {
        var stderr = self.console.writer(Console.Kind.stderr);

        try loadShaders(self, allocator);



        const fragment1 = gl.createShader(gl.FRAGMENT_SHADER);
        self.shaders.fragment[0].id = fragment1;
        gl.shaderSource(fragment1, 1, @ptrCast(self.shaders.fragment[0]), null);
        gl.compileShader(fragment1);

        gl.getShaderiv(fragment1, gl.COMPILE_STATUS, &shader_compiled);
        if (shader_compiled != gl.TRUE) {
            gl.getShaderInfoLog(fragment1, consts.INFO_LOG_MAX, @ptrCast(&log_len), @ptrCast(&info_log));
            try stderr.print("[Fragment 1 shader] {s}", .{info_log[0..@intCast(log_len)]});
            try stderr.flush();
            return;
        }

        const fragment2 = gl.createShader(gl.FRAGMENT_SHADER);
        self.shaders.fragment[1].id = fragment2;
        gl.shaderSource(fragment2, 1, @ptrCast(self.shaders.fragment[1]), null);
        gl.compileShader(fragment2);

        gl.getShaderiv(fragment2, gl.COMPILE_STATUS, &shader_compiled);
        if (shader_compiled != gl.TRUE) {
            gl.getShaderInfoLog(fragment2, consts.INFO_LOG_MAX, @ptrCast(&log_len), @ptrCast(&info_log));
            try stderr.print("[Fragment 2 shader] {s}", .{info_log[0..@intCast(log_len)]});
            try stderr.flush();
            return;
        }

        const program1 = gl.createProgram();
        self.programs[0] = program1;
        gl.attachShader(program1, vertex);
        gl.attachShader(program1, fragment1);
        gl.linkProgram(program1);

        gl.getProgramiv(program1, gl.LINK_STATUS, &program_linked);
        if (program_linked != gl.TRUE) {
            gl.getProgramInfoLog(program1, consts.INFO_LOG_MAX, @ptrCast(&log_len), @ptrCast(&info_log));
            try stderr.print("[Pass 1 program] {s}", .{info_log[0..@intCast(log_len)]});
            try stderr.flush();
            return;
        }

        const program2 = gl.createProgram();
        self.programs[1] = program2;
        gl.attachShader(program2, vertex);
        gl.attachShader(program2, fragment2);
        gl.linkProgram(program2);

        gl.getProgramiv(program2, gl.LINK_STATUS, &program_linked);
        if (program_linked != gl.TRUE) {
            gl.getProgramInfoLog(program2, consts.INFO_LOG_MAX, @ptrCast(&log_len), @ptrCast(&info_log));
            try stderr.print("[Pass 2 program] {s}", .{info_log[0..@intCast(log_len)]});
            try stderr.flush();
            return;
        }

        var fb_size: [2]c_int = undefined;
        glfw.getFramebufferSize(window, @constCast(&fb_size[0]), @constCast(&fb_size[1]));

        // genero texture
        var depth_tex: gl.Uint = undefined;
        gl.genTextures(1, @ptrCast(&depth_tex));
        // seleziono tex slot
        gl.activeTexture(gl.TEXTURE0);
        // bindo texture
        gl.bindTexture(gl.TEXTURE_2D, depth_tex);
        // configuro 2d image texture
        const fb_size_red: [2]c_int = .{
            @intFromFloat(@trunc(@as(gl.Float, @floatFromInt(fb_size[0])) / RES_REDUCTION)),
            @intFromFloat(@trunc(@as(gl.Float, @floatFromInt(fb_size[1])) / RES_REDUCTION))
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

        stateObj.opengl.pipeline = .{
            .vertex = vertex,
            .fragment = .{fragment1, fragment2},
            .program = .{program1, program2},
            .alt_fb = fb,
            .fb_size = .{
                .{fb_size_red[0], fb_size_red[1]},
                .{fb_size[0], fb_size[1]},
            }
        };

        // Bind uniforms
        stateObj.opengl.uniforms = .{
            .{
                .resolution = gl.getUniformLocation(program1, "uResolution"),
                .time = gl.getUniformLocation(program1, "uTime"),
                .cam_fov = gl.getUniformLocation(program1, "uFov"),
                .cam_pos = gl.getUniformLocation(program1, "uCamPos"),
                .cam_rot = gl.getUniformLocation(program1, "uCamRot"),
                .crank_angle = gl.getUniformLocation(program1, "uCrankAngle"),
                .depth_tex = 0,
            },
            .{
                .resolution = gl.getUniformLocation(program2, "uResolution"),
                .time = gl.getUniformLocation(program2, "uTime"),
                .cam_fov = gl.getUniformLocation(program2, "uFov"),
                .cam_pos = gl.getUniformLocation(program2, "uCamPos"),
                .cam_rot = gl.getUniformLocation(program2, "uCamRot"),
                .crank_angle = gl.getUniformLocation(program2, "uCrankAngle"),
                .depth_tex = gl.getUniformLocation(program2, "uSampler"),
            },
        };
    }


    pub fn cleanup() void {
        // elimino buffer
        // elimino shader
    }
};

// const Options = struct {

// };

pub const Camera = struct {
    fov: f32 = (consts.FOV_MAX - consts.FOV_MIN) / 2,
    min_fov: f32 = consts.FOV_MIN,
    max_fov: f32 = consts.FOV_MAX,
    position: glm.Vec3 = .{},
    rotation: glm.Quaternion = .{},

    const Self = @This();

    pub const Options = struct {
        fov: ?f32 = null,
        min_fov: ?f32 = null,
        max_fov: ?f32 = null,
        position: ?glm.Vec3 = null,
        rotation: ?glm.Quaternion = null,
    };

    pub fn new(options: Options) Self {
        var cam = Camera{};

        if (options.fov) |fov| cam.fov = fov;
        if (options.min_fov) |min_fov| cam.min_fov = min_fov;
        if (options.max_fov) |max_fov| cam.max_fov = max_fov;
        if (options.position) |position| cam.position = position;
        if (options.rotation) |rotation| cam.rotation = rotation;
    }

    pub fn setFov(self: *Self, fov: f32) void {
        self.fov = std.math.clamp(fov, consts.FOV_MIN, consts.FOV_MAX);
    }
};

const Time = struct {
    now: f32 = 0,
    dt: f32 = 0,
};

const Performance = struct {
    frametime_rbuf: [consts.FRAMETIME_RBUF_DIM]f32 = [_]f32{0} ** consts.FRAMETIME_RBUF_DIM,
    rbuf_idx: u32 = 0,
    frametimes_sum: f32 = 0,

    const Self = @This();

    pub fn addFrametime(self: *Self, dt: f32) void {
        self.frametimes_sum -= self.frametime_rbuf[self.rbuf_idx];
        self.frametimes_sum += dt;
        self.frametime_rbuf[self.rbuf_idx] = dt;
        self.rbuf_idx = (self.rbuf_idx + 1) & (consts.FRAMETIME_RBUF_DIM - 1);
    }

    pub fn getAvgFrameTime(self: Self) f32 {
        return self.frametimes_sum / consts.FRAMETIME_RBUF_DIM;
    }
};
