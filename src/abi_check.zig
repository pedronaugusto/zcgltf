//! Comptime cross-check: the hand-written externs in `src/c/` against the
//! vendored `cgltf.h` + `cgltf_write.h`, `@cImport`'d only in a test (the
//! shipped module stays translate-c-free), compared per declaration via
//! reflection; an unclassified declaration errors at compile time.
//!
//! Naming conventions are load-bearing: extern functions carry the C name
//! itself, type `BufferView` pairs with `cgltf_buffer_view` (snake case),
//! an enum's `upstream_prefix` decl plus its field name reconstructs each
//! enumerator, and the 6 scalar typedefs pair through `scalar_typedefs`
//! below (`Bool32` is `cgltf_bool`), each row itself verified. The reverse
//! sweep is the completeness gate: every header function must be bound.
//!
//! Pointees compare by size/alignment only (the check never descends into a
//! pointee; tests hold those); function pointers and the union compare deep.

const std = @import("std");
const c = @import("c.zig");

const h = @cImport({
    @cInclude("cgltf.h");
    @cInclude("cgltf_write.h");
});

//=============================================================================
// Name conventions, computed rather than tabulated
//=============================================================================

/// `BufferView` -> `buffer_view`, `Ior` -> `ior`.
fn snake(comptime name: []const u8) []const u8 {
    comptime {
        var out: []const u8 = "";
        for (name, 0..) |ch, i| {
            if (std.ascii.isUpper(ch)) {
                if (i != 0) out = out ++ "_";
                out = out ++ [_]u8{std.ascii.toLower(ch)};
            } else {
                out = out ++ [_]u8{ch};
            }
        }
        return out;
    }
}

fn typeCName(comptime name: []const u8) []const u8 {
    return "cgltf_" ++ snake(name);
}

/// The scalar typedef aliases, whose Zig names cannot be derived from the C
/// names mechanically (`Bool32` guards against `bool`-sized mistakes,
/// `SSize` would snake to `s_size`). Each row is verified against the real
/// typedef, and a scalar alias missing here is a compile error below.
const scalar_typedefs = .{
    .{ "Size", "cgltf_size" },
    .{ "SSize", "cgltf_ssize" },
    .{ "Float", "cgltf_float" },
    .{ "Int", "cgltf_int" },
    .{ "Uint", "cgltf_uint" },
    .{ "Bool32", "cgltf_bool" },
};

fn scalarCName(comptime name: []const u8) ?[]const u8 {
    inline for (scalar_typedefs) |row| {
        if (comptime std.mem.eql(u8, row[0], name)) return row[1];
    }
    return null;
}

//=============================================================================
// Comparison primitives
//
// Every failure is a compile error naming both sides — a guard that cannot
// state which declaration drifted costs more to read than the drift it found.
//=============================================================================

fn fail(comptime msg: []const u8) void {
    @compileError("zcgltf ABI drift: " ++ msg);
}

fn theirDecl(comptime name: []const u8, comptime because: []const u8) type {
    if (!@hasDecl(h, name)) {
        fail("`" ++ because ++ "` expects `" ++ name ++
            "` from the C headers, which do not declare it");
    }
    return @TypeOf(@field(h, name));
}

fn sameSizeAndAlign(
    comptime what: []const u8,
    comptime Ours: type,
    comptime Theirs: type,
) void {
    if (@sizeOf(Ours) != @sizeOf(Theirs)) {
        fail(what ++ " is " ++ std.fmt.comptimePrint("{d}", .{@sizeOf(Ours)}) ++
            " bytes on the Zig side but " ++ std.fmt.comptimePrint("{d}", .{@sizeOf(Theirs)}) ++
            " in the C header");
    }
    if (@alignOf(Ours) != @alignOf(Theirs)) {
        fail(what ++ " has alignment " ++ std.fmt.comptimePrint("{d}", .{@alignOf(Ours)}) ++
            " on the Zig side but " ++ std.fmt.comptimePrint("{d}", .{@alignOf(Theirs)}) ++
            " in the C header");
    }
}

