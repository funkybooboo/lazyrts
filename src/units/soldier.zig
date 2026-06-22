const std = @import("std");
const config = @import("../config.zig");

pub const Soldier = struct {};

pub fn glyph(cfg: *const config.Config) []const u8 {
    return cfg.glyphs.soldier;
}

pub fn maxHp(cfg: *const config.Config) u16 {
    return cfg.unit_hp.soldier;
}

pub fn damage() u16 {
    return 8;
}

test "glyph is lowercase s" {
    const cfg = config.default();
    try std.testing.expectEqualStrings("s", glyph(&cfg));
}

test "maxHp positive" {
    const cfg = config.default();
    try std.testing.expect(maxHp(&cfg) > 0);
}

test "damage is 8" {
    try std.testing.expectEqual(@as(u16, 8), damage());
}
