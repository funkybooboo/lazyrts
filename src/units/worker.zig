const std = @import("std");
const config = @import("../config.zig");

pub const Worker = struct {};

pub fn glyph(cfg: *const config.Config) []const u8 {
    return cfg.glyphs.worker;
}

pub fn maxHp(cfg: *const config.Config) u16 {
    return cfg.unit_hp.worker;
}

pub fn damage() u16 {
    return 3;
}

test "glyph is lowercase w" {
    const cfg = config.default();
    try std.testing.expectEqualStrings("w", glyph(&cfg));
}

test "maxHp positive" {
    const cfg = config.default();
    try std.testing.expect(maxHp(&cfg) > 0);
}

test "damage is 3" {
    try std.testing.expectEqual(@as(u16, 3), damage());
}
