//! `EXT_meshopt_compression` end to end, both packages in one process:
//! zmeshopt encodes a mesh, this program writes the glTF JSON a compressed
//! asset carries, zcgltf parses it, zmeshopt decodes what cgltf's metadata
//! points at, and cgltf's accessor API reads the decoded bytes — the
//! three-step contract README's "Pairing with zmeshopt" documents, through
//! every `mode` the extension defines and one of its filters.
//!
//! The asset is constructed here rather than checked in, so the values read
//! back can be compared against the exact values encoded.

const std = @import("std");
const zcgltf = @import("zcgltf");
const zmeshopt = @import("zmeshopt");

const positions: [3][3]f32 = .{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 } };
const triangle: [3]u32 = .{ 0, 1, 2 };
const outline: [4]u32 = .{ 0, 1, 2, 0 };

// Buffer 0 is the fallback: no uri, so `loadBuffers` leaves it unloaded and
// every byte read must come through the decoded views. Buffers 1 to 3 hold
// the compressed streams as data URIs: the positions (ATTRIBUTES, through
// the exponential filter), the triangle (TRIANGLES) and its outline as a
// line strip (INDICES).
const gltf_template =
    \\{{
    \\  "asset": {{ "version": "2.0" }},
    \\  "extensionsUsed": ["EXT_meshopt_compression"],
    \\  "extensionsRequired": ["EXT_meshopt_compression"],
    \\  "meshes": [{{ "primitives": [
    \\    {{ "attributes": {{ "POSITION": 0 }}, "indices": 1 }},
    \\    {{ "attributes": {{ "POSITION": 0 }}, "indices": 2, "mode": 3 }}
    \\  ] }}],
    \\  "accessors": [
    \\    {{ "bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3" }},
    \\    {{ "bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR" }},
    \\    {{ "bufferView": 2, "componentType": 5123, "count": 4, "type": "SCALAR" }}
    \\  ],
    \\  "bufferViews": [
    \\    {{ "buffer": 0, "byteOffset": 0, "byteLength": 36, "byteStride": 12, "extensions": {{
    \\      "EXT_meshopt_compression": {{ "buffer": 1, "byteLength": {d}, "byteStride": 12, "count": 3, "mode": "ATTRIBUTES", "filter": "EXPONENTIAL" }} }} }},
    \\    {{ "buffer": 0, "byteOffset": 36, "byteLength": 6, "extensions": {{
    \\      "EXT_meshopt_compression": {{ "buffer": 2, "byteLength": {d}, "byteStride": 2, "count": 3, "mode": "TRIANGLES" }} }} }},
    \\    {{ "buffer": 0, "byteOffset": 42, "byteLength": 8, "extensions": {{
    \\      "EXT_meshopt_compression": {{ "buffer": 3, "byteLength": {d}, "byteStride": 2, "count": 4, "mode": "INDICES" }} }} }}
    \\  ],
    \\  "buffers": [
    \\    {{ "byteLength": 50 }},
    \\    {{ "byteLength": {d}, "uri": "data:application/octet-stream;base64,{s}" }},
    \\    {{ "byteLength": {d}, "uri": "data:application/octet-stream;base64,{s}" }},
    \\    {{ "byteLength": {d}, "uri": "data:application/octet-stream;base64,{s}" }}
    \\  ]
    \\}}
;

/// Allocates a decoded view's bytes through the document's own memory
/// options, because `free` releases every non-null `view.data` through
/// `memory.free_func` — a foreign allocator here would be a mismatched free.
fn allocView(data: *zcgltf.Data, comptime T: type, count: usize) ![]T {
    const raw = data.memory.alloc_func.?(data.memory.user_data, count * @sizeOf(T)) orelse
        return error.OutOfMemory;
    return @as([*]T, @ptrCast(@alignCast(raw)))[0..count];
}

