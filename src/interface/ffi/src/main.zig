// Alloyiser FFI Reference Implementation
//
// Implements the C-ABI functions declared in
// src/interface/abi/Alloyiser/ABI/Foreign.idr. The Idris2 ABI is the source of
// truth: every `%foreign "C:alloyiser_*"` symbol and every Result code below
// matches it exactly (symbol names, arity, and integer encodings).
//
// This is a self-contained reference: it builds an Alloy model in memory and
// serialises it to .als / JSON. Real assertion analysis (the JVM/Alloy Analyzer
// bridge) is future work; `alloyiser_analyze` reports no counterexamples.
//
// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

const std = @import("std");

const VERSION = "0.1.0";
const BUILD_INFO = "alloyiser built with Zig " ++ @import("builtin").zig_version_string;

//==============================================================================
// Result Codes (must match Alloyiser.ABI.Types.resultToInt)
//==============================================================================

pub const Result = enum(c_int) {
    ok = 0,
    err = 1, // Idris `Error`
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
    model_parse_error = 5,
    solver_timeout = 6,
    counterexample_found = 7,
};

fn code(r: Result) c_int {
    return @intFromEnum(r);
}

/// Thread-local last-error message (a static string; never freed by the caller).
threadlocal var last_error: ?[*:0]const u8 = null;

fn setError(msg: [*:0]const u8) void {
    last_error = msg;
}

//==============================================================================
// Model state
//==============================================================================

const Sig = struct { name: []u8, is_abstract: bool, parent: []u8 };
const Field = struct { owner: []u8, name: []u8, target: []u8, mult: u32 };
const Named = struct { name: []u8, body: []u8 };

/// An Alloy model under construction. Opaque to C (passed as a pointer).
const Model = struct {
    allocator: std.mem.Allocator,
    module_name: []u8,
    sigs: std.ArrayList(Sig),
    fields: std.ArrayList(Field),
    facts: std.ArrayList(Named),
    assertions: std.ArrayList(Named),

    fn deinit(self: *Model) void {
        const a = self.allocator;
        a.free(self.module_name);
        for (self.sigs.items) |s| {
            a.free(s.name);
            a.free(s.parent);
        }
        self.sigs.deinit();
        for (self.fields.items) |f| {
            a.free(f.owner);
            a.free(f.name);
            a.free(f.target);
        }
        self.fields.deinit();
        for (self.facts.items) |f| {
            a.free(f.name);
            a.free(f.body);
        }
        self.facts.deinit();
        for (self.assertions.items) |x| {
            a.free(x.name);
            a.free(x.body);
        }
        self.assertions.deinit();
    }
};

/// Duplicate a C string into an owned, non-sentinel byte slice.
fn dup(a: std.mem.Allocator, s: ?[*:0]const u8) ![]u8 {
    const slice: []const u8 = if (s) |p| std.mem.span(p) else "";
    return a.dupe(u8, slice);
}

//==============================================================================
// Model lifecycle
//==============================================================================

export fn alloyiser_model_create(module_name: ?[*:0]const u8) callconv(.C) ?*Model {
    const a = std.heap.c_allocator;
    const m = a.create(Model) catch {
        setError("alloyiser: failed to allocate model");
        return null;
    };
    m.* = .{
        .allocator = a,
        .module_name = dup(a, module_name) catch {
            a.destroy(m);
            setError("alloyiser: failed to allocate module name");
            return null;
        },
        .sigs = std.ArrayList(Sig).init(a),
        .fields = std.ArrayList(Field).init(a),
        .facts = std.ArrayList(Named).init(a),
        .assertions = std.ArrayList(Named).init(a),
    };
    return m;
}

export fn alloyiser_model_free(model: ?*Model) callconv(.C) void {
    const m = model orelse return;
    const a = m.allocator;
    m.deinit();
    a.destroy(m);
}

//==============================================================================
// Model construction
//==============================================================================

