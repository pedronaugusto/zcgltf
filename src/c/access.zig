//! Externs: reading parsed data — node transforms, buffer views, accessors.

const t = @import("types.zig");

/// Writes the node's local transform as a column-major 4x4 into
/// `out_matrix` (16 floats), composing TRS when no matrix is present.
pub extern fn cgltf_node_transform_local(node: *const t.Node, out_matrix: [*]t.Float) void;

/// Local transform pre-multiplied by every ancestor's, same layout.
pub extern fn cgltf_node_transform_world(node: *const t.Node, out_matrix: [*]t.Float) void;

/// The view's bytes: `view.data` when an extension decoded it, else
/// `buffer.data + offset`. Null until the backing buffer is loaded.
pub extern fn cgltf_buffer_view_data(view: *const t.BufferView) ?[*]const u8;

/// The primitive's accessor for (`type`, `index`), or null.
pub extern fn cgltf_find_accessor(prim: *const t.Primitive, type: t.AttributeType, index: t.Int) ?*const t.Accessor;

/// Reads element `index` as floats into `out` (`element_size` entries,
/// at least `numComponents(accessor.type)`), converting and normalizing per
/// the accessor. Returns 0 when data is missing or `element_size` is short.
pub extern fn cgltf_accessor_read_float(accessor: *const t.Accessor, index: t.Size, out: [*]t.Float, element_size: t.Size) t.Bool32;

/// Same, converting to unsigned integers; float sources are refused.
pub extern fn cgltf_accessor_read_uint(accessor: *const t.Accessor, index: t.Size, out: [*]t.Uint, element_size: t.Size) t.Bool32;

/// Reads single-component element `index` as an index value; 0 when the
/// backing data is missing.
pub extern fn cgltf_accessor_read_index(accessor: *const t.Accessor, index: t.Size) t.Size;

/// Component count of a `cgltf_type` (vec3 -> 3).
pub extern fn cgltf_num_components(type: t.Type) t.Size;

/// Byte size of one component (r_16u -> 2).
pub extern fn cgltf_component_size(component_type: t.ComponentType) t.Size;

/// Byte size of one element, matrix column padding included.
pub extern fn cgltf_calc_size(type: t.Type, component_type: t.ComponentType) t.Size;

/// Unpacks up to `float_count` floats across whole elements; returns how
/// many were written, or with `out == null` the count needed.
pub extern fn cgltf_accessor_unpack_floats(accessor: *const t.Accessor, out: ?[*]t.Float, float_count: t.Size) t.Size;

/// Unpacks `index_count` single-component values into `out` as integers of
/// `out_component_size` bytes (1, 2, 4 or 8); with `out == null` returns
/// the count needed. Values that overflow the output width are truncated.
pub extern fn cgltf_accessor_unpack_indices(accessor: *const t.Accessor, out: ?*anyopaque, out_component_size: t.Size, index_count: t.Size) t.Size;

/// Deprecated upstream (use `Extras.data`): copies the extras JSON span
/// into `dest`; with `dest == null` writes the needed size to `dest_size`.
pub extern fn cgltf_copy_extras_json(data: *const t.Data, extras: *const t.Extras, dest: ?[*]u8, dest_size: *t.Size) t.Result;
