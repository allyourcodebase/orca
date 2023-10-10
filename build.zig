const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const upstream = b.dependency("orca", .{});
    const angle_dep = b.dependency("angle", .{});

    // For the orca python script
    const orca_dir = b.addNamedWriteFiles("orca_dir");
    _ = orca_dir.addCopyFile(upstream.path("resources/Menlo.ttf"), "resources/Menlo.ttf");
    _ = orca_dir.addCopyFile(upstream.path("resources/Menlo Bold.ttf"), "resources/Menlo Bold.ttf");
    _ = orca_dir.addCopyFile(angle_dep.path("bin/libGLESv2.dylib"), "src/ext/angle/bin/libGLESv2.dylib");
    _ = orca_dir.addCopyFile(angle_dep.path("bin/libEGL.dylib"), "src/ext/angle/bin/libEGL.dylib");

    const liborca = b.addSharedLibrary(.{
        .name = "orca",
        .target = target,
        .optimize = optimize,
    });
    _ = orca_dir.addCopyFile(liborca.getEmittedBin(), "build/bin/liborca.dylib");

    liborca.addIncludePath(upstream.path("src"));
    liborca.addIncludePath(upstream.path("src/util"));
    liborca.addIncludePath(upstream.path("src/platform"));
    liborca.addIncludePath(upstream.path("src/ext"));
    liborca.addIncludePath(angle_dep.path("include"));

    if (optimize == .Debug) {
        liborca.defineCMacro("OC_DEBUG", null);
        liborca.defineCMacro("OC_LOG_COMPILE_DEBUG", null);
    }

    liborca.addCSourceFile(.{
        .file = upstream.path("src/orca.c"),
        .flags = &.{
            "-std=c11",
            "-fno-sanitize=undefined", // :^(
        },
    });

    const wasm3 = b.addStaticLibrary(.{
        .name = "wasm3",
        .target = target,
        .optimize = .ReleaseFast,
    });

    wasm3.addIncludePath(upstream.path("src/ext/wasm3/source"));
    wasm3.addCSourceFiles(.{
        .dependency = upstream,
        .files = &.{
            "src/ext/wasm3/source/m3_api_libc.c",
            "src/ext/wasm3/source/m3_api_meta_wasi.c",
            "src/ext/wasm3/source/m3_api_tracer.c",
            "src/ext/wasm3/source/m3_api_uvwasi.c",
            "src/ext/wasm3/source/m3_api_wasi.c",
            "src/ext/wasm3/source/m3_bind.c",
            "src/ext/wasm3/source/m3_code.c",
            "src/ext/wasm3/source/m3_compile.c",
            "src/ext/wasm3/source/m3_core.c",
            "src/ext/wasm3/source/m3_env.c",
            "src/ext/wasm3/source/m3_exec.c",
            "src/ext/wasm3/source/m3_function.c",
            "src/ext/wasm3/source/m3_info.c",
            "src/ext/wasm3/source/m3_module.c",
            "src/ext/wasm3/source/m3_parse.c",
        },
        .flags = &.{
            "-Dd_m3HasWASI",
            "-fno-sanitize=undefined", // :^(
        },
    });

    switch (target.getOsTag()) {
        .macos => {
            liborca.addCSourceFiles(.{
                .dependency = upstream,
                .files = &.{
                    "src/orca.m",
                },
                .flags = &.{
                    "-std=c11",
                    "-fno-sanitize=undefined", // :^(
                },
            });

            liborca.addLibraryPath(angle_dep.path("bin"));
            liborca.linkFramework("Carbon");
            liborca.linkFramework("Cocoa");
            liborca.linkFramework("Metal");
            liborca.linkFramework("QuartzCore");
            liborca.linkSystemLibrary2("EGL", .{ .weak = true });
            liborca.linkSystemLibrary2("GLESv2", .{ .weak = true });
        },
        else => {},
    }

    liborca.linkLibC();

    const exe = b.addExecutable(.{
        .name = "orca_runtime",
        .target = target,
        .optimize = optimize,
    });

    _ = orca_dir.addCopyFile(exe.getEmittedBin(), "build/bin/orca_runtime");

    exe.addIncludePath(upstream.path("src"));
    exe.addIncludePath(upstream.path("src/ext"));
    exe.addIncludePath(angle_dep.path("include"));
    exe.addIncludePath(upstream.path("src/ext/wasm3/source"));
    exe.linkLibrary(liborca);
    exe.linkLibrary(wasm3);

    exe.addCSourceFiles(.{
        .dependency = upstream,
        .files = &.{
            "src/runtime.c",
        },
        .flags = &.{
            "-std=c11",
            "-fno-sanitize=undefined", // :^(
        },
    });

    if (optimize == .Debug) {
        exe.defineCMacro("OC_DEBUG", null);
        exe.defineCMacro("OC_LOG_COMPILE_DEBUG", null);
    }

    // metal shaders
    if (target.getOsTag() == .macos) {
        const xcrun1 = b.addSystemCommand(&.{
            "xcrun",
            "-sdk",
            "macosx",
            "metal",
            "-fno-fast-math",
            "-c",
            "-o",
        });
        const mtl_renderer_air = xcrun1.addOutputFileArg("mtl_renderer.air");
        xcrun1.addFileArg(upstream.path("src/graphics/mtl_renderer.metal"));

        const xcrun2 = b.addSystemCommand(&.{
            "xcrun",
            "-sdk",
            "macosx",
            "metallib",
            "-o",
        });
        const mtl_renderer = xcrun2.addOutputFileArg("mtl_renderer.metallib");
        _ = orca_dir.addCopyFile(mtl_renderer, "build/bin/mtl_renderer.metallib");

        xcrun2.addFileArg(mtl_renderer_air);
        b.getInstallStep().dependOn(&b.addInstallFile(
            mtl_renderer,
            "bin/mtl_renderer.metallib",
        ).step);
    }
    const embed_text_files = b.addSystemCommand(&.{
        "python3",
    });

    embed_text_files.addFileArg(upstream.path("scripts/embed_text_files.py"));
    embed_text_files.addArgs(&.{
        "-p",
        "glsl_",
        "-o",
    });

    const shaders = embed_text_files.addOutputFileArg("glsl_shaders.h");
    _ = shaders;

    embed_text_files.addFileArg(upstream.path("src/graphics/glsl_shaders/common.glsl"));
    embed_text_files.addFileArg(upstream.path("src/graphics/glsl_shaders/blit_vertex.glsl"));
    embed_text_files.addFileArg(upstream.path("src/graphics/glsl_shaders/blit_fragment.glsl"));
    embed_text_files.addFileArg(upstream.path("src/graphics/glsl_shaders/path_setup.glsl"));
    embed_text_files.addFileArg(upstream.path("src/graphics/glsl_shaders/segment_setup.glsl"));
    embed_text_files.addFileArg(upstream.path("src/graphics/glsl_shaders/backprop.glsl"));
    embed_text_files.addFileArg(upstream.path("src/graphics/glsl_shaders/merge.glsl"));
    embed_text_files.addFileArg(upstream.path("src/graphics/glsl_shaders/raster.glsl"));
    embed_text_files.addFileArg(upstream.path("src/graphics/glsl_shaders/balance_workgroups.glsl"));

    // b.getInstallStep().dependOn(&b.addInstallFile(shaders, "glsl_shaders.h").step);
    b.getInstallStep().dependOn(&b.addInstallArtifact(liborca, .{ .dest_dir = .{ .override = .bin } }).step);

    const write_bindings = b.addNamedWriteFiles("stubs");
    exe.addIncludePath(write_bindings.getDirectory());

    const gles_json = blk: {
        const gles_bindgen_step = b.addSystemCommand(&.{
            "python3",
        });

        // gles_bindgen_step.lazy_cwd = upstream.path("scripts/");

        gles_bindgen_step.addFileArg(upstream.path("scripts/gles_gen.py"));
        gles_bindgen_step.addArg("--spec");
        gles_bindgen_step.addFileArg(upstream.path("src/ext/gl.xml"));
        gles_bindgen_step.addArg("--header");
        const gles_header_name = "graphics/orca_gl31.h";
        _ = write_bindings.addCopyFile(gles_bindgen_step.addOutputFileArg(gles_header_name), gles_header_name);
        gles_bindgen_step.addArg("--log");
        gles_bindgen_step.addArg("/dev/null");

        gles_bindgen_step.addArg("--json");
        break :blk gles_bindgen_step.addOutputFileArg("wasmbind/gles_api.json");
    };

    generateBindings(
        b,
        upstream,
        write_bindings,
        "gles",
        gles_json,
        null,
        null,
        "wasmbind/gles_api_bind_gen.c",
    );

    generateBindings(
        b,
        upstream,
        write_bindings,
        "core",
        upstream.path("src/wasmbind/core_api.json"),
        "wasmbind/core_api_stubs.c",
        null,
        "wasmbind/core_api_bind_gen.c",
    );

    generateBindings(
        b,
        upstream,
        write_bindings,
        "surface",
        upstream.path("src/wasmbind/surface_api.json"),
        "graphics/orca_surface_stubs.c",
        "graphics/graphics.h",
        "wasmbind/surface_api_bind_gen.c",
    );

    generateBindings(
        b,
        upstream,
        write_bindings,
        "clock",
        upstream.path("src/wasmbind/clock_api.json"),
        null,
        "platform/platform_clock.h",
        "wasmbind/clock_api_bind_gen.c",
    );
    generateBindings(
        b,
        upstream,
        write_bindings,
        "io",
        upstream.path("src/wasmbind/io_api.json"),
        "platform/orca_io_stubs.c",
        null,
        "wasmbind/io_api_bind_gen.c",
    );

    b.installArtifact(exe);
}

