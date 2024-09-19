const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "demo",
        .root_source_file = b.path("example/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addAnonymousImport("Zli", .{ .root_source_file = buildParser(b, "example/cli.zig") });

    b.installArtifact(exe);
}

pub fn buildParser(b: *std.Build, parser_file: []const u8) std.Build.LazyPath {
    const zli = b.addModule("zli", .{
        .root_source_file = b.path("src/zli.zig"),
        .target = b.host,
    });

    const generate_parser = b.addExecutable(.{
        .name = "generate_parser",
        .root_source_file = b.path(parser_file),
        .target = b.host,
    });

    generate_parser.root_module.addImport("zli", zli);
    const gen_step = b.addRunArtifact(generate_parser);
    return gen_step.addOutputFileArg("Parser.zig");
}
