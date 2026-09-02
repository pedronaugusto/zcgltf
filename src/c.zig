//! The C declaration modules, and the list the guards walk.
//!
//! The split follows the headers' own shape: `types` is `cgltf.h`'s
//! document model (every typedef, enum and struct), the function modules
//! are its declaration groups in header order, and `write` is
//! `cgltf_write.h`. That rule is mechanical, so a new declaration has
//! exactly one home and nobody has to argue about it.
//!
//! `modules` is the point of keeping this file at all: `abi_check.zig`
//! discovers what to check by walking it, so a module added here is swept
//! automatically, and a module not added here is a module the guard does
//! not cover — which its coverage floors turn into a build failure.

pub const types = @import("c/types.zig");
pub const document = @import("c/document.zig");
pub const access = @import("c/access.zig");
pub const index = @import("c/index.zig");
pub const write = @import("c/write.zig");

/// Every module above, in header order. Walked by `abi_check.zig`.
pub const modules = .{
    types,
    document,
    access,
    index,
    write,
};
