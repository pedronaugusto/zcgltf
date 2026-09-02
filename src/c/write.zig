//! Externs: the glTF writer (`cgltf_write.h`).

const t = @import("types.zig");

/// Writes the document to `path` through `options.file`; `.type = .glb`
/// emits JSON and the bin chunk in one container.
pub extern fn cgltf_write_file(options: *const t.Options, path: [*:0]const u8, data: *const t.Data) t.Result;

/// Serializes JSON into `buffer` (null-terminated) and returns the byte
/// count INCLUDING the terminator; with `buffer == null` returns the size
/// needed. Buffer data itself is not written — only structure.
pub extern fn cgltf_write(options: *const t.Options, buffer: ?[*]u8, size: t.Size, data: *const t.Data) t.Size;
