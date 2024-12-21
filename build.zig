const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zli_module = b.addModule("zli", .{
        .root_source_file = b.path("src/zli.zig"),
        .target = b.resolveTargetQuery(.{}),
    });

    const exe_buildtime = b.addExecutable(.{
        .name = "demo_buildtime",
        .root_source_file = b.path("example/buildtime_parser/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    buildParser(b, zli_module, exe_buildtime, "example/buildtime_parser/cli.zig");
    b.installArtifact(exe_buildtime);

    const exe_comptime = b.addExecutable(.{
        .name = "demo_comptime",
        .root_source_file = b.path("example/comptime_parser/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const zli = b.addModule("zli", .{
        .root_source_file = b.path("src/zli.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_comptime.root_module.addImport("zli", zli);
    b.installArtifact(exe_comptime);
}

pub fn buildParser(b: *std.Build, zli_module: *std.Build.Module, program: *std.Build.Step.Compile, parser_file: []const u8) void {
    const generate_parser = b.addExecutable(.{
        .name = "generate_parser",
        .root_source_file = b.path(parser_file),
        .target = b.resolveTargetQuery(.{}),
    });

    const config = b.addOptions();
    config.addOption([]const u8, "program_name", program.name);

    zli_module.addOptions("config", config);
    generate_parser.root_module.addImport("zli", zli_module);
    const gen_step = b.addRunArtifact(generate_parser);

    program.root_module.addAnonymousImport("Zli", .{ .root_source_file = gen_step.addOutputFileArg("Parser.zig") });
}