/// The scalar a type really is at the boundary, with the Zig-side wrapper
/// removed. translate-c renders every C enum as a plain integer; this side
/// deliberately keeps enums as `enum(...)`, so each is resolved to its
/// backing integer first — not a loosening: an `enum(u32)` against a C
/// `int` enum is a real signedness disagreement, and this is what surfaces
/// it.
fn scalarIdentity(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .@"enum" => |e| e.tag_type,
        .@"struct" => |st| st.backing_integer orelse T,
        else => T,
    };
}

/// A `*const fn`/`?*const fn` unwrapped to the fn type, or null when the
/// type is not a function pointer. translate-c makes every C function
/// pointer optional; both sides unwrap the same way.
fn fnPointee(comptime T: type) ?type {
    const Base = switch (@typeInfo(T)) {
        .optional => |o| o.child,
        else => T,
    };
    if (@typeInfo(Base) == .pointer and
        @typeInfo(@typeInfo(Base).pointer.child) == .@"fn")
    {
        return @typeInfo(Base).pointer.child;
    }
    return null;
}

/// Size and alignment, plus the scalar identity they do not carry: a
/// `size_t` declared `isize` or a `float` declared `u32` passes both and
/// silently reinterprets every value — signedness and int-vs-float close
/// that. Function pointers on both sides compare signature-deep (upstream
/// has no named callback typedefs, so this is the one place a callback's
/// shape is held to the header); a union field recurses per member.
fn sameScalar(
    comptime what: []const u8,
    comptime Ours: type,
    comptime Theirs: type,
) void {
    sameSizeAndAlign(what, Ours, Theirs);

    if (fnPointee(Ours)) |OursFn| {
        if (fnPointee(Theirs)) |TheirsFn| {
            checkFnType(what ++ " (callback)", OursFn, TheirsFn);
            return;
        }
        fail(what ++ " is a function pointer on the Zig side but not in the C header");
    } else if (fnPointee(Theirs) != null) {
        fail(what ++ " is a function pointer in the C header but not on the Zig side");
    }

    if (@typeInfo(Ours) == .@"union" or @typeInfo(Theirs) == .@"union") {
        if (@typeInfo(Ours) != .@"union" or @typeInfo(Theirs) != .@"union") {
            fail(what ++ " is a union on one side of the boundary only");
        }
        checkUnionLayout(what, Ours, Theirs);
        return;
    }

    const oi = @typeInfo(scalarIdentity(Ours));
    const ti = @typeInfo(scalarIdentity(Theirs));

    // Signedness, EXCEPT across an enum: C leaves an enum's underlying type
    // to the implementation (clang/gcc pick unsigned when no enumerator is
    // negative, MSVC uses `int`), so comparing it would fail a correct
    // binding on one toolchain and pass on another. Safe to skip only
    // because every enumerator here is non-negative — `checkEnumValues`
    // asserts that precondition rather than assuming it.
    const across_enum = scalarIdentity(Ours) != Ours or scalarIdentity(Theirs) != Theirs;
    if (!across_enum and oi == .int and ti == .int and
        oi.int.signedness != ti.int.signedness)
    {
        fail(what ++ " is " ++ @tagName(oi.int.signedness) ++ " on the Zig side but " ++
            @tagName(ti.int.signedness) ++ " in the C header");
    }
    if ((oi == .int) != (ti == .int) or (oi == .float) != (ti == .float)) {
        fail(what ++ " is a " ++ @tagName(oi) ++ " on the Zig side but a " ++
            @tagName(ti) ++ " in the C header");
    }
}

