const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zli = b.addModule("zli", .{
        .root_source_file = b.path("src/zli.zig"),
        .optimize = optimize,
        .target = target,
    });

    const generate_parser = b.addExecutable(.{
        .name = "generate_parser",
        .root_source_file = b.path("example/cli.zig"),
        .target = b.host,
    });

    generate_parser.root_module.addImport("zli", zli);
    const gen_step = b.addRunArtifact(generate_parser);
    const parser = gen_step.addOutputFileArg("Parser.zig");

    const exe = b.addExecutable(.{
        .name = "demo",
        .root_source_file = b.path("example/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addAnonymousImport("Zli", .{ .root_source_file = parser });
    exe.root_module.addImport("zli", zli);

    b.installArtifact(exe);
}
