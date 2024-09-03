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

# Usage

First, add Zli to your project by running
```cmd
zig fetch git+https://gitlab.com/nihklas/zli.git --save
```

After that, add this to your build.zig
```zig
const zli = b.dependency("zli", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zli", zli.module("zli"));
```

To update the version, just run the `zig fetch`-command again
