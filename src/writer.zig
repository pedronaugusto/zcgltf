//! Idiomatic layer: the glTF writer (`cgltf_write.h`), with the size-query
//! dance folded into an allocating wrapper.
//!
//! Scope, upstream's: the writer serializes document STRUCTURE — buffer
//! payloads are written only as GLB bin chunks or carried in existing URIs,
//! and `EXT_meshopt_compression` is parse-only (see UPSTREAM.md).

const std = @import("std");
const c = @import("c.zig");
const t = c.types;
const document = @import("document.zig");

/// Writes the document to `path` through `options.file`; `options.type =
/// .glb` emits JSON and `buffers[0]`'s bin chunk in one container.
pub fn writeFile(options: *const t.Options, path: [:0]const u8, data: *const t.Data) document.Error!void {
    try document.check(c.write.cgltf_write_file(options, path.ptr, data));
}

/// Serializes the document's JSON into memory owned by `allocator`. The
/// result is the exact JSON text (the C terminator is dropped).
pub fn writeAlloc(
    allocator: std.mem.Allocator,
    options: *const t.Options,
    data: *const t.Data,
) (document.Error || std.mem.Allocator.Error)![]u8 {
    const needed = c.write.cgltf_write(options, null, 0, data);
    if (needed == 0) return error.InvalidGltf;

    const buffer = try allocator.alloc(u8, needed);
    errdefer allocator.free(buffer);
    const written = c.write.cgltf_write(options, buffer.ptr, buffer.len, data);
    if (written != needed) return error.InvalidGltf;
    return allocator.realloc(buffer, needed - 1);
}

const test_asset_path = "tests/data/triangle.gltf";

test writeAlloc {
    var options = std.mem.zeroes(t.Options);
    const data = try document.parseFile(&options, test_asset_path);
    defer document.free(data);

    const json = try writeAlloc(std.testing.allocator, &options, data);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.startsWith(u8, json, "{"));

    // Round trip: the writer's output parses back to the same shape.
    const reparsed = try document.parse(&options, json);
    defer document.free(reparsed);
    try document.validate(reparsed);
    try std.testing.expectEqual(data.accessors_count, reparsed.accessors_count);
    try std.testing.expectEqual(data.meshes_count, reparsed.meshes_count);
}

test writeFile {
    var options = std.mem.zeroes(t.Options);
    const data = try document.parseFile(&options, test_asset_path);
    defer document.free(data);
    // GLB needs the bin payload in memory.
    try document.loadBuffers(&options, data, test_asset_path);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    // The tmp dir lives at this cwd-relative path by construction, and the
    // writer goes through fopen, which resolves against the cwd too.
    const glb_path = try std.fmt.allocPrintSentinel(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/triangle.glb",
        .{tmp.sub_path},
        0,
    );
    defer std.testing.allocator.free(glb_path);

    var glb_options = std.mem.zeroes(t.Options);
    glb_options.type = .glb;
    try writeFile(&glb_options, glb_path, data);

    // Round trip through the binary container, bin chunk included.
    const reparsed = try document.parseFile(&glb_options, glb_path);
    defer document.free(reparsed);
    try document.loadBuffers(&glb_options, reparsed, glb_path);
    try document.validate(reparsed);

    const prim = &reparsed.meshes.?[0].primitives.?[0];
    const positions = @import("access.zig").findAccessor(prim, .position, 0) orelse
        return error.TestUnexpectedResult;
    var v: [3]f32 = undefined;
    try std.testing.expect(@import("access.zig").readFloat(positions, 1, &v));
    try std.testing.expectEqual([3]f32{ 1, 0, 0 }, v);
}
