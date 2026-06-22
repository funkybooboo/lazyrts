const std = @import("std");
const config = @import("../config.zig");

pub const TownCenter = struct {};

pub fn glyph(cfg: *const config.Config) []const u8 {
    return cfg.glyphs.town_center;
}

pub fn label(cfg: *const config.Config) []const u8 {
    return cfg.labels.town_center;
}

pub fn maxHp(cfg: *const config.Config) u16 {
    return cfg.building_hp.town_center;
}

pub fn isDropoff() bool {
    return true;
}

pub fn popHousing(cfg: *const config.Config) usize {
    return cfg.pop_per_housing;
}

test "glyph is C" {
    const cfg = config.default();
    try std.testing.expectEqualStrings("C", glyph(&cfg));
}

test "maxHp positive" {
    const cfg = config.default();
    try std.testing.expect(maxHp(&cfg) > 0);
}

test "isDropoff true" {
    try std.testing.expect(isDropoff());
}

test "popHousing positive" {
    const cfg = config.default();
    try std.testing.expect(popHousing(&cfg) > 0);
}
