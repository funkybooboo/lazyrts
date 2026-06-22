const std = @import("std");
const config = @import("../config.zig");

pub const DropPile = struct {};

pub fn glyph(cfg: *const config.Config) []const u8 {
    return cfg.glyphs.drop_pile;
}

pub fn label(cfg: *const config.Config) []const u8 {
    return cfg.labels.drop_pile;
}

pub fn maxHp(cfg: *const config.Config) u16 {
    return cfg.building_hp.drop_pile;
}

pub fn isDropoff() bool {
    return true;
}

pub fn popHousing(cfg: *const config.Config) usize {
    _ = cfg;
    return 0;
}

test "glyph is P" {
    const cfg = config.default();
    try std.testing.expectEqualStrings("P", glyph(&cfg));
}

test "maxHp positive" {
    const cfg = config.default();
    try std.testing.expect(maxHp(&cfg) > 0);
}

test "isDropoff true" {
    try std.testing.expect(isDropoff());
}

test "popHousing zero" {
    const cfg = config.default();
    try std.testing.expectEqual(@as(usize, 0), popHousing(&cfg));
}
