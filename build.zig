const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = .{
        // Off by default, and deliberately NOT tied to `optimize`: Zig's C
        // sanitizer emits calls into a runtime linked only into a compilation
        // that is itself sanitized, so defaulting it on in Debug hands a
        // consumer who forgot to forward `optimize` a link failure naming a
        // __ubsan symbol. The suite turns it on explicitly instead.
        .sanitize_c = b.option(
            bool,
            "sanitize_c",
            "Compile the C with Zig's undefined-behaviour sanitizer",
        ) orelse false,
    };

    // Every behaviour-affecting option is mirrored into a Zig module so the
    // wrapper can never disagree with how the C was compiled; the version
    // rides along so a test can compare what the library REPORTS against
    // build.zig.zon rather than against a literal of its own.
    const options_step = b.addOptions();
    options_step.addOption([]const u8, "version", @import("build.zig.zon").version);
    inline for (std.meta.fields(@TypeOf(options))) |field| {
        options_step.addOption(field.type, field.name, @field(options, field.name));
    }
    const options_module = options_step.createModule();

    //=====================================================================
    // The C library: one translation unit instantiating the vendored
    // implementation-in-header parser and writer (src/cgltf_impl.c).
    // Static only: upstream declares no export macro, so a shared build
    // would be editing upstream's contract — see README's Scope.
    //=====================================================================

    const lib = b.addLibrary(.{
        .name = "zcgltf",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    lib.root_module.link_libc = true;
    lib.root_module.addIncludePath(b.path("libs/cgltf"));
    lib.root_module.addCSourceFile(.{
        .file = b.path("src/cgltf_impl.c"),
        .flags = &.{"-std=c99"},
    });
    lib.root_module.sanitize_c = if (options.sanitize_c) .full else .off;

    // C consumers get the vendored headers without reaching into the source
    // tree; tests/consumer proves an installed prefix resolves them.
    lib.installHeader(b.path("libs/cgltf/cgltf.h"), "cgltf.h");
    lib.installHeader(b.path("libs/cgltf/cgltf_write.h"), "cgltf_write.h");

    //=====================================================================
    // The Zig module.
    //=====================================================================

    const module = b.addModule("zcgltf", .{
        .root_source_file = b.path("src/zcgltf.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zcgltf_options", .module = options_module },
        },
    });
    // No include path: the wrapper hand-writes its externs rather than
    // @cImport-ing the header, so nothing Zig-side compiles C.
    module.linkLibrary(lib);

    // Registered unconditionally: `std.Build.Dependency.artifact` scans the
    // dependency's install step, so an artifact not installed here is one
    // `dep.artifact("zcgltf")` cannot find. This does not pollute a
    // consumer's prefix — a dependency's install step only runs when
    // something actually depends on it.
    b.installArtifact(lib);

    //=====================================================================
    // Tests.
    //=====================================================================

    const tests = b.addTest(.{
        .name = "zcgltf-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zcgltf.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zcgltf_options", .module = options_module },
            },
        }),
    });
    tests.root_module.linkLibrary(lib);
    // The ABI cross-check @cImports the vendored header. Wired here, on the
    // test module, and deliberately not on the shipped module above. No
    // build macros go with it: no cgltf configuration macro changes a type's
    // layout (see UPSTREAM.md).
    tests.root_module.addIncludePath(b.path("libs/cgltf"));

    const test_step = b.step("test", "Run zcgltf tests");
    const run_tests = b.addRunArtifact(tests);
    // Tests read the checked-in asset by repo-relative path.
    run_tests.setCwd(b.path("."));
    test_step.dependOn(&run_tests.step);

    // A C-only smoke test proves the installed headers and library stand on
    // their own, independent of anything Zig-side.
    const c_smoke = b.addExecutable(.{
        .name = "zcgltf-c-smoke",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });
    c_smoke.root_module.link_libc = true;
    c_smoke.root_module.addIncludePath(b.path("libs/cgltf"));
    c_smoke.root_module.addCSourceFile(.{
        .file = b.path("tests/c_smoke.c"),
        .flags = &.{"-std=c99"},
    });
    c_smoke.root_module.linkLibrary(lib);

    const c_test_step = b.step("test-c", "Run the C-level smoke test");
    c_test_step.dependOn(&b.addRunArtifact(c_smoke).step);
    test_step.dependOn(c_test_step);

    //=====================================================================
    // Examples
    //
    // Built AND run, against the module a consumer gets. An example that is
    // only compiled proves the names still resolve; running it is what
    // proves the pipeline still works. examples/usage.zig is also where
    // README.md's Usage block comes from — see ci/readme_usage.sh — so a
    // snippet a reader copies cannot drift from code CI executes.
    //=====================================================================

    const examples_step = b.step("examples", "Build and run the examples");
    for (example_sources) |source| {
        const example = b.addExecutable(.{
            .name = std.fs.path.stem(source),
            .root_module = b.createModule(.{
                .root_source_file = b.path(source),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "zcgltf", .module = module }},
            }),
        });
        const run = b.addRunArtifact(example);
        // Examples read the checked-in asset by repo-relative path.
        run.setCwd(b.path("."));
        examples_step.dependOn(&run.step);
    }
    test_step.dependOn(examples_step);
}

/// Every example, listed rather than globbed: a build graph that scans a
/// directory is not reproducible from the manifest alone.
const example_sources = [_][]const u8{
    "examples/usage.zig",
};
