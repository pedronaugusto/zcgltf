//! A downstream consumer of the `zcgltf` Zig module.
//!
//! What is under test: a consumer can reach the module through
//! `b.dependency` at all, the parse pipeline actually runs from out here,
//! and the build options zcgltf was compiled with are visible downstream.
const std = @import("std");
const zcgltf = @import("zcgltf");

// A whole document in a string: a triangle with its buffer inline as a
// base64 data URI, so the consumer needs no file next to it.
const gltf_json =
    \\{
    \\  "asset": { "version": "2.0" },
    \\  "meshes": [{ "primitives": [{ "attributes": { "POSITION": 0 } }] }],
    \\  "accessors": [{
    \\    "bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
    \\    "min": [0.0, 0.0, 0.0], "max": [1.0, 1.0, 0.0]
    \\  }],
    \\  "bufferViews": [{ "buffer": 0, "byteOffset": 0, "byteLength": 36 }],
    \\  "buffers": [{
    \\    "byteLength": 36,
    \\    "uri": "data:application/octet-stream;base64,AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAA"
    \\  }]
    \\}
;

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .{};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var options = std.mem.zeroes(zcgltf.Options);
    options.memory = zcgltf.memoryOptions(&gpa);

    const data = try zcgltf.parse(&options, gltf_json);
    defer zcgltf.free(data);
    try zcgltf.loadBuffers(&options, data, null);
    try zcgltf.validate(data);

    const prim = &data.meshes.?[0].primitives.?[0];
    const positions = zcgltf.findAccessor(prim, .position, 0) orelse
        return error.MissingPositions;
    var v: [3]f32 = undefined;
    if (!zcgltf.readFloat(positions, 1, &v)) return error.ReadFailed;
    if (v[0] != 1) return error.WrongVertex;

    // The options module is a separate export the dependency has to carry
    // alongside the code; reaching it from out here is the test.
    std.debug.print(
        "zig consumer ok: zcgltf {s}, sanitize_c {}, {} accessors\n",
        .{ zcgltf.version(), zcgltf.options.sanitize_c, data.accessors_count },
    );
}
