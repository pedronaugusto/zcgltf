//! Externs: document lifecycle — parse, load, validate, free.

const t = @import("types.zig");

/// Parses an in-memory glTF or GLB. `out_data` receives a document owned by
/// the parser; free it with `cgltf_free`. The document keeps pointers INTO
/// `data`, which must outlive it.
pub extern fn cgltf_parse(options: *const t.Options, data: *const anyopaque, size: t.Size, out_data: *?*t.Data) t.Result;

/// Reads and parses a file through `options.file` (fopen/fread when null).
pub extern fn cgltf_parse_file(options: *const t.Options, path: [*:0]const u8, out_data: *?*t.Data) t.Result;

/// Resolves every buffer: GLB bin chunk, base64 data URIs, and files
/// relative to `gltf_path`. Fills each `Buffer.data` and its free method.
pub extern fn cgltf_load_buffers(options: *const t.Options, data: *t.Data, gltf_path: ?[*:0]const u8) t.Result;

/// Decodes base64 into memory allocated via `options.memory`; `size` is the
/// decoded byte count the caller expects.
pub extern fn cgltf_load_buffer_base64(options: *const t.Options, size: t.Size, base64: [*:0]const u8, out_data: *?*anyopaque) t.Result;

/// Decodes JSON escape sequences in place; returns the new length.
pub extern fn cgltf_decode_string(string: [*:0]u8) t.Size;

/// Decodes percent-encoding in place; returns the new length.
pub extern fn cgltf_decode_uri(uri: [*:0]u8) t.Size;

/// Structural validation beyond what parsing enforces: accessor bounds
/// against buffer views, sparse indices, required attributes.
pub extern fn cgltf_validate(data: *t.Data) t.Result;

/// Frees the document and everything it owns, through the memory and file
/// options it was parsed with. Null is a no-op.
pub extern fn cgltf_free(data: ?*t.Data) void;
