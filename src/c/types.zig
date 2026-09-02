//! The cgltf document model: every typedef, enum and struct `cgltf.h`
//! declares, mirrored field for field in header order. `src/abi_check.zig`
//! holds each mirror to the vendored header by reflection — names, offsets,
//! scalar identities, enumerator values — so a drift is a build failure.
//!
//! Pointer nullability follows the parser's contract: a field the document
//! may omit is optional, an element pointer inside a counted array is not.

/// `cgltf_size`: byte and element counts (`size_t`).
pub const Size = usize;
/// `cgltf_ssize`: signed variant (`long long`), used by the implementation.
pub const SSize = i64;
/// `cgltf_float` / `cgltf_int` / `cgltf_uint` scalar typedefs.
pub const Float = f32;
pub const Int = i32;
pub const Uint = u32;
/// `cgltf_bool`: a C `int`; nonzero is true. The idiomatic layer converts.
pub const Bool32 = i32;

pub const FileType = enum(c_uint) {
    pub const upstream_prefix = "cgltf_file_type_";
    invalid,
    gltf,
    glb,
    max_enum,
};

pub const Result = enum(c_uint) {
    pub const upstream_prefix = "cgltf_result_";
    success,
    data_too_short,
    unknown_format,
    invalid_json,
    invalid_gltf,
    invalid_options,
    file_not_found,
    io_error,
    out_of_memory,
    legacy_gltf,
    max_enum,
};

/// `cgltf_memory_options`: allocation hooks for parsing and writing. Both
/// callbacks may be null (upstream falls back to malloc/free); `user`
/// receives `user_data`.
pub const MemoryOptions = extern struct {
    alloc_func: ?*const fn (user: ?*anyopaque, size: Size) callconv(.c) ?*anyopaque,
    free_func: ?*const fn (user: ?*anyopaque, ptr: ?*anyopaque) callconv(.c) void,
    user_data: ?*anyopaque,
};

/// `cgltf_file_options`: file I/O hooks for `parseFile`/`loadBuffers`. Both
/// callbacks may be null (upstream falls back to fopen/fread).
pub const FileOptions = extern struct {
    read: ?*const fn (memory_options: *const MemoryOptions, file_options: *const FileOptions, path: [*:0]const u8, size: *Size, data: *?*anyopaque) callconv(.c) Result,
    release: ?*const fn (memory_options: *const MemoryOptions, file_options: *const FileOptions, data: ?*anyopaque) callconv(.c) void,
    user_data: ?*anyopaque,
};

/// `cgltf_options`: `.type = .invalid` auto-detects glTF vs GLB;
/// `json_token_count == 0` sizes the token pool automatically.
pub const Options = extern struct {
    type: FileType,
    json_token_count: Size,
    memory: MemoryOptions,
    file: FileOptions,
};

pub const BufferViewType = enum(c_uint) {
    pub const upstream_prefix = "cgltf_buffer_view_type_";
    invalid,
    indices,
    vertices,
    max_enum,
};

pub const AttributeType = enum(c_uint) {
    pub const upstream_prefix = "cgltf_attribute_type_";
    invalid,
    position,
    normal,
    tangent,
    texcoord,
    color,
    joints,
    weights,
    custom,
    max_enum,
};

pub const ComponentType = enum(c_uint) {
    pub const upstream_prefix = "cgltf_component_type_";
    invalid,
    r_8,
    r_8u,
    r_16,
    r_16u,
    r_32u,
    r_32f,
    max_enum,
};

pub const Type = enum(c_uint) {
    pub const upstream_prefix = "cgltf_type_";
    invalid,
    scalar,
    vec2,
    vec3,
    vec4,
    mat2,
    mat3,
    mat4,
    max_enum,
};

pub const PrimitiveType = enum(c_uint) {
    pub const upstream_prefix = "cgltf_primitive_type_";
    invalid,
    points,
    lines,
    line_loop,
    line_strip,
    triangles,
    triangle_strip,
    triangle_fan,
    max_enum,
};

pub const AlphaMode = enum(c_uint) {
    pub const upstream_prefix = "cgltf_alpha_mode_";
    @"opaque",
    mask,
    blend,
    max_enum,
};

pub const AnimationPathType = enum(c_uint) {
    pub const upstream_prefix = "cgltf_animation_path_type_";
    invalid,
    translation,
    rotation,
    scale,
    weights,
    max_enum,
};

