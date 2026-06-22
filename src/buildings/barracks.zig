const std = @import("std");
const config = @import("../config.zig");

pub const Barracks = struct {};

pub fn glyph(cfg: *const config.Config) []const u8 {
    return cfg.glyphs.barracks;
}

pub fn label(cfg: *const config.Config) []const u8 {
    return cfg.labels.barracks;
}

pub fn maxHp(cfg: *const config.Config) u16 {
    return cfg.building_hp.barracks;
}

pub fn isDropoff() bool {
    return false;
}

pub fn popHousing(cfg: *const config.Config) usize {
    _ = cfg;
    return 0;
}

test "glyph is B" {
    const cfg = config.default();
    try std.testing.expectEqualStrings("B", glyph(&cfg));
}

test "maxHp positive" {
    const cfg = config.default();
    try std.testing.expect(maxHp(&cfg) > 0);
}

test "isDropoff false" {
    try std.testing.expect(!isDropoff());
}

test "popHousing zero" {
    const cfg = config.default();
    try std.testing.expectEqual(@as(usize, 0), popHousing(&cfg));
}
