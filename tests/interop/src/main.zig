//! `EXT_meshopt_compression` end to end, both packages in one process:
//! zmeshopt encodes a mesh, this program writes the glTF JSON a compressed
//! asset carries, zcgltf parses it, zmeshopt decodes what cgltf's metadata
//! points at, and cgltf's accessor API reads the decoded bytes — the
//! three-step contract README's "Pairing with zmeshopt" documents.
//!
//! The asset is constructed here rather than checked in, so the values read
//! back can be compared against the exact values encoded.

const std = @import("std");
const zcgltf = @import("zcgltf");
const zmeshopt = @import("zmeshopt");

const positions: [3][3]f32 = .{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 } };
const indices: [3]u32 = .{ 0, 1, 2 };

// Buffer 0 is the fallback: no uri, so `loadBuffers` leaves it unloaded and
// every byte read must come through the decoded views. Buffers 1 and 2 hold
// the compressed streams as data URIs.
const gltf_template =
    \\{{
    \\  "asset": {{ "version": "2.0" }},
    \\  "extensionsUsed": ["EXT_meshopt_compression"],
    \\  "extensionsRequired": ["EXT_meshopt_compression"],
    \\  "meshes": [{{ "primitives": [{{ "attributes": {{ "POSITION": 0 }}, "indices": 1 }}] }}],
    \\  "accessors": [
    \\    {{ "bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3" }},
    \\    {{ "bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR" }}
    \\  ],
    \\  "bufferViews": [
    \\    {{ "buffer": 0, "byteOffset": 0, "byteLength": 36, "byteStride": 12, "extensions": {{
    \\      "EXT_meshopt_compression": {{ "buffer": 1, "byteLength": {d}, "byteStride": 12, "count": 3, "mode": "ATTRIBUTES" }} }} }},
    \\    {{ "buffer": 0, "byteOffset": 36, "byteLength": 6, "extensions": {{
    \\      "EXT_meshopt_compression": {{ "buffer": 2, "byteLength": {d}, "byteStride": 2, "count": 3, "mode": "TRIANGLES" }} }} }}
    \\  ],
    \\  "buffers": [
    \\    {{ "byteLength": 42 }},
    \\    {{ "byteLength": {d}, "uri": "data:application/octet-stream;base64,{s}" }},
    \\    {{ "byteLength": {d}, "uri": "data:application/octet-stream;base64,{s}" }}
    \\  ]
    \\}}
;

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .{};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    // 1. Encode with zmeshopt. Vertex codec format v0 is what shipping
    //    `EXT_meshopt_compression` assets carry (gltfpack targets the
    //    widest decoder range), so that is what goes in the asset.
    const vbuf = try gpa.alloc(u8, zmeshopt.encodeVertexBufferBound([3]f32, positions.len));
    defer gpa.free(vbuf);
    const encoded_v = try zmeshopt.encodeVertexBufferLevel([3]f32, vbuf, &positions, 2, .v0);

    const ibuf = try gpa.alloc(u8, zmeshopt.encodeIndexBufferBound(indices.len, positions.len));
    defer gpa.free(ibuf);
    const encoded_i = try zmeshopt.encodeIndexBuffer(ibuf, &indices);

    // 2. Write the JSON of a compressed asset around the two streams.
    const enc = std.base64.standard.Encoder;
    const v64 = try gpa.alloc(u8, enc.calcSize(encoded_v.len));
    defer gpa.free(v64);
    _ = enc.encode(v64, encoded_v);
    const i64_ = try gpa.alloc(u8, enc.calcSize(encoded_i.len));
    defer gpa.free(i64_);
    _ = enc.encode(i64_, encoded_i);

    const json = try std.fmt.allocPrint(gpa, gltf_template, .{
        encoded_v.len, encoded_i.len,
        encoded_v.len, v64,
        encoded_i.len, i64_,
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
    if (views[0].meshopt_compression.stride != 12) return error.MetadataLost;
    if (views[1].meshopt_compression.mode != .triangles) return error.MetadataLost;

    // Before decoding, the compressed views expose no bytes at all.
    if (zcgltf.bufferViewData(&views[0]) != null) return error.FallbackLoaded;

    // 4. Decode each view's compressed region with zmeshopt and hand the
    //    result to cgltf by writing `view.data`. Ownership transfers with
    //    the pointer — `free` releases every non-null `view.data` through
    //    `memory.free_func` — so the decoded bytes are allocated through
    //    the document's own memory options, never a foreign allocator.
    const vc = &views[0].meshopt_compression;
    const vsrc = @as([*]const u8, @ptrCast(vc.buffer.?.data.?))[vc.offset..][0..vc.size];
    const vraw = data.memory.alloc_func.?(data.memory.user_data, vc.count * vc.stride) orelse
        return error.OutOfMemory;
    const verts = @as([*][3]f32, @ptrCast(@alignCast(vraw)))[0..vc.count];
    views[0].data = verts.ptr; // assigned before decoding, so `free` owns it on every path
    try zmeshopt.decodeVertexBuffer([3]f32, verts, vsrc);

    const ic = &views[1].meshopt_compression;
    const isrc = @as([*]const u8, @ptrCast(ic.buffer.?.data.?))[ic.offset..][0..ic.size];
    const iraw = data.memory.alloc_func.?(data.memory.user_data, ic.count * ic.stride) orelse
        return error.OutOfMemory;
    const inds = @as([*]u16, @ptrCast(@alignCast(iraw)))[0..ic.count];
    views[1].data = inds.ptr;
    try zmeshopt.decodeIndexBuffer(u16, inds, isrc);

    // 5. Read back through cgltf's accessor API, which prefers `view.data`.
    const accessors = data.accessors.?;
    var v: [3]f32 = undefined;
    for (positions, 0..) |expected, i| {
        if (!zcgltf.readFloat(&accessors[0], i, &v)) return error.ReadFailed;
        if (!std.mem.eql(f32, &v, &expected)) return error.WrongVertex;
    }
    var read_indices: [3]u32 = undefined;
    for (zcgltf.unpackIndices(&accessors[1], u32, &read_indices), indices) |got, expected| {
        if (got != expected) return error.WrongIndex;
    }

    std.debug.print(
        "interop ok: {d} vertices + {d} indices round-tripped through " ++
            "EXT_meshopt_compression ({d}+{d} compressed bytes)\n",
        .{ positions.len, indices.len, encoded_v.len, encoded_i.len },
    );
}
