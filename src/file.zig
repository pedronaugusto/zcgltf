//! Idiomatic layer: a `FileOptions` whose reader is `std.Io` instead of
//! fopen/fread. That closes both portability holes in upstream's default
//! reader on Windows (documented in UPSTREAM.md): paths beyond the ANSI
//! code page (std converts WTF-8 to UTF-16 for the OS call, fopen does
//! not), and files over 2 GiB on non-MSVC toolchains (upstream sizes them
//! through long-returning ftell; std sizes are 64-bit everywhere).

const std = @import("std");
const t = @import("c.zig").types;

/// A `FileOptions` backed by `io`. The POINTER is captured as `user_data`,
/// so it must outlive every use — including the final `free` of any
/// document parsed with these options. Relative paths resolve against the
/// current working directory, exactly like the fopen default; allocation
/// still goes through the `MemoryOptions` alongside, so a document parsed
/// with this reader frees normally.
pub fn fileOptions(io: *const std.Io) t.FileOptions {
    return .{
        .read = zigRead,
        .release = zigRelease,
        .user_data = @ptrCast(@constCast(io)),
    };
}

fn allocThrough(memory: *const t.MemoryOptions, size: usize) ?*anyopaque {
    if (memory.alloc_func) |f| return f(memory.user_data, size);
    return std.c.malloc(size);
}

fn freeThrough(memory: *const t.MemoryOptions, ptr: ?*anyopaque) void {
    if (memory.free_func) |f| return f(memory.user_data, ptr);
    std.c.free(ptr);
}

fn zigRead(
    memory: *const t.MemoryOptions,
    file_opts: *const t.FileOptions,
    path: [*:0]const u8,
    size: *t.Size,
    data: *?*anyopaque,
) callconv(.c) t.Result {
    const io: *const std.Io = @ptrCast(@alignCast(file_opts.user_data orelse
        return .invalid_options));

    const file = std.Io.Dir.cwd().openFile(io.*, std.mem.span(path), .{}) catch |err|
        return switch (err) {
            error.FileNotFound => .file_not_found,
            else => .io_error,
        };
    defer file.close(io.*);

    // A caller-provided size is a cap (GLB knows its chunk sizes); zero
    // means read the whole file — upstream's contract.
    var want: usize = size.*;
    if (want == 0) {
        const stat = file.stat(io.*) catch return .io_error;
        want = std.math.cast(usize, stat.size) orelse return .io_error;
    }

    const buffer = allocThrough(memory, want) orelse return .out_of_memory;
    const bytes = @as([*]u8, @ptrCast(buffer))[0..want];
    var got: usize = 0;
    while (got < want) {
        const n = file.readStreaming(io.*, &.{bytes[got..]}) catch {
            freeThrough(memory, buffer);
            return .io_error;
        };
        if (n == 0) break;
        got += n;
    }
    if (got != want) {
        freeThrough(memory, buffer);
        return .io_error;
    }

    size.* = want;
    data.* = buffer;
    return .success;
}

fn zigRelease(
    memory: *const t.MemoryOptions,
    _: *const t.FileOptions,
    data: ?*anyopaque,
) callconv(.c) void {
    freeThrough(memory, data);
}

const document = @import("document.zig");
const memory_adapter = @import("memory.zig");

test fileOptions {
    // The full Zig-backed stack: std.Io reads, std.testing.allocator
    // allocates (and fails the test on any leak).
    var options = std.mem.zeroes(t.Options);
    options.memory = memory_adapter.memoryOptions(&std.testing.allocator);
    options.file = fileOptions(&std.testing.io);

    const path = "tests/data/triangle.gltf";
    const data = try document.parseFile(&options, path);
    defer document.free(data);
    try document.loadBuffers(&options, data, path);
    try document.validate(data);
    try std.testing.expectEqual(@as(usize, 1), data.meshes_count);

    try std.testing.expectError(
        error.FileNotFound,
        document.parseFile(&options, "tests/data/no_such_file.gltf"),
    );
}
