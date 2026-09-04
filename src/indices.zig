//! Idiomatic layer: object-to-index lookup, one comptime-dispatched entry
//! point over the 16 per-type C helpers. The object must belong to the
//! document (or animation) it is looked up in: upstream asserts that
//! (cgltf.h:2537), but the assert is compiled out under `NDEBUG`, so a
//! foreign object yields a garbage index instead of a diagnostic.

const std = @import("std");
const c = @import("c.zig");
const t = c.types;

/// The element's position in its owning array on `data`. Dispatches on the
/// pointee type; a type without an upstream index helper is a compile error.
pub fn indexOf(data: *const t.Data, object: anytype) usize {
    const i = c.index;
    return switch (@typeInfo(@TypeOf(object)).pointer.child) {
        t.Mesh => i.cgltf_mesh_index(data, object),
        t.Material => i.cgltf_material_index(data, object),
        t.Accessor => i.cgltf_accessor_index(data, object),
        t.BufferView => i.cgltf_buffer_view_index(data, object),
        t.Buffer => i.cgltf_buffer_index(data, object),
        t.Image => i.cgltf_image_index(data, object),
        t.Texture => i.cgltf_texture_index(data, object),
        t.Sampler => i.cgltf_sampler_index(data, object),
        t.Skin => i.cgltf_skin_index(data, object),
        t.Camera => i.cgltf_camera_index(data, object),
        t.Light => i.cgltf_light_index(data, object),
        t.Node => i.cgltf_node_index(data, object),
        t.Scene => i.cgltf_scene_index(data, object),
        t.Animation => i.cgltf_animation_index(data, object),
        else => @compileError("cgltf has no index helper for " ++
            @typeName(@typeInfo(@TypeOf(object)).pointer.child)),
    };
}

/// Same, for the two types owned by an animation rather than the document.
pub fn animationIndexOf(animation: *const t.Animation, object: anytype) usize {
    const i = c.index;
    return switch (@typeInfo(@TypeOf(object)).pointer.child) {
        t.AnimationSampler => i.cgltf_animation_sampler_index(animation, object),
        t.AnimationChannel => i.cgltf_animation_channel_index(animation, object),
        else => @compileError("an animation owns no " ++
            @typeName(@typeInfo(@TypeOf(object)).pointer.child)),
    };
}

const document = @import("document.zig");

test indexOf {
    var options = std.mem.zeroes(t.Options);
    const data = try document.parseFile(&options, "tests/data/triangle.gltf");
    defer document.free(data);

    try std.testing.expectEqual(@as(usize, 0), indexOf(data, &data.meshes.?[0]));
    try std.testing.expectEqual(@as(usize, 0), indexOf(data, &data.nodes.?[0]));
    try std.testing.expectEqual(@as(usize, 1), indexOf(data, &data.accessors.?[1]));
    try std.testing.expectEqual(@as(usize, 1), indexOf(data, &data.buffer_views.?[1]));
    try std.testing.expectEqual(@as(usize, 0), indexOf(data, &data.buffers.?[0]));
    try std.testing.expectEqual(@as(usize, 0), indexOf(data, &data.scenes.?[0]));
}