pub const InterpolationType = enum(c_uint) {
    pub const upstream_prefix = "cgltf_interpolation_type_";
    linear,
    step,
    cubic_spline,
    max_enum,
};

pub const CameraType = enum(c_uint) {
    pub const upstream_prefix = "cgltf_camera_type_";
    invalid,
    perspective,
    orthographic,
    max_enum,
};

pub const LightType = enum(c_uint) {
    pub const upstream_prefix = "cgltf_light_type_";
    invalid,
    directional,
    point,
    spot,
    max_enum,
};

pub const DataFreeMethod = enum(c_uint) {
    pub const upstream_prefix = "cgltf_data_free_method_";
    none,
    file_release,
    memory_free,
    max_enum,
};

/// `cgltf_extras`: raw extras JSON. `start_offset`/`end_offset` are
/// deprecated upstream; `data` is the null-terminated JSON text, or null.
pub const Extras = extern struct {
    start_offset: Size,
    end_offset: Size,
    data: ?[*:0]u8,
};

pub const Extension = extern struct {
    name: ?[*:0]u8,
    data: ?[*:0]u8,
};

/// `cgltf_buffer`: `data` is null until `loadBuffers` (or the caller) fills
/// it; `data_free_method` records who owns it.
pub const Buffer = extern struct {
    name: ?[*:0]u8,
    size: Size,
    uri: ?[*:0]u8,
    data: ?*anyopaque,
    data_free_method: DataFreeMethod,
    extras: Extras,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

pub const MeshoptCompressionMode = enum(c_uint) {
    pub const upstream_prefix = "cgltf_meshopt_compression_mode_";
    invalid,
    attributes,
    triangles,
    indices,
    max_enum,
};

pub const MeshoptCompressionFilter = enum(c_uint) {
    pub const upstream_prefix = "cgltf_meshopt_compression_filter_";
    none,
    octahedral,
    quaternion,
    exponential,
    max_enum,
};

/// `cgltf_meshopt_compression` (`EXT_meshopt_compression`): the compressed
/// region is `buffer[offset..offset+size]`, decoding to `count` elements of
/// `stride` bytes.
pub const MeshoptCompression = extern struct {
    buffer: ?*Buffer,
    offset: Size,
    size: Size,
    stride: Size,
    count: Size,
    mode: MeshoptCompressionMode,
    filter: MeshoptCompressionFilter,
};

/// `cgltf_buffer_view`: `data` overrides `buffer.data` when an extension
/// (meshopt compression) decoded this view out of line; `stride == 0` defers
/// to the accessor. A non-null `data` is released by `cgltf_free` through
/// `memory.free_func` (cgltf.h:1875), so it must come from the document's
/// own allocator.
pub const BufferView = extern struct {
    name: ?[*:0]u8,
    buffer: ?*Buffer,
    offset: Size,
    size: Size,
    stride: Size,
    type: BufferViewType,
    data: ?*anyopaque,
    has_meshopt_compression: Bool32,
    meshopt_compression: MeshoptCompression,
    extras: Extras,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

pub const AccessorSparse = extern struct {
    count: Size,
    indices_buffer_view: ?*BufferView,
    indices_byte_offset: Size,
    indices_component_type: ComponentType,
    values_buffer_view: ?*BufferView,
    values_byte_offset: Size,
};

/// `cgltf_accessor`: `buffer_view` is null for sparse-only accessors;
/// `min`/`max` are valid for the leading `numComponents(type)` entries when
/// the matching `has_*` flag is set.
pub const Accessor = extern struct {
    name: ?[*:0]u8,
    component_type: ComponentType,
    normalized: Bool32,
    type: Type,
    offset: Size,
    count: Size,
    stride: Size,
    buffer_view: ?*BufferView,
    has_min: Bool32,
    min: [16]Float,
    has_max: Bool32,
    max: [16]Float,
    is_sparse: Bool32,
    sparse: AccessorSparse,
    extras: Extras,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

/// `cgltf_attribute`: `index` is the numeric suffix (TEXCOORD_1 -> 1).
pub const Attribute = extern struct {
    name: ?[*:0]u8,
    type: AttributeType,
    index: Int,
    data: ?*Accessor,
};

pub const Image = extern struct {
    name: ?[*:0]u8,
    uri: ?[*:0]u8,
    buffer_view: ?*BufferView,
    mime_type: ?[*:0]u8,
    extras: Extras,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

/// GL filter constants, carried verbatim (NEAREST = 9728, ...); `undefined`
/// means the sampler omitted the field.
pub const FilterType = enum(c_uint) {
    pub const upstream_prefix = "cgltf_filter_type_";
    undefined = 0,
    nearest = 9728,
    linear = 9729,
    nearest_mipmap_nearest = 9984,
    linear_mipmap_nearest = 9985,
    nearest_mipmap_linear = 9986,
    linear_mipmap_linear = 9987,
};

/// GL wrap constants, carried verbatim (REPEAT = 10497, ...).
pub const WrapMode = enum(c_uint) {
    pub const upstream_prefix = "cgltf_wrap_mode_";
    clamp_to_edge = 33071,
    mirrored_repeat = 33648,
    repeat = 10497,
};

pub const Sampler = extern struct {
    name: ?[*:0]u8,
    mag_filter: FilterType,
    min_filter: FilterType,
    wrap_s: WrapMode,
    wrap_t: WrapMode,
    extras: Extras,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

/// `cgltf_texture`: `basisu_image`/`webp_image` are the extension sources
/// (`KHR_texture_basisu`, `EXT_texture_webp`), valid under their flags.
pub const Texture = extern struct {
    name: ?[*:0]u8,
    image: ?*Image,
    sampler: ?*Sampler,
    has_basisu: Bool32,
    basisu_image: ?*Image,
    has_webp: Bool32,
    webp_image: ?*Image,
    extras: Extras,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

/// `cgltf_texture_transform` (`KHR_texture_transform`).
pub const TextureTransform = extern struct {
    offset: [2]Float,
    rotation: Float,
    scale: [2]Float,
    has_texcoord: Bool32,
    texcoord: Int,
};

/// `cgltf_texture_view`: `scale` doubles as strength for occlusion.
pub const TextureView = extern struct {
    texture: ?*Texture,
    texcoord: Int,
    scale: Float,
    has_transform: Bool32,
    transform: TextureTransform,
};

pub const PbrMetallicRoughness = extern struct {
    base_color_texture: TextureView,
    metallic_roughness_texture: TextureView,
    base_color_factor: [4]Float,
    metallic_factor: Float,
    roughness_factor: Float,
};

pub const PbrSpecularGlossiness = extern struct {
    diffuse_texture: TextureView,
    specular_glossiness_texture: TextureView,
    diffuse_factor: [4]Float,
    specular_factor: [3]Float,
    glossiness_factor: Float,
};

pub const Clearcoat = extern struct {
    clearcoat_texture: TextureView,
    clearcoat_roughness_texture: TextureView,
    clearcoat_normal_texture: TextureView,
    clearcoat_factor: Float,
    clearcoat_roughness_factor: Float,
};

pub const Transmission = extern struct {
    transmission_texture: TextureView,
    transmission_factor: Float,
};

pub const Ior = extern struct {
    ior: Float,
};

pub const Specular = extern struct {
    specular_texture: TextureView,
    specular_color_texture: TextureView,
    specular_color_factor: [3]Float,
    specular_factor: Float,
};

pub const Volume = extern struct {
    thickness_texture: TextureView,
    thickness_factor: Float,
    attenuation_color: [3]Float,
    attenuation_distance: Float,
};

pub const Sheen = extern struct {
    sheen_color_texture: TextureView,
    sheen_color_factor: [3]Float,
    sheen_roughness_texture: TextureView,
    sheen_roughness_factor: Float,
};

pub const EmissiveStrength = extern struct {
    emissive_strength: Float,
};

pub const Iridescence = extern struct {
    iridescence_factor: Float,
    iridescence_texture: TextureView,
    iridescence_ior: Float,
    iridescence_thickness_min: Float,
    iridescence_thickness_max: Float,
    iridescence_thickness_texture: TextureView,
};

pub const DiffuseTransmission = extern struct {
    diffuse_transmission_texture: TextureView,
    diffuse_transmission_factor: Float,
    diffuse_transmission_color_factor: [3]Float,
    diffuse_transmission_color_texture: TextureView,
};

pub const Anisotropy = extern struct {
    anisotropy_strength: Float,
    anisotropy_rotation: Float,
    anisotropy_texture: TextureView,
};

pub const Dispersion = extern struct {
    dispersion: Float,
};

/// `cgltf_material`: each embedded extension block is valid only under its
/// `has_*` flag; the factors keep upstream's spec defaults either way.
pub const Material = extern struct {
    name: ?[*:0]u8,
    has_pbr_metallic_roughness: Bool32,
    has_pbr_specular_glossiness: Bool32,
    has_clearcoat: Bool32,
    has_transmission: Bool32,
    has_volume: Bool32,
    has_ior: Bool32,
    has_specular: Bool32,
    has_sheen: Bool32,
    has_emissive_strength: Bool32,
    has_iridescence: Bool32,
    has_diffuse_transmission: Bool32,
    has_anisotropy: Bool32,
    has_dispersion: Bool32,
    pbr_metallic_roughness: PbrMetallicRoughness,
    pbr_specular_glossiness: PbrSpecularGlossiness,
    clearcoat: Clearcoat,
    ior: Ior,
    specular: Specular,
    sheen: Sheen,
    transmission: Transmission,
    volume: Volume,
    emissive_strength: EmissiveStrength,
    iridescence: Iridescence,
    diffuse_transmission: DiffuseTransmission,
    anisotropy: Anisotropy,
    dispersion: Dispersion,
    normal_texture: TextureView,
    occlusion_texture: TextureView,
    emissive_texture: TextureView,
    emissive_factor: [3]Float,
    alpha_mode: AlphaMode,
    alpha_cutoff: Float,
    double_sided: Bool32,
    unlit: Bool32,
    extras: Extras,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

/// `cgltf_material_mapping` (`KHR_materials_variants`).
pub const MaterialMapping = extern struct {
    variant: Size,
    material: ?*Material,
    extras: Extras,
};

pub const MorphTarget = extern struct {
    attributes: ?[*]Attribute,
    attributes_count: Size,
};

/// `cgltf_draco_mesh_compression` (`KHR_draco_mesh_compression`): cgltf
/// parses the pointers but does not decode Draco data.
pub const DracoMeshCompression = extern struct {
    buffer_view: ?*BufferView,
    attributes: ?[*]Attribute,
    attributes_count: Size,
};

/// `cgltf_mesh_gpu_instancing` (`EXT_mesh_gpu_instancing`).
pub const MeshGpuInstancing = extern struct {
    attributes: ?[*]Attribute,
    attributes_count: Size,
};

/// `cgltf_primitive`: `indices` is null for non-indexed geometry, `material`
/// for the default material.
pub const Primitive = extern struct {
    type: PrimitiveType,
    indices: ?*Accessor,
    material: ?*Material,
    attributes: ?[*]Attribute,
    attributes_count: Size,
    targets: ?[*]MorphTarget,
    targets_count: Size,
    extras: Extras,
    has_draco_mesh_compression: Bool32,
    draco_mesh_compression: DracoMeshCompression,
    mappings: ?[*]MaterialMapping,
    mappings_count: Size,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

pub const Mesh = extern struct {
    name: ?[*:0]u8,
    primitives: ?[*]Primitive,
    primitives_count: Size,
    weights: ?[*]Float,
    weights_count: Size,
    target_names: ?[*]?[*:0]u8,
    target_names_count: Size,
    extras: Extras,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

/// `cgltf_skin`: `joints` entries are non-null node pointers.
pub const Skin = extern struct {
    name: ?[*:0]u8,
    joints: ?[*]*Node,
    joints_count: Size,
    skeleton: ?*Node,
    inverse_bind_matrices: ?*Accessor,
    extras: Extras,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

pub const CameraPerspective = extern struct {
    has_aspect_ratio: Bool32,
    aspect_ratio: Float,
    yfov: Float,
    has_zfar: Bool32,
    zfar: Float,
    znear: Float,
    extras: Extras,
};

pub const CameraOrthographic = extern struct {
    xmag: Float,
    ymag: Float,
    zfar: Float,
    znear: Float,
    extras: Extras,
};

/// The one union in the API, anonymous upstream: `type` selects which
/// member of `data` is meaningful.
pub const CameraData = extern union {
    perspective: CameraPerspective,
    orthographic: CameraOrthographic,
};

pub const Camera = extern struct {
    name: ?[*:0]u8,
    type: CameraType,
    data: CameraData,
    extras: Extras,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

/// `cgltf_light` (`KHR_lights_punctual`): `range == 0` means unlimited.
pub const Light = extern struct {
    name: ?[*:0]u8,
    color: [3]Float,
    intensity: Float,
    type: LightType,
    range: Float,
    spot_inner_cone_angle: Float,
    spot_outer_cone_angle: Float,
    extras: Extras,
};

/// `cgltf_node`: the self-referential scene graph node. TRS fields are
/// valid under their `has_*` flags; `matrix` under `has_matrix`.
pub const Node = extern struct {
    name: ?[*:0]u8,
    parent: ?*Node,
    children: ?[*]*Node,
    children_count: Size,
    skin: ?*Skin,
    mesh: ?*Mesh,
    camera: ?*Camera,
    light: ?*Light,
    weights: ?[*]Float,
    weights_count: Size,
    has_translation: Bool32,
    has_rotation: Bool32,
    has_scale: Bool32,
    has_matrix: Bool32,
    translation: [3]Float,
    rotation: [4]Float,
    scale: [3]Float,
    matrix: [16]Float,
    extras: Extras,
    has_mesh_gpu_instancing: Bool32,
    mesh_gpu_instancing: MeshGpuInstancing,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

pub const Scene = extern struct {
    name: ?[*:0]u8,
    nodes: ?[*]*Node,
    nodes_count: Size,
    extras: Extras,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

pub const AnimationSampler = extern struct {
    input: ?*Accessor,
    output: ?*Accessor,
    interpolation: InterpolationType,
    extras: Extras,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

pub const AnimationChannel = extern struct {
    sampler: ?*AnimationSampler,
    target_node: ?*Node,
    target_path: AnimationPathType,
    extras: Extras,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

pub const Animation = extern struct {
    name: ?[*:0]u8,
    samplers: ?[*]AnimationSampler,
    samplers_count: Size,
    channels: ?[*]AnimationChannel,
    channels_count: Size,
    extras: Extras,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

/// `cgltf_material_variant` (`KHR_materials_variants`).
pub const MaterialVariant = extern struct {
    name: ?[*:0]u8,
    extras: Extras,
};

pub const Asset = extern struct {
    copyright: ?[*:0]u8,
    generator: ?[*:0]u8,
    version: ?[*:0]u8,
    min_version: ?[*:0]u8,
    extras: Extras,
    extensions_count: Size,
    extensions: ?[*]Extension,
};

/// `cgltf_data`: the parsed document. Every array is owned by the document
/// and freed by `cgltf_free`; `json`/`bin` alias the input for a GLB.
pub const Data = extern struct {
    file_type: FileType,
    file_data: ?*anyopaque,
    asset: Asset,
    meshes: ?[*]Mesh,
    meshes_count: Size,
    materials: ?[*]Material,
    materials_count: Size,
    accessors: ?[*]Accessor,
    accessors_count: Size,
    buffer_views: ?[*]BufferView,
    buffer_views_count: Size,
    buffers: ?[*]Buffer,
    buffers_count: Size,
    images: ?[*]Image,
    images_count: Size,
    textures: ?[*]Texture,
    textures_count: Size,
    samplers: ?[*]Sampler,
    samplers_count: Size,
    skins: ?[*]Skin,
    skins_count: Size,
    cameras: ?[*]Camera,
    cameras_count: Size,
    lights: ?[*]Light,
    lights_count: Size,
    nodes: ?[*]Node,
    nodes_count: Size,
    scenes: ?[*]Scene,
    scenes_count: Size,
    scene: ?*Scene,
    animations: ?[*]Animation,
    animations_count: Size,
    variants: ?[*]MaterialVariant,
    variants_count: Size,
    extras: Extras,
    data_extensions_count: Size,
    data_extensions: ?[*]Extension,
    extensions_used: ?[*]?[*:0]u8,
    extensions_used_count: Size,
    extensions_required: ?[*]?[*:0]u8,
    extensions_required_count: Size,
    json: ?[*]const u8,
    json_size: Size,
    bin: ?*const anyopaque,
    bin_size: Size,
    memory: MemoryOptions,
    file: FileOptions,
};
