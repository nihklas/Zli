# Zli

A very small and simple library for easy command line parsing in Zig.

This is written specifically for my personal needs and learning purposes.

For usage examples look at example/main.zig.

It is written with a current build of zig master. As it is still very much evolving, if something breaks because of a zig change,
feel free to open an issue, or even a pull request. But this is still a hobby/side project mostly for me personally, i cannot and
will not make any promises on when or if i get to the issue.

# Features

- Positional Arguments, accessable via names
- Options with both long and short forms, working as you would expect (`--long, -l`, `--long value, -l value`, `--long=value, -l=value`)
- Combined short flags (`-abc`)
- Help/Usage Text

# Usage

First, add Zli to your project by running
```cmd
zig fetch git+https://gitlab.com/nihklas/zli.git --save
```

After that, add this to your build.zig
```zig
const zli = b.dependency("zli", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("Zli", zli.module("Zli"));
```

To update the version, just run the `zig fetch`-command again