/// Compares two function types by the things translate-c preserves: how many
/// parameters there are, how each one is passed, and whether the signature
/// is variadic.
fn checkFnType(
    comptime what: []const u8,
    comptime Ours: type,
    comptime Theirs: type,
) void {
    const ours = @typeInfo(Ours).@"fn";
    const theirs = @typeInfo(Theirs).@"fn";

    if (ours.params.len != theirs.params.len) {
        fail(what ++ " takes " ++ std.fmt.comptimePrint("{d}", .{ours.params.len}) ++
            " parameters on the Zig side but " ++ std.fmt.comptimePrint("{d}", .{theirs.params.len}) ++
            " in the C header");
    }
    if (ours.is_var_args != theirs.is_var_args) {
        fail(what ++ " is variadic on one side of the boundary only");
    }

    inline for (ours.params, theirs.params, 0..) |op, tp, i| {
        const OP = op.type orelse fail(what ++ " has an untyped parameter on the Zig side");
        const TP = tp.type orelse fail(what ++ " has an untyped parameter in the C header");
        sameScalar(
            what ++ " parameter " ++ std.fmt.comptimePrint("{d}", .{i}),
            OP,
            TP,
        );
    }

    const OR = ours.return_type orelse fail(what ++ " has no return type on the Zig side");
    const TR = theirs.return_type orelse fail(what ++ " has no return type in the C header");
    sameScalar(what ++ " return value", OR, TR);
}

//=============================================================================
// Hazard shapes
//
// Two caller shapes were measured miscompiled by Zig 0.16.0 in the sibling
// package zmeshopt (its hosted CI, 2026-09-02): a float argument after more
// than 6 integer-class parameters, and a small all-float struct returned by
// value. cgltf's surface has NEITHER shape, so this package needs no
// forwarding shim — and both counts are pinned at 0 below so a re-vendor
// that introduces one is a conscious decision, not a silent regression.
//=============================================================================

const max_int_class_params_before_float = 6;

/// True when `Fn` passes a float after more than 6 integer-class parameters.
fn hasLateFloat(comptime Fn: type) bool {
    comptime {
        var int_class: usize = 0;
        for (@typeInfo(Fn).@"fn".params) |p| {
            const P = p.type orelse continue;
            switch (@typeInfo(scalarIdentity(P))) {
                .float, .vector => {
                    if (int_class > max_int_class_params_before_float) return true;
                },
                else => int_class += 1,
            }
        }
        return false;
    }
}

/// True when `Fn` returns a struct or union by value.
fn hasAggregateReturn(comptime Fn: type) bool {
    const R = @typeInfo(Fn).@"fn".return_type orelse return false;
    return switch (@typeInfo(scalarIdentity(R))) {
        .@"struct", .@"union" => true,
        else => false,
    };
}

//=============================================================================
// Struct, union and enum comparisons
//=============================================================================

/// Struct layout, compared field by NAME rather than by position — the
/// distinction that makes the check worth having. Two same-sized adjacent
/// fields swapping places leaves the *sequence* of offsets identical, so a
/// positional comparison passes a swap that silently reinterprets both
/// fields; pairing each name with its own offset catches it.
fn checkStructLayout(
    comptime what: []const u8,
    comptime Ours: type,
    comptime Theirs: type,
) void {
    sameSizeAndAlign(what, Ours, Theirs);

    const ours = @typeInfo(Ours).@"struct";
    const theirs = switch (@typeInfo(Theirs)) {
        .@"struct" => |s| s,
        else => fail(what ++ " is a struct in src/c/ but not in the C header"),
    };

    if (ours.fields.len != theirs.fields.len) {
        fail(what ++ " has " ++ std.fmt.comptimePrint("{d}", .{ours.fields.len}) ++
            " fields in src/c/ but " ++ std.fmt.comptimePrint("{d}", .{theirs.fields.len}) ++
            " in the C header");
    }

    inline for (ours.fields) |f| {
        if (!@hasField(Theirs, f.name)) {
            fail(what ++ " has field `" ++ f.name ++ "` in src/c/, which the C header does not");
        }
        if (@offsetOf(Ours, f.name) != @offsetOf(Theirs, f.name)) {
            fail(what ++ "." ++ f.name ++ " is at byte " ++
                std.fmt.comptimePrint("{d}", .{@offsetOf(Ours, f.name)}) ++ " in src/c/ but " ++
                std.fmt.comptimePrint("{d}", .{@offsetOf(Theirs, f.name)}) ++ " in the C header");
        }
        sameScalar(
            what ++ "." ++ f.name,
            f.type,
            @FieldType(Theirs, f.name),
        );
    }
}

