const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "Raymarching demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // zglfw dependency
    const zglfw_dep = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
        .shared = b.option(
            bool,
            "glfw-shared",
            "Build GLFW as shared lib",
        ) orelse false,
        .x11 = b.option(
            bool,
            "glfw-x11",
            "Whether to build with X11 support (default: false)",
        ) orelse false,
        .wayland = b.option(
            bool,
            "glfw-wayland",
            "Whether to build with Wayland support (default: true)",
        ) orelse true,
        .import_vulkan = b.option(
            bool,
            "glfw-import_vulkan",
            "Whether to build with external Vulkan dependency (default: false)",
        ) orelse false,
    });
    exe.root_module.addImport("zglfw", zglfw_dep.module("root"));

    if (target.result.os.tag != .emscripten) {
        exe.linkLibrary(zglfw_dep.artifact("glfw"));
    }

    // zopengl dependency
    const zopengl = b.dependency("zopengl", .{});
    exe.root_module.addImport("zopengl", zopengl.module("root"));

    // zmath dependency
    const zmath = b.dependency("zmath", .{});
    exe.root_module.addImport("zmath", zmath.module("root"));

    b.installArtifact(exe);

    // TODO: compilare ed eseguire test
    // const run_test = b.addTe

    // const test_step = b.step("test", "Execute tests");
    // test_step.dependOn();

    const run_exe = b.addRunArtifact(exe);

    const run_step = b.step("run", "Run the executable");
    run_step.dependOn(&run_exe.step);
}
