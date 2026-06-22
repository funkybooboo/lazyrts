const std = @import("std");
const config = @import("../config.zig");

pub const Farm = struct {
    food_remaining: u16 = 0,
    fallow: bool = false,
    assigned_worker: ?usize = null,
};

pub fn glyph(cfg: *const config.Config) []const u8 {
    return cfg.glyphs.farm;
}

pub fn label(cfg: *const config.Config) []const u8 {
    return cfg.labels.farm;
}

pub fn maxHp(cfg: *const config.Config) u16 {
    return cfg.building_hp.farm;
}

pub fn isDropoff() bool {
    return false;
}

pub fn popHousing(cfg: *const config.Config) usize {
    _ = cfg;
    return 0;
}

pub fn resow(f: *Farm, cfg: *const config.Config) void {
    f.fallow = false;
    f.food_remaining = cfg.economy.farm_yield_total;
}

test "glyph is F" {
    const cfg = config.default();
    try std.testing.expectEqualStrings("F", glyph(&cfg));
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

test "resow clears fallow and refills food" {
    const cfg = config.default();
    var f = Farm{ .food_remaining = 0, .fallow = true };
    resow(&f, &cfg);
    try std.testing.expect(!f.fallow);
    try std.testing.expectEqual(cfg.economy.farm_yield_total, f.food_remaining);
}
