//! Idiomatic layer: reading parsed data — node transforms, buffer views and
//! accessors — with slices in and out instead of pointer/length pairs.

const std = @import("std");
const c = @import("c.zig");
const t = c.types;

/// The node's local transform as a column-major 4x4, composing TRS when no
/// matrix is present.
pub fn nodeTransformLocal(node: *const t.Node) [16]f32 {
    var out: [16]f32 = undefined;
    c.access.cgltf_node_transform_local(node, &out);
    return out;
}

/// The local transform pre-multiplied by every ancestor's, same layout.
pub fn nodeTransformWorld(node: *const t.Node) [16]f32 {
    var out: [16]f32 = undefined;
    c.access.cgltf_node_transform_world(node, &out);
    return out;
}

/// The view's bytes: `view.data` when an extension decoded it, else
/// `buffer.data + offset`. Null until the backing buffer is loaded.
pub fn bufferViewData(view: *const t.BufferView) ?[]const u8 {
    const ptr = c.access.cgltf_buffer_view_data(view) orelse return null;
    return ptr[0..view.size];
}

/// The primitive's accessor for (`attribute_type`, `index`), or null.
pub fn findAccessor(prim: *const t.Primitive, attribute_type: t.AttributeType, index: i32) ?*const t.Accessor {
    return c.access.cgltf_find_accessor(prim, attribute_type, index);
}

// The three per-element readers below guard `index` themselves. Upstream
// checks `is_sparse` and a null view, then computes
// `element += accessor->offset + accessor->stride * index` against nothing
// (cgltf.h:2371, 2500, 2534), so an out-of-range index reads past the view.
// The bulk `unpack*` entry points need no guard: upstream clamps them.

/// Reads element `index` as floats into `out`, converting and normalizing
/// per the accessor. False when `index` is past the accessor's last element,
/// when the backing data is missing, or when `out` is shorter than the
/// element's component count.
pub fn readFloat(accessor: *const t.Accessor, index: usize, out: []f32) bool {
    if (index >= accessor.count) return false;
    return c.access.cgltf_accessor_read_float(accessor, index, out.ptr, out.len) != 0;
}

/// Same, converting to unsigned integers; float-sourced accessors are
/// refused.
pub fn readUint(accessor: *const t.Accessor, index: usize, out: []u32) bool {
    if (index >= accessor.count) return false;
    return c.access.cgltf_accessor_read_uint(accessor, index, out.ptr, out.len) != 0;
}

/// Reads single-component element `index` as an index value; 0 when `index`
/// is past the accessor's last element or the backing data is missing
/// (indistinguishable from a real 0 — upstream's contract).
pub fn readIndex(accessor: *const t.Accessor, index: usize) usize {
    if (index >= accessor.count) return 0;
    return c.access.cgltf_accessor_read_index(accessor, index);
}

/// Component count of a `Type` (`.vec3` -> 3).
pub fn numComponents(kind: t.Type) usize {
    return c.access.cgltf_num_components(kind);
}

/// Byte size of one component (`.r_16u` -> 2).
pub fn componentSize(component_type: t.ComponentType) usize {
    return c.access.cgltf_component_size(component_type);
}

/// Byte size of one element, matrix column padding included.
pub fn calcSize(kind: t.Type, component_type: t.ComponentType) usize {
    return c.access.cgltf_calc_size(kind, component_type);
}

/// How many floats `unpackFloats` needs for the whole accessor.
pub fn unpackFloatsCount(accessor: *const t.Accessor) usize {
    return c.access.cgltf_accessor_unpack_floats(accessor, null, 0);
}

/// Unpacks as many whole elements as fit into `out`, converting and
/// normalizing per the accessor; returns the written prefix (empty when the
/// backing data is missing).
pub fn unpackFloats(accessor: *const t.Accessor, out: []f32) []f32 {
    return out[0..c.access.cgltf_accessor_unpack_floats(accessor, out.ptr, out.len)];
}

/// How many values `unpackIndices` needs for the whole accessor.
pub fn unpackIndicesCount(accessor: *const t.Accessor) usize {
    return c.access.cgltf_accessor_unpack_indices(accessor, null, 8, 0);
}

