//! Idiomatic layer: routing cgltf's allocations through a
//! `std.mem.Allocator`.
//!
//! The C hooks hand the free callback a bare pointer, and a Zig allocator
//! needs the allocation's length back — so the adapter prefixes every
//! allocation with a 16-byte header holding the total size. 16 bytes keeps
//! the pointer cgltf sees aligned the way malloc would align it.
//!
//! Unlike a global-hook design, cgltf's hooks live in `Options`, so the
//! adapter is per-call and two documents can use two allocators.

const std = @import("std");
const t = @import("c.zig").types;

/// A `MemoryOptions` backed by `allocator`. The POINTER is captured as
/// `user_data`, so it must outlive every use of these options — including
/// the final `free` of any document parsed with them.
pub fn memoryOptions(allocator: *const std.mem.Allocator) t.MemoryOptions {
    return .{
        .alloc_func = zigAlloc,
        .free_func = zigFree,
        .user_data = @ptrCast(@constCast(allocator)),
    };
}

const header_size = 16;
const alignment = std.mem.Alignment.@"16";

comptime {
    // The header must not lower the alignment of what follows it.
    std.debug.assert(header_size % alignment.toByteUnits() == 0);
    std.debug.assert(header_size >= @sizeOf(usize));
}

fn zigAlloc(user: ?*anyopaque, size: t.Size) callconv(.c) ?*anyopaque {
    const allocator: *const std.mem.Allocator = @ptrCast(@alignCast(user.?));
    const total = std.math.add(usize, size, header_size) catch return null;
    const memory = allocator.alignedAlloc(u8, alignment, total) catch return null;
    @as(*usize, @ptrCast(memory.ptr)).* = total;
    return memory.ptr + header_size;
}

fn zigFree(user: ?*anyopaque, ptr: ?*anyopaque) callconv(.c) void {
    const p = ptr orelse return;
    const allocator: *const std.mem.Allocator = @ptrCast(@alignCast(user.?));
    const base: [*]align(alignment.toByteUnits()) u8 = @alignCast(@as([*]u8, @ptrCast(p)) - header_size);
    const total = @as(*const usize, @ptrCast(base)).*;
    allocator.free(base[0..total]);
}

/// Releases a block the C layer allocated through `memory` — the base64
/// buffer from `loadBufferBase64`, or any pointer cgltf hands back. Routes
/// to the options' `free_func`, else `std.c.free`. The ONLY correct release
/// when the options came from `memoryOptions`: the pointer cgltf sees sits
/// past a 16-byte header, so `std.mem.Allocator.free` would be given the
/// wrong base and the wrong length.
pub fn freeThrough(memory: *const t.MemoryOptions, ptr: ?*anyopaque) void {
    if (memory.free_func) |f| return f(memory.user_data, ptr);
    std.c.free(ptr);
}

const document = @import("document.zig");

test memoryOptions {
    // std.testing.allocator fails the test on any leak, so parse + free
    // through the adapter is also the balance proof.
    var options = std.mem.zeroes(t.Options);
    options.memory = memoryOptions(&std.testing.allocator);

    const path = "tests/data/triangle.gltf";
    const data = try document.parseFile(&options, path);
    defer document.free(data);
    try document.loadBuffers(&options, data, path);
    try document.validate(data);
    try std.testing.expectEqual(@as(usize, 2), data.accessors_count);
}

test freeThrough {
    // The base64 buffer comes back past the adapter's header, so the only
    // correct release is through the options. `std.testing.allocator` fails
    // the test on a leak or a bad free, which is what proves it.
    var options = std.mem.zeroes(t.Options);
    options.memory = memoryOptions(&std.testing.allocator);

    // "zcgltf" in base64, decoded into its 6 bytes.
    const decoded = try document.loadBufferBase64(&options, 6, "emNnbHRm");
    try std.testing.expectEqualStrings("zcgltf", decoded);
    freeThrough(&options.memory, decoded.ptr);

    // With no hooks installed the same call routes to cgltf's own
    // allocator, and `freeThrough` must reach `std.c.free` instead.
    var plain = std.mem.zeroes(t.Options);
    const c_owned = try document.loadBufferBase64(&plain, 6, "emNnbHRm");
    try std.testing.expectEqualStrings("zcgltf", c_owned);
    freeThrough(&plain.memory, c_owned.ptr);
}