fn generateBindings(
    b: *std.Build,
    upstream: *std.Build.Dependency,
    write: *std.Build.WriteFileStep,
    api: []const u8,
    spec: std.Build.LazyPath,
    guest_stubs_basename_opt: ?[]const u8,
    guest_include: ?[]const u8,
    wasm3_bindings_basename_opt: ?[]const u8,
) void {
    const bindgen_step = b.addSystemCommand(&.{
        "python3",
    });

    bindgen_step.addFileArg(upstream.path("scripts/bindgen.py"));
    bindgen_step.addArg(api);
    bindgen_step.addFileArg(spec);
    bindgen_step.addArg("--guest-stubs");
    const guest_stubs_basename = guest_stubs_basename_opt orelse
        b.fmt("bindgen_{s}_guest_stubs.c", .{api});
    const gs = bindgen_step.addOutputFileArg(guest_stubs_basename);

    if (guest_include) |gi| {
        bindgen_step.addArg("--guest-include");
        bindgen_step.addArg(gi);
    }

    bindgen_step.addArg("--wasm3-bindings");
    const wasm3_bindings_basename = wasm3_bindings_basename_opt orelse
        b.fmt("bindgen_{s}_wasm3_bindings.c", .{api});
    const wb = bindgen_step.addOutputFileArg(wasm3_bindings_basename);

    if (guest_stubs_basename_opt != null) {
        _ = write.addCopyFile(gs, guest_stubs_basename);
    }
    _ = write.addCopyFile(wb, wasm3_bindings_basename);
}
const libc_shim_files: []const []const u8 = &.{
    "src/libc-shim/src/__cos.c",
    "src/libc-shim/src/__cosdf.c",
    "src/libc-shim/src/__errno_location.c",
    "src/libc-shim/src/__math_divzero.c",
    "src/libc-shim/src/__math_divzerof.c",
    "src/libc-shim/src/__math_invalid.c",
    "src/libc-shim/src/__math_invalidf.c",
    "src/libc-shim/src/__math_oflow.c",
    "src/libc-shim/src/__math_oflowf.c",
    "src/libc-shim/src/__math_uflow.c",
    "src/libc-shim/src/__math_uflowf.c",
    "src/libc-shim/src/__math_xflow.c",
    "src/libc-shim/src/__math_xflowf.c",
    "src/libc-shim/src/__rem_pio2.c",
    "src/libc-shim/src/__rem_pio2_large.c",
    "src/libc-shim/src/__rem_pio2f.c",
    "src/libc-shim/src/__sin.c",
    "src/libc-shim/src/__sindf.c",
    "src/libc-shim/src/__tan.c",
    "src/libc-shim/src/__tandf.c",
    "src/libc-shim/src/abs.c",
    "src/libc-shim/src/acos.c",
    "src/libc-shim/src/acosf.c",
    "src/libc-shim/src/asin.c",
    "src/libc-shim/src/asinf.c",
    "src/libc-shim/src/atan.c",
    "src/libc-shim/src/atan2.c",
    "src/libc-shim/src/atan2f.c",
    "src/libc-shim/src/atanf.c",
    "src/libc-shim/src/cbrt.c",
    "src/libc-shim/src/cbrtf.c",
    "src/libc-shim/src/ceil.c",
    "src/libc-shim/src/cos.c",
    "src/libc-shim/src/cosf.c",
    "src/libc-shim/src/exp.c",
    "src/libc-shim/src/exp2f_data.c",
    "src/libc-shim/src/exp_data.c",
    "src/libc-shim/src/expf.c",
    "src/libc-shim/src/fabs.c",
    "src/libc-shim/src/fabsf.c",
    "src/libc-shim/src/floor.c",
    "src/libc-shim/src/fmod.c",
    "src/libc-shim/src/log.c",
    "src/libc-shim/src/log2.c",
    "src/libc-shim/src/log2_data.c",
    "src/libc-shim/src/log2f.c",
    "src/libc-shim/src/log2f_data.c",
    "src/libc-shim/src/log_data.c",
    "src/libc-shim/src/logf.c",
    "src/libc-shim/src/logf_data.c",
    "src/libc-shim/src/pow.c",
    "src/libc-shim/src/powf.c",
    "src/libc-shim/src/powf_data.c",
    "src/libc-shim/src/scalbn.c",
    "src/libc-shim/src/sin.c",
    "src/libc-shim/src/sinf.c",
    "src/libc-shim/src/sqrt.c",
    "src/libc-shim/src/sqrt_data.c",
    "src/libc-shim/src/sqrtf.c",
    "src/libc-shim/src/string.c",
    "src/libc-shim/src/tan.c",
    "src/libc-shim/src/tanf.c",
};