/// Union layout, member by name. Upstream's one union is anonymous, so the
/// check reaches it through the struct field embedding it; every member
/// starts at byte 0 by construction, leaving names, member types and the
/// overall size to hold.
fn checkUnionLayout(
    comptime what: []const u8,
    comptime Ours: type,
    comptime Theirs: type,
) void {
    const ours = @typeInfo(Ours).@"union";
    const theirs = @typeInfo(Theirs).@"union";

    if (ours.layout != .@"extern") {
        fail(what ++ " is a union without extern layout, so it has no defined ABI");
    }
    if (ours.fields.len != theirs.fields.len) {
        fail(what ++ " has " ++ std.fmt.comptimePrint("{d}", .{ours.fields.len}) ++
            " members in src/c/ but " ++ std.fmt.comptimePrint("{d}", .{theirs.fields.len}) ++
            " in the C header");
    }
    inline for (ours.fields) |f| {
        if (!@hasField(Theirs, f.name)) {
            fail(what ++ " has member `" ++ f.name ++ "` in src/c/, which the C header does not");
        }
        sameScalar(what ++ "." ++ f.name, f.type, @FieldType(Theirs, f.name));
    }
}

/// Enumerator values, paired by `upstream_prefix` ++ the field name (cgltf
/// enumerators are snake case, so the field name IS the suffix).
///
/// translate-c flattens a C enum to an integer alias and loses which
/// enumerators belonged to it, so the values cannot be recovered from the
/// type; the prefix convention is what puts them back together.
fn checkEnumValues(
    comptime what: []const u8,
    comptime Ours: type,
) void {
    if (!@hasDecl(Ours, "upstream_prefix")) {
        fail(what ++ " has no `upstream_prefix` decl, so its enumerators cannot " ++
            "be paired with the header's constants");
    }
    inline for (@typeInfo(Ours).@"enum".fields) |f| {
        const cname = Ours.upstream_prefix ++ f.name;
        _ = theirDecl(cname, what ++ "." ++ f.name);
        // The precondition that lets sameScalar skip signedness across an
        // enum. C leaves the underlying type to the implementation, and the
        // implementations disagree; that is only unobservable while every
        // enumerator is non-negative.
        if (f.value < 0) {
            fail(what ++ "." ++ f.name ++ " is negative, which makes the enum's " ++
                "underlying type observable — C leaves that to the implementation " ++
                "and MSVC and clang choose differently.");
        }
        if (@as(i128, @field(h, cname)) != @as(i128, f.value)) {
            fail(what ++ "." ++ f.name ++ " is " ++
                std.fmt.comptimePrint("{d}", .{f.value}) ++ " in src/c/ but " ++ cname ++
                " is " ++ std.fmt.comptimePrint("{d}", .{@field(h, cname)}) ++ " in the C header");
        }
    }
}

//=============================================================================
// The sweep
//=============================================================================

const Counts = struct {
    types: usize = 0,
    functions: usize = 0,
    fields: usize = 0,
    enumerators: usize = 0,
    late_float_fns: usize = 0,
    aggregate_return_fns: usize = 0,
};

