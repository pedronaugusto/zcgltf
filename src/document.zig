//! Idiomatic layer: document lifecycle — parse, load, validate, free — with
//! `cgltf_result` folded into a Zig error set.

const std = @import("std");
const c = @import("c.zig");
const t = c.types;

/// `Result` minus `success`, one error per failure enumerator.
pub const Error = error{
    DataTooShort,
    UnknownFormat,
    InvalidJson,
    InvalidGltf,
    InvalidOptions,
    FileNotFound,
    IoError,
    OutOfMemory,
    LegacyGltf,
};

/// The `Result` -> `Error` fold every wrapper goes through.
pub fn check(result: t.Result) Error!void {
    return switch (result) {
        .success => {},
        .data_too_short => error.DataTooShort,
        .unknown_format => error.UnknownFormat,
        .invalid_json => error.InvalidJson,
        .invalid_gltf => error.InvalidGltf,
        .invalid_options => error.InvalidOptions,
        .file_not_found => error.FileNotFound,
        .io_error => error.IoError,
        .out_of_memory => error.OutOfMemory,
        .legacy_gltf => error.LegacyGltf,
        // The sentinel, which no upstream return site produces. Mapped to an
        // error rather than `unreachable` so that if a future upstream ever
        // does return it, the caller sees a failure instead of undefined
        // behaviour in release builds.
        .max_enum => error.InvalidGltf,
    };
}

/// Parses an in-memory glTF or GLB (`options.type = .invalid` auto-detects).
/// The document keeps pointers INTO `bytes`, which must outlive it; free
/// with `free`.
pub fn parse(options: *const t.Options, bytes: []const u8) Error!*t.Data {
    var out: ?*t.Data = null;
    try check(c.document.cgltf_parse(options, bytes.ptr, bytes.len, &out));
    return out.?;
}

/// Reads and parses a file through `options.file` — fopen/fread when null;
/// `file.fileOptions()` swaps in the Zig-backed reader.
pub fn parseFile(options: *const t.Options, path: [:0]const u8) Error!*t.Data {
    var out: ?*t.Data = null;
    try check(c.document.cgltf_parse_file(options, path.ptr, &out));
    return out.?;
}

/// Resolves every buffer: GLB bin chunk, base64 data URIs, and files
/// relative to `gltf_path` (null forbids file URIs). Fills each
/// `Buffer.data`.
pub fn loadBuffers(options: *const t.Options, data: *t.Data, gltf_path: ?[:0]const u8) Error!void {
    try check(c.document.cgltf_load_buffers(options, data, if (gltf_path) |p| p.ptr else null));
}

/// Decodes base64 into `size` bytes allocated through `options.memory`; the
/// caller owns the result and releases it through that same allocator.
pub fn loadBufferBase64(options: *const t.Options, size: usize, base64: [:0]const u8) Error![]u8 {
    var out: ?*anyopaque = null;
    try check(c.document.cgltf_load_buffer_base64(options, size, base64.ptr, &out));
    return @as([*]u8, @ptrCast(out.?))[0..size];
}

/// Decodes JSON escape sequences in place and returns the decoded prefix
/// (never longer than the input).
pub fn decodeString(string: [:0]u8) []u8 {
    return string[0..c.document.cgltf_decode_string(string.ptr)];
}

/// Decodes percent-encoding in place and returns the decoded prefix.
pub fn decodeUri(uri: [:0]u8) []u8 {
    return uri[0..c.document.cgltf_decode_uri(uri.ptr)];
}

/// Structural validation beyond what parsing enforces: accessor bounds
/// against buffer views, sparse indices, required attributes.
pub fn validate(data: *t.Data) Error!void {
    try check(c.document.cgltf_validate(data));
}

/// Frees the document and everything it owns, through the memory and file
/// options it was parsed with.
pub fn free(data: *t.Data) void {
    c.document.cgltf_free(data);
}

const test_asset_path = "tests/data/triangle.gltf";

test parse {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        test_asset_path,
        std.testing.allocator,
        .limited(1 << 20),
    );
    defer std.testing.allocator.free(bytes);

    var options = std.mem.zeroes(t.Options);
    const data = try parse(&options, bytes);
    defer free(data);
    try loadBuffers(&options, data, test_asset_path);
    try validate(data);

    try std.testing.expectEqual(@as(usize, 1), data.meshes_count);
    try std.testing.expectEqual(@as(usize, 2), data.accessors_count);
    try std.testing.expectEqual(@as(usize, 1), data.buffers_count);
    try std.testing.expect(data.buffers.?[0].data != null);
}

test "parse failures map to the error set" {
    var options = std.mem.zeroes(t.Options);
    // Auto-detection treats anything without the GLB magic as JSON text, so
    // non-glTF prose fails as JSON rather than as an unknown format.
    try std.testing.expectError(error.InvalidJson, parse(&options, "not gltf at all"));
    try std.testing.expectError(error.DataTooShort, parse(&options, ""));
    try std.testing.expectError(error.FileNotFound, parseFile(&options, "tests/data/no_such_file.gltf"));
}

test decodeString {
    var buf = "a\\nb".*;
    try std.testing.expectEqualStrings("a\nb", decodeString(buf[0..4 :0]));
    var uri = "a%20b".*;
    try std.testing.expectEqualStrings("a b", decodeUri(uri[0..5 :0]));
}
