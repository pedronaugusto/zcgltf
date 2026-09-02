const std = @import("std");

/// The one place zcgltf and its sibling zmeshopt meet: an executable that
/// round-trips `EXT_meshopt_compression` end to end. zmeshopt is a
/// dependency of THIS package only — never of zcgltf itself — and it is a
/// path dependency on a sibling checkout, so this package builds where both
/// repositories are checked out side by side (`ci/run.sh --interop`).
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zcgltf = b.dependency("zcgltf", .{ .target = target, .optimize = optimize });
    const zmeshopt = b.dependency("zmeshopt", .{ .target = target, .optimize = optimize });

    const interop = b.addExecutable(.{
        .name = "interop",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zcgltf", .module = zcgltf.module("zcgltf") },
                .{ .name = "zmeshopt", .module = zmeshopt.module("zmeshopt") },
            },
        }),
    });

    const step = b.step("run", "Build and run the interop example");
    step.dependOn(&b.addRunArtifact(interop).step);
    b.getInstallStep().dependOn(step);
}
