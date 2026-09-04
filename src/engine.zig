const std = @import("std");
const glfw = @import("zglfw");
const opengl = @import("zopengl");
const gl = opengl.bindings;
const consts = @import("constants.zig");
const sim = @import("simulation");
const glm = @import("glm.zig");

pub const State = struct {
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

    const Error = error {
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
        return (switch (kind) {
            .stdout => self.stdout,
            .stderr => self.stderr,
        } orelse return Error.ConsoleNotInitialized).interface;
    }
};

const OpenGL = struct {
    context: *glfw.Window,
    buffers: struct {
        vbo: ?gl.Uint = null,
        vao: ?gl.Uint = null,
    },
    shaders: struct {
        vertex: Shader = .{},
        fragments: [2]Shader = .{.{}, .{}},
    },
    programs: [2]Program = .{.{}, .{}},
    frame_buffer: ?c_int = null,
    texture: ?c_int = null,
    ubo: Ubo,

    const Self = OpenGL;

    const Error = error {
        ResourceCreation
    };

    const Shader = struct {
        id: ?c_uint = null,
        code: []u8 = undefined, // trasformare in un array di righe per permettere di aggiungere define senza concat

        const Type = enum(comptime_int) {
            vertex = gl.VERTEX_SHADER,
            fragment = gl.FRAGMENT_SHADER,
        };

        const Error = error {
            CompilationFail,
        };

        fn compile(self: *Shader, shader_type: Shader.Type, error_buf: []u8) !void  {
            const shader = gl.createShader(shader_type);
            if (shader == 0) return OpenGL.Error.ResourceCreation;
            self.id = shader;

            gl.shaderSource(shader, 1, @ptrCast(self.code), null);

            var shader_compiled: gl.Int = undefined;
            gl.compileShader(shader);
            gl.getShaderiv(shader, gl.COMPILE_STATUS, &shader_compiled);
            if (shader_compiled != gl.TRUE) {
                gl.getShaderInfoLog(shader, error_buf.len, null, @ptrCast(error_buf));
                return Shader.Error.CompilationFail;
            }
        }
    };

    const Program = struct {
        id: ?c_uint = null,

        const Error = error {
            LinkFail,
        };

        fn link(self: *Program, vertex: Shader, fragment: Shader, error_buf: []u8) !void {
            const program = gl.createProgram();
            if (program == 0) return OpenGL.Error.ResourceCreation;
            self.id = program;

            gl.attachShader(program, vertex.id);
            gl.attachShader(program, fragment.id);
            gl.linkProgram();

            var program_linked: gl.Int = undefined;
            gl.getProgramiv(program, gl.LINK_STATUS, &program_linked);
            if (program_linked != gl.TRUE) {
                gl.getProgramInfoLog(program, error_buf.len, null, @ptrCast(error_buf));
                return Program.Error.LinkFail;
            }
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

    fn loadShaders(self: *Self, allocator: std.mem.Allocator) !void {
        var shader_dir = try std.fs.cwd().openDir(consts.SHADER_DIR, .{});
        defer shader_dir.close();

        const vertex_code = try loadFile(consts.VERTEX_FILE, allocator);
        self.shaders.vertex.code = vertex_code;

        const scene_code = try loadFile(consts.SCENE_FILE, allocator);
        defer allocator.free(scene_code);
        const pass1_code = try loadFile(consts.PASS1_FILE, allocator);
        defer allocator.free(pass1_code);
        const pass2_code = try loadFile(consts.PASS2_FILE, allocator);
        defer allocator.free(pass2_code);

        const frag1_code = try std.mem.concat(allocator, u8, .{consts.PASS1_DEFINE, scene_code, pass1_code});
        self.shaders.fragments[0].code = frag1_code;
        const frag2_code = try std.mem.concat(allocator, u8, .{consts.PASS2_DEFINE, scene_code, pass2_code});
        self.shaders.fragments[1].code = frag2_code;

        var buf: [consts.INFO_LOG_MAX]u8 = undefined;
        self.shaders.vertex.compile(&buf, Shader.Type.vertex) catch |err| {
            if (err == Shader.Error.CompilationFail) {
                var stderr_buf: [64]u8 = undefined;
                std.fs.File.stderr().writer(&stderr_buf).interface.print("[Vertex] {s}", .{buf});
                return err;
            }
        };
        inline for (self.shaders.fragments, 0..) |_, i| {
            self.shaders.fragments[i].compile(&buf, Shader.Type.fragment) catch |err| {
                if (err == Shader.Error.CompilationFail) {
                    var stderr_buf: [64]u8 = undefined;
                    std.fs.File.stderr().writer(&stderr_buf).interface.print("[Fragment {d}] {s}", .{i, buf});
                    return err;
                }
            };
        }
    }

    fn createPrograms(self: *Self) !void {
        var buf: [consts.INFO_LOG_MAX]u8 = undefined;

        for (self.programs, 0..) |_, i| {
            self.programs[i].link(
                self.shaders.vertex,
                self.shaders.fragments[i],
                &buf
            ) catch |err| {
                if (err == Program.Error.LinkFail) {
                    var stderr_buf: [64]u8 = undefined;
                    std.fs.File.stderr().writer(&stderr_buf).interface.print("[Program {d}] {s}", .{i, buf});
                    return err;
                }
            };
        }
    }

    fn createInterPassFrameBuffer(self: *Self) void {
        var width: c_int = undefined;
        var height: c_int = undefined;
        glfw.getFramebufferSize(self.context, &width, &height);

        var depth_tex: gl.Uint = undefined;
        gl.genTextures(1, &depth_tex);
        self.texture = depth_tex;
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, depth_tex);
        const tex_width = width / consts.RES_REDUCTION;
        const tex_height = height / consts.RES_REDUCTION;
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.R32F, tex_width, tex_height, 0, gl.RED, gl.FLOAT, null);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);

        var fb: gl.Uint = undefined;
        gl.genFramebuffers(1, &fb);
        self.frame_buffer = fb;
        gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
        gl.framebufferTexture(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, depth_tex, 0);
    }

    pub fn setupPipeline(self: *Self, allocator: std.mem.Allocator) !void {
        try self.loadShaders(allocator);
        try self.createPrograms();
        createInterPassFrameBuffer();
    }

    pub fn firstPass(self: *Self) void {
        gl.bindFramebuffer(gl.FRAMEBUFFER, 0);
        gl.useProgram(self.programs[0].id.?);
        var width: c_int = undefined;
        var height: c_int = undefined;
        glfw.getFramebufferSize(self.context, &width, &height);
        gl.viewport(0, 0, width, height);
        gl.drawArrays(gl.TRIANGLES, 0, consts.CANVAS_VERTS.len / consts.VERT_SIZE);
    }

    pub fn secondPass(self: *Self) void {
        gl.bindFramebuffer(gl.FRAMEBUFFER, self.frame_buffer.?);
        gl.useProgram(self.programs[1].id.?);
        var width: c_int = undefined;
        var height: c_int = undefined;
        glfw.getFramebufferSize(self.context, &width, &height);
        gl.viewport(0, 0, width / consts.RES_REDUCTION, height / consts.RES_REDUCTION);
        gl.drawArrays(gl.TRIANGLES, 0, consts.CANVAS_VERTS.len / consts.VERT_SIZE);
    }

    pub fn updateUniforms(seld: *Self) {

    }

    pub fn cleanup(self: *Self, allocator: std.mem.Allocator) void {
        // elimino buffer
        gl.deleteBuffers(1, &self.buffers.vbo.?);
        gl.deleteVertexArrays(1, &self.buffers.vao.?);
        // shader
        gl.deleteShader(self.shaders.vertex.id.?);
        gl.deleteShader(self.shaders.fragments[0].id.?);
        gl.deleteShader(self.shaders.fragments[1].id.?);
        // programmi
        gl.deleteProgram(self.programs[0].id.?);
        gl.deleteProgram(self.programs[1].id.?);
        // framebuffer
        gl.deleteFramebuffers(1, self.frame_buffer.?);
        // texture
        gl.deleteTextures(1, self.texture.?);

        // anche codice shader in mem CPU
        allocator.free(self.shaders.vertex.code));
        allocator.free(self.shaders.fragments[0].code));
        allocator.free(self.shaders.fragments[1].code));
    }
};

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