const AppOptions = struct {
    name: []const u8,
    resource_dir: ?std.Build.LazyPath,
    optimize: std.builtin.OptimizeMode,
    root_source_file: std.Build.LazyPath,
};

pub fn addApp(b: *std.build.Builder, orca_dep: *std.Build.Dependency, options: AppOptions) std.Build.LazyPath {
    const upstream = orca_dep.builder.dependency("orca", .{});

    const app = b.addSharedLibrary(.{
        .name = "module",
        .target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
            .cpu_features_add = std.Target.wasm.featureSet(&.{.bulk_memory}),
        },
        .optimize = options.optimize,
        .root_source_file = .{ .path = "src/main.zig" },
    });

    app.rdynamic = true;
    app.disable_sanitize_c = true;
    app.defineCMacro("__ORCA__", null);
    app.addSystemIncludePath(upstream.path("src/libc-shim/include"));
    app.addIncludePath(upstream.path("src"));
    app.addIncludePath(upstream.path("src/ext"));
    app.addIncludePath(orca_dep.namedWriteFiles("stubs").getDirectory());

    const cflags: []const []const u8 = &.{
        "-O2", // works around undefined symbol on __fpclassifyl
    };
    app.addCSourceFile(.{
        .file = upstream.path("src/orca.c"),
        .flags = cflags,
    });
    app.addCSourceFiles(.{
        .dependency = upstream,
        .files = libc_shim_files,
        .flags = cflags,
    });

    const bundle = b.addSystemCommand(&.{
        "python3",
    });

    const orca_dir = orca_dep.namedWriteFiles("orca_dir").getDirectory();

    bundle.addFileArg(upstream.path("orca"));
    bundle.addArgs(&.{ "bundle", "--orca-dir" });

    bundle.addDirectoryArg(orca_dir);

    bundle.addArgs(&.{
        "--name", options.name,
    });

    if (options.resource_dir) |rd| {
        bundle.addArgs(&.{"--resource-dir"});
        bundle.addDirectoryArg(rd);
    }

    bundle.addArgs(&.{"--out-dir"});
    const output = bundle.addOutputFileArg(".");

    bundle.addFileArg(app.getEmittedBin());

    return output;
}
