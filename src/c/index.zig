//! Externs: object-to-index helpers. Each returns the element's position in
//! its owning array — pointer arithmetic upstream, with no bounds check, so
//! the object must belong to that document (or animation).

const t = @import("types.zig");

pub extern fn cgltf_mesh_index(data: *const t.Data, object: *const t.Mesh) t.Size;
pub extern fn cgltf_material_index(data: *const t.Data, object: *const t.Material) t.Size;
pub extern fn cgltf_accessor_index(data: *const t.Data, object: *const t.Accessor) t.Size;
pub extern fn cgltf_buffer_view_index(data: *const t.Data, object: *const t.BufferView) t.Size;
pub extern fn cgltf_buffer_index(data: *const t.Data, object: *const t.Buffer) t.Size;
pub extern fn cgltf_image_index(data: *const t.Data, object: *const t.Image) t.Size;
pub extern fn cgltf_texture_index(data: *const t.Data, object: *const t.Texture) t.Size;
pub extern fn cgltf_sampler_index(data: *const t.Data, object: *const t.Sampler) t.Size;
pub extern fn cgltf_skin_index(data: *const t.Data, object: *const t.Skin) t.Size;
pub extern fn cgltf_camera_index(data: *const t.Data, object: *const t.Camera) t.Size;
pub extern fn cgltf_light_index(data: *const t.Data, object: *const t.Light) t.Size;
pub extern fn cgltf_node_index(data: *const t.Data, object: *const t.Node) t.Size;
pub extern fn cgltf_scene_index(data: *const t.Data, object: *const t.Scene) t.Size;
pub extern fn cgltf_animation_index(data: *const t.Data, object: *const t.Animation) t.Size;
pub extern fn cgltf_animation_sampler_index(animation: *const t.Animation, object: *const t.AnimationSampler) t.Size;
pub extern fn cgltf_animation_channel_index(animation: *const t.Animation, object: *const t.AnimationChannel) t.Size;