/// Unpacks single-component values into `out` (`T` one of u8/u16/u32/u64);
/// returns the written prefix. Values wider than `T` are truncated —
/// upstream's contract, so pick `T` from the accessor's component type.
pub fn unpackIndices(accessor: *const t.Accessor, comptime T: type, out: []T) []T {
    comptime std.debug.assert(T == u8 or T == u16 or T == u32 or T == u64);
    const n = c.access.cgltf_accessor_unpack_indices(accessor, out.ptr, @sizeOf(T), out.len);
    return out[0..n];
}

const document = @import("document.zig");
const test_asset_path = "tests/data/triangle.gltf";

fn parseTestAsset(options: *const t.Options) !*t.Data {
    const data = try document.parseFile(options, test_asset_path);
    errdefer document.free(data);
    try document.loadBuffers(options, data, test_asset_path);
    return data;
}

test readFloat {
    var options = std.mem.zeroes(t.Options);
    const data = try parseTestAsset(&options);
    defer document.free(data);

    const prim = &data.meshes.?[0].primitives.?[0];
    const positions = findAccessor(prim, .position, 0) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 3), numComponents(positions.type));
    try std.testing.expectEqual(@as(usize, 4), componentSize(positions.component_type));
    try std.testing.expectEqual(@as(usize, 12), calcSize(positions.type, positions.component_type));

    var v: [3]f32 = undefined;
    try std.testing.expect(readFloat(positions, 2, &v));
    try std.testing.expectEqual([3]f32{ 0, 1, 0 }, v);

    try std.testing.expectEqual(@as(usize, 9), unpackFloatsCount(positions));
    var all: [9]f32 = undefined;
    try std.testing.expectEqual(@as(usize, 9), unpackFloats(positions, &all).len);
    try std.testing.expectEqual(@as(f32, 1), all[3]);

    const indices = prim.indices orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 3), unpackIndicesCount(indices));
    var idx: [3]u16 = undefined;
    try std.testing.expectEqualSlices(u16, &.{ 0, 1, 2 }, unpackIndices(indices, u16, &idx));
    try std.testing.expectEqual(@as(usize, 2), readIndex(indices, 2));
    var one: [1]u32 = undefined;
    try std.testing.expect(readUint(indices, 1, &one));
    try std.testing.expectEqual(@as(u32, 1), one[0]);

    const view = indices.buffer_view orelse return error.TestUnexpectedResult;
    const bytes = bufferViewData(view) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 6), bytes.len);
}

test "the per-element readers refuse an index past the accessor's end" {
    // Upstream would compute `offset + stride * index` and read past the
    // buffer view; the guards in this module are what make that a refusal.
    var options = std.mem.zeroes(t.Options);
    const data = try parseTestAsset(&options);
    defer document.free(data);

    const prim = &data.meshes.?[0].primitives.?[0];
    const positions = findAccessor(prim, .position, 0) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 3), positions.count);

    var v: [3]f32 = undefined;
    try std.testing.expect(readFloat(positions, 2, &v));
    try std.testing.expect(!readFloat(positions, 3, &v));
    try std.testing.expect(!readFloat(positions, std.math.maxInt(usize), &v));

    const indices = prim.indices orelse return error.TestUnexpectedResult;
    var one: [1]u32 = undefined;
    try std.testing.expect(readUint(indices, 2, &one));
    try std.testing.expect(!readUint(indices, 3, &one));
    try std.testing.expectEqual(@as(usize, 0), readIndex(indices, 3));
}

test nodeTransformLocal {
    var options = std.mem.zeroes(t.Options);
    const data = try parseTestAsset(&options);
    defer document.free(data);

    // The asset's one node carries no TRS, so both transforms are identity.
    const node = &data.nodes.?[0];
    const local = nodeTransformLocal(node);
    const world = nodeTransformWorld(node);
    try std.testing.expectEqual(@as(f32, 1), local[0]);
    try std.testing.expectEqual(@as(f32, 1), local[15]);
    try std.testing.expectEqualSlices(f32, &local, &world);
}