export fn alloyiser_add_sig(
    model: ?*Model,
    name: ?[*:0]const u8,
    is_abstract: u32,
    parent: ?[*:0]const u8,
) callconv(.C) c_int {
    const m = model orelse return code(.null_pointer);
    const n = dup(m.allocator, name) catch return code(.out_of_memory);
    const p = dup(m.allocator, parent) catch {
        m.allocator.free(n);
        return code(.out_of_memory);
    };
    m.sigs.append(.{ .name = n, .is_abstract = is_abstract != 0, .parent = p }) catch {
        m.allocator.free(n);
        m.allocator.free(p);
        return code(.out_of_memory);
    };
    return code(.ok);
}

export fn alloyiser_add_field(
    model: ?*Model,
    owner: ?[*:0]const u8,
    field: ?[*:0]const u8,
    target: ?[*:0]const u8,
    mult: u32,
) callconv(.C) c_int {
    const m = model orelse return code(.null_pointer);
    const o = dup(m.allocator, owner) catch return code(.out_of_memory);
    const f = dup(m.allocator, field) catch {
        m.allocator.free(o);
        return code(.out_of_memory);
    };
    const t = dup(m.allocator, target) catch {
        m.allocator.free(o);
        m.allocator.free(f);
        return code(.out_of_memory);
    };
    m.fields.append(.{ .owner = o, .name = f, .target = t, .mult = mult }) catch {
        m.allocator.free(o);
        m.allocator.free(f);
        m.allocator.free(t);
        return code(.out_of_memory);
    };
    return code(.ok);
}

fn addNamed(list: *std.ArrayList(Named), a: std.mem.Allocator, name: ?[*:0]const u8, body: ?[*:0]const u8) c_int {
    const n = dup(a, name) catch return code(.out_of_memory);
    const b = dup(a, body) catch {
        a.free(n);
        return code(.out_of_memory);
    };
    list.append(.{ .name = n, .body = b }) catch {
        a.free(n);
        a.free(b);
        return code(.out_of_memory);
    };
    return code(.ok);
}

export fn alloyiser_add_fact(model: ?*Model, name: ?[*:0]const u8, body: ?[*:0]const u8) callconv(.C) c_int {
    const m = model orelse return code(.null_pointer);
    return addNamed(&m.facts, m.allocator, name, body);
}

export fn alloyiser_add_assertion(model: ?*Model, name: ?[*:0]const u8, body: ?[*:0]const u8) callconv(.C) c_int {
    const m = model orelse return code(.null_pointer);
    return addNamed(&m.assertions, m.allocator, name, body);
}

//==============================================================================
// Analyzer (reference stub: no counterexamples)
//==============================================================================

export fn alloyiser_analyze(model: ?*Model, scope: u32, timeout_ms: u32) callconv(.C) c_int {
    _ = scope;
    _ = timeout_ms;
    if (model == null) return code(.null_pointer);
    // Reference build performs no SAT solving; all assertions vacuously hold.
    return code(.ok);
}

export fn alloyiser_counterexample_count(model: ?*Model) callconv(.C) u32 {
    if (model == null) return 0;
    return 0;
}

export fn alloyiser_counterexample_assertion(model: ?*Model, index: u32) callconv(.C) ?[*:0]const u8 {
    _ = model;
    _ = index;
    return null;
}

export fn alloyiser_counterexample_atom_count(model: ?*Model, index: u32) callconv(.C) u32 {
    _ = model;
    _ = index;
    return 0;
}

export fn alloyiser_counterexample_describe(model: ?*Model, index: u32) callconv(.C) ?[*:0]const u8 {
    _ = model;
    _ = index;
    return null;
}

//==============================================================================
// Serialisation
//==============================================================================

fn multKeyword(mult: u32) []const u8 {
    return switch (mult) {
        0 => "one",
        1 => "lone",
        2 => "set",
        else => "seq",
    };
}

