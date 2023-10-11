# orca
Zig build for https://orca-app.dev


## Usage
### Building an app
This build script exposes a `addApp` function that applications can use to compile, link and bundle their applications.

Usage example:
```zig
const std = @import("std");
const orca_build = @import("orca");

pub fn build(b: *std.build.Builder) void {
    const optimize = b.standardOptimizeOption(.{});
    const orca_dep = b.dependency("orca", .{});

    const app = orca_build.addApp(b, orca_dep, .{
        .name = "UIZ",
        .resource_dir = .{ .path = "data" },
        .optimize = optimize,
        .root_source_file = .{ .path = "src/main.zig" },
    });

    b.installDirectory(.{
        .source_dir = app,
        .install_dir = .prefix,
        .install_subdir = "",
    });
}
```

See https://github.com/kristoff-it/orca-ui-hello-zig for a complete example.

### Runtime only
Running `zig build` will produce the runtime assets which can then be used via other build scripts.


## Dependencies

- `xcrun` (for compiling metal shaders)
- Python (used by orca's own build scripts that we currently still use, see relative TODO bullet point)


## TODOs

- Implement the missing bundling features (eg adding icons), the current code only implements what's required to make Orca's UI sample work.
- Implement support for Windows (current code is macOS only).
- Remove the python dependency by implementing the same logic as part of the build script.
- Add support for having the application be implemented in C (contributor friendly!)
