const std = @import("std");
const config = @import("../config.zig");

pub const House = struct {};

pub fn glyph(cfg: *const config.Config) []const u8 {
    return cfg.glyphs.house;
}

pub fn label(cfg: *const config.Config) []const u8 {
    return cfg.labels.house;
}

pub fn maxHp(cfg: *const config.Config) u16 {
    return cfg.building_hp.house;
}

pub fn isDropoff() bool {
    return false;
}

pub fn popHousing(cfg: *const config.Config) usize {
    return cfg.pop_per_housing;
}

test "glyph is H" {
    const cfg = config.default();
    try std.testing.expectEqualStrings("H", glyph(&cfg));
}

test "maxHp positive" {
    const cfg = config.default();
    try std.testing.expect(maxHp(&cfg) > 0);
}

test "isDropoff false" {
    try std.testing.expect(!isDropoff());
}

test "popHousing positive" {
    const cfg = config.default();
    try std.testing.expect(popHousing(&cfg) > 0);
}
