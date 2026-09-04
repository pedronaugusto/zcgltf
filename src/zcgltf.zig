//! zcgltf — complete Zig bindings for cgltf v1.15.
//!
//! Three layers, thinnest first:
//!
//!   * `c` — the raw externs, one module per header region, mirroring the
//!     vendored `cgltf.h` and `cgltf_write.h` exactly; `src/abi_check.zig`'s
//!     reverse sweep fails the build if a header function is ever missing.
//!   * The idiomatic layer — error-union and slice wrappers in the per-area
//!     files (`src/document.zig`, `src/access.zig`, …), re-exported flat
//!     below, plus the Zig-allocator adapter (`src/memory.zig`) and the
//!     Zig-file-backed reader (`src/file.zig`).
//!   * The type re-exports — the document model under its Zig names, so a
//!     caller never has to spell `c.types.…`.

const std = @import("std");

/// How the C was built (`sanitize_c`) plus the package version — the build
/// options module, re-exported so a consumer can branch on it without
/// plumbing a second module import.
pub const options = @import("zcgltf_options");

pub const c = @import("c.zig");

const document_area = @import("document.zig");
const access_area = @import("access.zig");
const indices_area = @import("indices.zig");
const memory_area = @import("memory.zig");
const file_area = @import("file.zig");
const writer_area = @import("writer.zig");

// Scalar typedefs.
pub const Size = c.types.Size;
pub const SSize = c.types.SSize;
pub const Float = c.types.Float;
pub const Int = c.types.Int;
pub const Uint = c.types.Uint;
pub const Bool32 = c.types.Bool32;

// Enums.
pub const FileType = c.types.FileType;
pub const Result = c.types.Result;
pub const BufferViewType = c.types.BufferViewType;
pub const AttributeType = c.types.AttributeType;
pub const ComponentType = c.types.ComponentType;
pub const Type = c.types.Type;
pub const PrimitiveType = c.types.PrimitiveType;
pub const AlphaMode = c.types.AlphaMode;
pub const AnimationPathType = c.types.AnimationPathType;
pub const InterpolationType = c.types.InterpolationType;
pub const CameraType = c.types.CameraType;
pub const LightType = c.types.LightType;
pub const DataFreeMethod = c.types.DataFreeMethod;
pub const MeshoptCompressionMode = c.types.MeshoptCompressionMode;
pub const MeshoptCompressionFilter = c.types.MeshoptCompressionFilter;
pub const FilterType = c.types.FilterType;
pub const WrapMode = c.types.WrapMode;

// Option and document structs.
pub const MemoryOptions = c.types.MemoryOptions;
pub const FileOptions = c.types.FileOptions;
pub const Options = c.types.Options;
pub const Extras = c.types.Extras;
pub const Extension = c.types.Extension;
pub const Buffer = c.types.Buffer;
pub const MeshoptCompression = c.types.MeshoptCompression;
pub const BufferView = c.types.BufferView;
pub const AccessorSparse = c.types.AccessorSparse;
pub const Accessor = c.types.Accessor;
pub const Attribute = c.types.Attribute;
pub const Image = c.types.Image;
pub const Sampler = c.types.Sampler;
pub const Texture = c.types.Texture;
pub const TextureTransform = c.types.TextureTransform;
pub const TextureView = c.types.TextureView;
pub const PbrMetallicRoughness = c.types.PbrMetallicRoughness;
pub const PbrSpecularGlossiness = c.types.PbrSpecularGlossiness;
pub const Clearcoat = c.types.Clearcoat;
pub const Transmission = c.types.Transmission;
pub const Ior = c.types.Ior;
pub const Specular = c.types.Specular;
pub const Volume = c.types.Volume;
pub const Sheen = c.types.Sheen;
pub const EmissiveStrength = c.types.EmissiveStrength;
pub const Iridescence = c.types.Iridescence;
pub const DiffuseTransmission = c.types.DiffuseTransmission;
pub const Anisotropy = c.types.Anisotropy;
pub const Dispersion = c.types.Dispersion;
pub const Material = c.types.Material;
pub const MaterialMapping = c.types.MaterialMapping;
pub const MorphTarget = c.types.MorphTarget;
pub const DracoMeshCompression = c.types.DracoMeshCompression;
pub const MeshGpuInstancing = c.types.MeshGpuInstancing;
pub const Primitive = c.types.Primitive;
pub const Mesh = c.types.Mesh;
pub const Skin = c.types.Skin;
pub const CameraPerspective = c.types.CameraPerspective;
pub const CameraOrthographic = c.types.CameraOrthographic;
pub const CameraData = c.types.CameraData;
pub const Camera = c.types.Camera;
pub const Light = c.types.Light;
pub const Node = c.types.Node;
pub const Scene = c.types.Scene;
pub const AnimationSampler = c.types.AnimationSampler;
pub const AnimationChannel = c.types.AnimationChannel;
pub const Animation = c.types.Animation;
pub const MaterialVariant = c.types.MaterialVariant;
pub const Asset = c.types.Asset;
pub const Data = c.types.Data;

// Document lifecycle.
pub const Error = document_area.Error;
pub const check = document_area.check;
pub const parse = document_area.parse;
pub const parseFile = document_area.parseFile;
pub const loadBuffers = document_area.loadBuffers;
pub const loadBufferBase64 = document_area.loadBufferBase64;
pub const decodeString = document_area.decodeString;
pub const decodeUri = document_area.decodeUri;
pub const validate = document_area.validate;
pub const free = document_area.free;

// Reading parsed data.
pub const nodeTransformLocal = access_area.nodeTransformLocal;
pub const nodeTransformWorld = access_area.nodeTransformWorld;
pub const bufferViewData = access_area.bufferViewData;
pub const findAccessor = access_area.findAccessor;
pub const readFloat = access_area.readFloat;
pub const readUint = access_area.readUint;
pub const readIndex = access_area.readIndex;
pub const numComponents = access_area.numComponents;
pub const componentSize = access_area.componentSize;
pub const calcSize = access_area.calcSize;
pub const unpackFloatsCount = access_area.unpackFloatsCount;
pub const unpackFloats = access_area.unpackFloats;
pub const unpackIndicesCount = access_area.unpackIndicesCount;
pub const unpackIndices = access_area.unpackIndices;

// Object-to-index lookup.
pub const indexOf = indices_area.indexOf;
pub const animationIndexOf = indices_area.animationIndexOf;

// Allocation and file I/O adapters.
pub const memoryOptions = memory_area.memoryOptions;
pub const freeThrough = memory_area.freeThrough;
pub const fileOptions = file_area.fileOptions;

// The writer.
pub const writeFile = writer_area.writeFile;
pub const writeAlloc = writer_area.writeAlloc;

/// The package version, from `build.zig.zon` — the version's one home —
/// carried through the `zcgltf_options` module by `build.zig`.
pub fn version() []const u8 {
    return options.version;
}

test version {
    // A malformed version here means build.zig.zon's is malformed: this is
    // the same string, injected at build time.
    const v = version();
    var it = std.mem.splitScalar(u8, v, '.');
    var parts: usize = 0;
    while (it.next()) |part| : (parts += 1) {
        _ = try std.fmt.parseInt(u32, part, 10);
    }
    try std.testing.expectEqual(@as(usize, 3), parts);
}

test {
    _ = @import("abi_check.zig");
    _ = document_area;
    _ = access_area;
    _ = indices_area;
    _ = memory_area;
    _ = file_area;
    _ = writer_area;
}