fn compressed(view: *const zcgltf.BufferView) []const u8 {
    const mc = &view.meshopt_compression;
    return @as([*]const u8, @ptrCast(mc.buffer.?.data.?))[mc.offset..][0..mc.size];
}

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .{};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    // 1. Encode with zmeshopt. The positions pass through the exponential
    //    filter first; 16 mantissa bits keep 0 and 1 exact, so the values
    //    read back can be compared bit for bit. Vertex codec format v0 is
    //    the older of the two the decoder accepts (`vertexcodec.cpp`,
    //    `kDecodeVertexVersion`); the round trip does not depend on which.
    var filtered: [3][3]u32 = undefined;
    zmeshopt.encodeFilterExp([3]u32, &filtered, 16, @as([*]const f32, @ptrCast(&positions))[0 .. 3 * 3], .separate);
    const vbuf = try gpa.alloc(u8, zmeshopt.encodeVertexBufferBound([3]u32, filtered.len));
    defer gpa.free(vbuf);
    const encoded_v = try zmeshopt.encodeVertexBufferLevel([3]u32, vbuf, &filtered, 2, .v0);

    const ibuf = try gpa.alloc(u8, zmeshopt.encodeIndexBufferBound(triangle.len, positions.len));
    defer gpa.free(ibuf);
    const encoded_i = try zmeshopt.encodeIndexBuffer(ibuf, &triangle);

    const sbuf = try gpa.alloc(u8, zmeshopt.encodeIndexSequenceBound(outline.len, positions.len));
    defer gpa.free(sbuf);
    const encoded_s = try zmeshopt.encodeIndexSequence(sbuf, &outline);

    // 2. Write the JSON of a compressed asset around the three streams.
    const enc = std.base64.standard.Encoder;
    const v64 = try gpa.alloc(u8, enc.calcSize(encoded_v.len));
    defer gpa.free(v64);
    _ = enc.encode(v64, encoded_v);
    const i64_ = try gpa.alloc(u8, enc.calcSize(encoded_i.len));
    defer gpa.free(i64_);
    _ = enc.encode(i64_, encoded_i);
    const s64 = try gpa.alloc(u8, enc.calcSize(encoded_s.len));
    defer gpa.free(s64);
    _ = enc.encode(s64, encoded_s);

    const json = try std.fmt.allocPrint(gpa, gltf_template, .{
        encoded_v.len, encoded_i.len, encoded_s.len,
        encoded_v.len, v64,           encoded_i.len,
        i64_,          encoded_s.len, s64,
    });
    defer gpa.free(json);

    // 3. Parse with zcgltf. The fallback buffer has no uri, so it stays
    //    unloaded; the compressed buffers load from their data URIs.
    var options = std.mem.zeroes(zcgltf.Options);
    options.memory = zcgltf.memoryOptions(&gpa);
    const data = try zcgltf.parse(&options, json);
    defer zcgltf.free(data);
    try zcgltf.loadBuffers(&options, data, null);
    try zcgltf.validate(data);

    const views = data.buffer_views.?;
    if (views[0].has_meshopt_compression == 0) return error.MetadataLost;
    if (views[0].meshopt_compression.mode != .attributes) return error.MetadataLost;
    if (views[0].meshopt_compression.filter != .exponential) return error.MetadataLost;
    if (views[0].meshopt_compression.stride != 12) return error.MetadataLost;
    if (views[1].meshopt_compression.mode != .triangles) return error.MetadataLost;
    if (views[2].meshopt_compression.mode != .indices) return error.MetadataLost;

    // Before decoding, the compressed views expose no bytes at all.
    if (zcgltf.bufferViewData(&views[0]) != null) return error.FallbackLoaded;

    // 4. Decode each view's compressed region with zmeshopt and hand the
    //    result to cgltf by writing `view.data`. Each pointer is assigned
    //    before its decode, so `free` owns it on every path.
    const verts = try allocView(data, [3]u32, views[0].meshopt_compression.count);
    views[0].data = verts.ptr;
    try zmeshopt.decodeVertexBuffer([3]u32, verts, compressed(&views[0]));
    zmeshopt.decodeFilterExp([3]u32, verts); // in place: each u32 becomes the f32 it encoded

    const inds = try allocView(data, u16, views[1].meshopt_compression.count);
    views[1].data = inds.ptr;
    try zmeshopt.decodeIndexBuffer(u16, inds, compressed(&views[1]));

    const strip = try allocView(data, u16, views[2].meshopt_compression.count);
    views[2].data = strip.ptr;
    try zmeshopt.decodeIndexSequence(u16, strip, compressed(&views[2]));

    // 5. Read back through cgltf's accessor API, which prefers `view.data`.
    const accessors = data.accessors.?;
    var v: [3]f32 = undefined;
    for (positions, 0..) |expected, i| {
        if (!zcgltf.readFloat(&accessors[0], i, &v)) return error.ReadFailed;
        if (!std.mem.eql(f32, &v, &expected)) return error.WrongVertex;
    }
    var read_triangle: [3]u32 = undefined;
    for (zcgltf.unpackIndices(&accessors[1], u32, &read_triangle), triangle) |got, expected| {
        if (got != expected) return error.WrongIndex;
    }
    var read_outline: [4]u32 = undefined;
    for (zcgltf.unpackIndices(&accessors[2], u32, &read_outline), outline) |got, expected| {
        if (got != expected) return error.WrongIndex;
    }

    std.debug.print(
        "interop ok: {d} filtered vertices + {d} triangle indices + {d} strip indices " ++
            "round-tripped through EXT_meshopt_compression ({d}+{d}+{d} compressed bytes)\n",
        .{ positions.len, triangle.len, outline.len, encoded_v.len, encoded_i.len, encoded_s.len },
    );
}
