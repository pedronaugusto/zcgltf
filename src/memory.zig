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
