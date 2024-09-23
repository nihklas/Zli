# Zli

A very small and simple library for easy command line parsing in Zig.

This is written specifically for my personal needs and learning purposes.

For usage examples look at example/main.zig.

It is written with a current build of zig master. As it is still very much evolving, if something breaks because of a zig change,
feel free to open an issue, or even a pull request. But this is still a hobby/side project mostly for me personally, i cannot and
will not make any promises on when or if i get to the issue.

# Features

### Whats Special?

- Definition of Options and Arguments with an anonymous struct
- Compile Time Type analysis
- Access of Options and Arguments via struct-fields
- Automatic Help Text printing

### What CLI Interface does this handle?

- Positional Arguments
- Additional Arguments accessible for manual handling
- Named Options, both in long and short
    - Flags: `--flag, -f` for bool values
    - Options: `--value val, --value=val, -v val` for everything else
- Combined short flags (`-abc`)
- Subcommands (`command sub1 sub2 argument --option`), This is only available in the build-time parser

# Usage

First, add Zli to your project by running

```cmd
zig fetch git+https://gitlab.com/nihklas/zli.git --save
```

To update the version, just run the `zig fetch`-command again

## Compile Time Parser Usage

To use the simpler, but more limited API, add this to your build.zig

```zig
const zli = b.dependency("zli", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zli", zli.module("zli"));
```

## Build Time Parser Usage

To create a `Parser.zig` File at Build-time, add the following lines to your build definition:

```zig
const std = @import("std");
const zli = @import("zli");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zli_dep = b.dependency("zli", .{});

    const exe = b.addExecutable(.{
        .name = "zli_test",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This adds a new Step to the build-graph, which builds the Parser file and makes it available to import as 'Zli'
    zli.buildParser(b, zli_dep.module("zli"), exe, "src/cli.zig");
    b.installArtifact(exe);
    // ...
}
```

Now you need to create a seperate Zig-File to create the Step for building the Parser. For example, it can look like this:

```zig
// src/cli.zig
const zli = @import("zli");

pub fn main() !void {
    try zli.generateParser(.{
        .options = .{
            .bool = .{ .type = bool, .short = 'b', .desc = "Just some random flag" },
            .str = .{ .type = []const u8, .desc = "Put something to say here, it's a string, duh", .value_hint = "STRING" },
            .int = .{ .type = i32, .short = 'i', .desc = "If you have a number, put it here", .default = 0, .value_hint = "INT" },
            .help = .{ .type = bool, .short = 'h', .desc = "Print this help text" },
            .long_name = .{ .type = f32, .desc = "A long option-name, just to pass a float", .value_hint = "FLOAT" },
        },
        .arguments = .{
            .age = .{ .type = u8, .pos = 0, .desc = "Put in your age as the first argument", .value_hint = "INT" },
            .name = .{ .type = []const u8, .pos = 1, .desc = "Put your name as the second argument", .value_hint = "STRING" },
        },
    });
}
```