/// Every public declaration in `c.zig`'s modules, classified and compared.
/// The `else` arms are compile errors: a declaration this does not know how
/// to check is a hole in the guard, and a hole should stop the build rather
/// than be counted as a pass.
fn sweepOurs() Counts {
    comptime {
        var n = Counts{};

        for (c.modules, 0..) |m, mi| for (@typeInfo(m).@"struct".decls) |d| {
            // A name an EARLIER module already declared is a re-export,
            // checked once where it is declared; a re-export that stops being
            // the same declaration refuses the build.
            var earlier = false;
            for (c.modules, 0..) |other, oi| {
                if (oi < mi and @hasDecl(other, d.name)) {
                    if (@TypeOf(@field(other, d.name)) == type and
                        @TypeOf(@field(m, d.name)) == type and
                        @field(other, d.name) != @field(m, d.name))
                    {
                        fail("`" ++ d.name ++ "` is declared in two of src/c.zig's " ++
                            "modules and they are not the same declaration.");
                    }
                    earlier = true;
                }
            }
            if (earlier) continue;

            const Decl = @TypeOf(@field(m, d.name));

            // ---- types -----------------------------------------------------
            if (Decl == type) {
                const Ours = @field(m, d.name);
                const what = "type " ++ d.name;
                n.types += 1;

                switch (@typeInfo(Ours)) {
                    .@"struct" => |s| switch (s.layout) {
                        .@"extern" => {
                            _ = theirDecl(typeCName(d.name), what);
                            checkStructLayout(what, Ours, @field(h, typeCName(d.name)));
                            n.fields += s.fields.len;
                        },
                        .@"packed" => fail(what ++ " is a packed struct; cgltf has no " ++
                            "bit masks, so nothing here knows how to pair one — add " ++
                            "a mask check before introducing it"),
                        .auto => fail(what ++ " has automatic layout, so it has no " ++
                            "defined ABI; declare it extern"),
                    },
                    .@"union" => |u| {
                        // Anonymous upstream: no header name to pair with.
                        // The union is held to the header at every struct
                        // field embedding it — checkUnionLayout, reached
                        // through sameScalar — and its members are types
                        // with entries of their own.
                        if (u.layout != .@"extern") {
                            fail(what ++ " is a union without extern layout, so it " ++
                                "has no defined ABI");
                        }
                        n.fields += u.fields.len;
                    },
                    .@"enum" => |e| {
                        _ = theirDecl(typeCName(d.name), what);
                        sameSizeAndAlign(what, Ours, @field(h, typeCName(d.name)));
                        checkEnumValues(what, Ours);
                        n.enumerators += e.fields.len;
                    },
                    .int, .float => {
                        // A scalar typedef alias; the C name comes from the
                        // verified table because it cannot be derived.
                        const cname = scalarCName(d.name) orelse
                            fail(what ++ " is a scalar alias missing from " ++
                                "scalar_typedefs, so it cannot be paired with its " ++
                                "C typedef");
                        _ = theirDecl(cname, what);
                        sameScalar(what, Ours, @field(h, cname));
                    },
                    .pointer => {
                        // A callback alias of this binding's own. Upstream
                        // declares its function-pointer fields inline and
                        // names no typedef, so there is no header decl to
                        // pair with — the signature IS checked, deep, at
                        // every field that carries it.
                        if (fnPointee(Ours) == null) {
                            fail(what ++ " is a non-function pointer alias, which " ++
                                "this check does not know how to compare");
                        }
                    },
                    else => fail("type " ++ d.name ++ " is a " ++
                        @tagName(@typeInfo(Ours)) ++ ", which this check does not know " ++
                        "how to compare against the header"),
                }
                continue;
            }

            // ---- functions -------------------------------------------------
            if (@typeInfo(Decl) == .@"fn") {
                if (@typeInfo(Decl).@"fn".calling_convention == .auto) {
                    // A Zig helper, not an extern — allowed, but not on a
                    // boundary name: the reverse sweep only checks a name
                    // exists, so a helper on an exported symbol's name would
                    // satisfy it while the extern it displaced vanishes.
                    if (std.mem.startsWith(u8, d.name, "cgltf_")) {
                        fail("src/c/ declares `" ++ d.name ++ "` as a Zig function, " ++
                            "not an extern. The `cgltf_` prefix is reserved for " ++
                            "the C boundary here. Rename the helper.");
                    }
                    continue;
                }
                const what = "function " ++ d.name;
                _ = theirDecl(d.name, what);
                checkFnType(what, Decl, @TypeOf(@field(h, d.name)));
                if (hasLateFloat(Decl)) n.late_float_fns += 1;
                if (hasAggregateReturn(Decl)) n.aggregate_return_fns += 1;
                n.functions += 1;
                continue;
            }

            // ---- anything else ---------------------------------------------
            fail("src/c/ declares `" ++ d.name ++ "` as a " ++ @tagName(@typeInfo(Decl)) ++
                ", which this check does not know how to compare. Add a case rather " ++
                "than leaving it unchecked.");
        };

        return n;
    }
}

