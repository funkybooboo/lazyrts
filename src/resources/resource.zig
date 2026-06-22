const std = @import("std");
const config = @import("../config.zig");
const unit = @import("../units/unit.zig");
const coords = @import("../lib/coords.zig");
const tree = @import("tree.zig");
const deer_mod = @import("deer.zig");

pub const Kind = enum {
    tree,
    deer,

    pub fn glyph(self: Kind, cfg: *const config.Config) []const u8 {
        return switch (self) {
            .tree => tree.glyph(cfg),
            .deer => deer_mod.glyph(cfg),
        };
    }
};

pub const ResourceRef = union(Kind) {
    tree: coords.Pos,
    deer: usize,
};

pub fn glyphOf(kind: Kind, cfg: *const config.Config) []const u8 {
    return kind.glyph(cfg);
}

test "Kind.glyph tree and deer" {
    const cfg = config.default();
    try std.testing.expectEqualStrings(cfg.glyphs.tree, Kind.tree.glyph(&cfg));
    try std.testing.expectEqualStrings(cfg.glyphs.deer, Kind.deer.glyph(&cfg));
}

test "ResourceRef holds tree position" {
    const r: ResourceRef = .{ .tree = .{ .x = 5, .y = 9 } };
    try std.testing.expectEqual(Kind.tree, std.meta.activeTag(r));
    try std.testing.expectEqual(@as(usize, 5), r.tree.x);
}

test "ResourceRef holds deer index" {
    const r: ResourceRef = .{ .deer = 3 };
    try std.testing.expectEqual(Kind.deer, std.meta.activeTag(r));
    try std.testing.expectEqual(@as(usize, 3), r.deer);
}
