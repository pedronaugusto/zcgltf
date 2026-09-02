//! zcgltf usage: parse a glTF document, load its buffers, validate, and
//! read vertex data back out through the accessor API — with cgltf's
//! allocations routed through a `std.mem.Allocator`.

const std = @import("std");
const zcgltf = @import("zcgltf");

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .{};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    // --- README:usage ---
    var options = std.mem.zeroes(zcgltf.Options);
    options.memory = zcgltf.memoryOptions(&gpa);

    const path = "tests/data/triangle.gltf";
    const data = try zcgltf.parseFile(&options, path);
    defer zcgltf.free(data);
    try zcgltf.loadBuffers(&options, data, path);
    try zcgltf.validate(data);

    const prim = &data.meshes.?[0].primitives.?[0];
    const positions = zcgltf.findAccessor(prim, .position, 0) orelse
        return error.MissingPositions;
    const indices = prim.indices orelse return error.MissingIndices;

    var corners: [9]f32 = undefined;
    const floats = zcgltf.unpackFloats(positions, &corners);
    var index_values: [3]u32 = undefined;
    const idx = zcgltf.unpackIndices(indices, u32, &index_values);
    // --- README:usage ---

    std.debug.print(
        "zcgltf {s}: {d} vertices, indices {any}, vertex 1 at ({d}, {d}, {d})\n",
        .{ zcgltf.version(), positions.count, idx, floats[3], floats[4], floats[5] },
    );
}