/// The other direction — the completeness gate. A function the headers
/// declare that `c.zig` never bound is invisible to the sweep above, because
/// that sweep only walks what `c.zig` has; this one walks the headers.
fn sweepTheirs() usize {
    comptime {
        var found: usize = 0;

        for (@typeInfo(h).@"struct".decls) |d| {
            // Filter by name BEFORE touching the value: translate-c emits
            // `@compileError` declarations for system macros it cannot
            // render, and evaluating one would fail the build for a reason
            // that has nothing to do with zcgltf.
            if (!std.mem.startsWith(u8, d.name, "cgltf_")) continue;
            if (@typeInfo(@TypeOf(@field(h, d.name))) != .@"fn") continue;

            found += 1;
            var home: ?type = null;
            for (c.modules) |m| {
                if (@hasDecl(m, d.name)) home = m;
            }
            if (home == null) {
                fail("the C headers declare `" ++ d.name ++ "` but no module in " ++
                    "src/c.zig binds it. This binding is complete by contract: " ++
                    "declare it in the module its header region names.");
            }
            // Existence is not enough: the name must resolve to something
            // that actually links. The forward sweep rejects helpers on
            // boundary names first; this is the backstop, and it depends only
            // on the header.
            const Ours = @TypeOf(@field(home.?, d.name));
            if (@typeInfo(Ours) != .@"fn") {
                fail("the C headers declare `" ++ d.name ++ "` but src/c/ declares " ++
                    "that name as a " ++ @tagName(@typeInfo(Ours)) ++ " rather than a function");
            }
            if (@typeInfo(Ours).@"fn".calling_convention == .auto) {
                fail("the C headers declare `" ++ d.name ++ "` but src/c/ declares " ++
                    "that name as a Zig function rather than an extern, so nothing " ++
                    "binds the symbol");
            }
        }
        return found;
    }
}

//=============================================================================
// The test
//
// The comparisons above are compile errors, so reaching this body means they
// passed. What's left: assert they actually ran — a sweep matching nothing
// silently would be indistinguishable from one matching everything.
//=============================================================================

test "ABI: src/c/ agrees with cgltf's headers, and binds all of them" {
    @setEvalBranchQuota(8_000_000);

    const ours = comptime sweepOurs();
    const theirs = comptime sweepTheirs();

    // The counted surface of cgltf v1.15. Floors, not equalities, for
    // everything except functions: the reverse sweep already fails on an
    // unbound function, so `functions == theirs` pins completeness exactly.
    try std.testing.expect(ours.types >= 70);
    try std.testing.expect(ours.functions >= 39);
    try std.testing.expect(ours.fields >= 340);
    try std.testing.expect(ours.enumerators >= 90);
    try std.testing.expectEqual(ours.functions, theirs);

    // The two caller shapes measured miscompiled in zmeshopt (see the
    // Hazard-shapes section): cgltf has neither, which is the reason this
    // package ships without a forwarding shim. A re-vendor that changes
    // either count reopens that decision explicitly.
    try std.testing.expectEqual(@as(usize, 0), ours.late_float_fns);
    try std.testing.expectEqual(@as(usize, 0), ours.aggregate_return_fns);
}