fn renderAls(m: *Model) ![:0]u8 {
    var buf = std.ArrayList(u8).init(m.allocator);
    defer buf.deinit();
    const w = buf.writer();
    try w.print("module {s}\n\n", .{m.module_name});
    for (m.sigs.items) |s| {
        if (s.is_abstract) try w.writeAll("abstract ");
        if (s.parent.len > 0) {
            try w.print("sig {s} extends {s} {{", .{ s.name, s.parent });
        } else {
            try w.print("sig {s} {{", .{s.name});
        }
        var first = true;
        for (m.fields.items) |f| {
            if (std.mem.eql(u8, f.owner, s.name)) {
                try w.print("{s}\n  {s}: {s} {s}", .{ if (first) "" else ",", f.name, multKeyword(f.mult), f.target });
                first = false;
            }
        }
        try w.writeAll(if (first) "}\n" else "\n}\n");
    }
    for (m.facts.items) |f| try w.print("\nfact {s} {{ {s} }}\n", .{ f.name, f.body });
    for (m.assertions.items) |x| try w.print("\nassert {s} {{ {s} }}\n", .{ x.name, x.body });
    return buf.toOwnedSliceSentinel(0);
}

export fn alloyiser_model_to_als(model: ?*Model) callconv(.C) ?[*:0]const u8 {
    const m = model orelse return null;
    const out = renderAls(m) catch {
        setError("alloyiser: failed to render .als");
        return null;
    };
    return out.ptr;
}

export fn alloyiser_model_to_json(model: ?*Model) callconv(.C) ?[*:0]const u8 {
    const m = model orelse return null;
    var buf = std.ArrayList(u8).init(m.allocator);
    defer buf.deinit();
    const w = buf.writer();
    w.print("{{\"module\":\"{s}\",\"sigs\":{d},\"fields\":{d},\"facts\":{d},\"assertions\":{d}}}", .{ m.module_name, m.sigs.items.len, m.fields.items.len, m.facts.items.len, m.assertions.items.len }) catch {
        setError("alloyiser: failed to render JSON");
        return null;
    };
    const out = buf.toOwnedSliceSentinel(0) catch return null;
    return out.ptr;
}

//==============================================================================
// String / error helpers
//==============================================================================

export fn alloyiser_free_string(str: ?[*:0]const u8) callconv(.C) void {
    const p = str orelse return;
    std.heap.c_allocator.free(std.mem.span(p));
}

export fn alloyiser_last_error() callconv(.C) ?[*:0]const u8 {
    return last_error;
}

export fn alloyiser_version() callconv(.C) [*:0]const u8 {
    return VERSION;
}

export fn alloyiser_build_info() callconv(.C) [*:0]const u8 {
    return BUILD_INFO;
}

//==============================================================================
// Tests
//==============================================================================

test "model lifecycle and serialisation" {
    const m = alloyiser_model_create("univ") orelse return error.CreateFailed;
    defer alloyiser_model_free(m);

    try std.testing.expectEqual(code(.ok), alloyiser_add_sig(m, "Node", 0, ""));
    try std.testing.expectEqual(code(.ok), alloyiser_add_field(m, "Node", "next", "Node", 1));
    try std.testing.expectEqual(code(.ok), alloyiser_add_assertion(m, "acyclic", "no n: Node | n in n.^next"));
    try std.testing.expectEqual(code(.ok), alloyiser_analyze(m, 4, 1000));
    try std.testing.expectEqual(@as(u32, 0), alloyiser_counterexample_count(m));

    const als = alloyiser_model_to_als(m) orelse return error.RenderFailed;
    defer alloyiser_free_string(als);
    try std.testing.expect(std.mem.indexOf(u8, std.mem.span(als), "sig Node") != null);
}

test "null handle is rejected" {
    try std.testing.expectEqual(code(.null_pointer), alloyiser_add_fact(null, "f", "true"));
    try std.testing.expectEqual(@as(u32, 0), alloyiser_counterexample_count(null));
}
