const std = @import("std");
const config = @import("../config.zig");
const game_map = @import("../game/map.zig");

pub fn glyph(cfg: *const config.Config) []const u8 {
    return cfg.glyphs.tree;
}

pub fn totalYield(cfg: *const config.Config) u16 {
    return cfg.economy.tree_total_yield;
}

pub fn yieldPerHarvest(cfg: *const config.Config) u16 {
    return cfg.economy.tree_yield;
}

pub fn isAt(m: *const game_map.GameMap, x: usize, y: usize) bool {
    return m.at(x, y) == .tree;
}

pub fn remainingAt(m: *const game_map.GameMap, x: usize, y: usize) u16 {
    return m.treeRemainingAt(x, y);
}

pub fn deplete(m: *game_map.GameMap, x: usize, y: usize, amount: u16) void {
    m.depleteTree(x, y, amount);
}

test "glyph non-empty" {
    const cfg = config.default();
    try std.testing.expect(glyph(&cfg).len > 0);
}

test "totalYield positive" {
    const cfg = config.default();
    try std.testing.expect(totalYield(&cfg) > 0);
}

test "yieldPerHarvest positive" {
    const cfg = config.default();
    try std.testing.expect(yieldPerHarvest(&cfg) > 0);
}

test "totalYield greater than yieldPerHarvest" {
    const cfg = config.default();
    try std.testing.expect(totalYield(&cfg) > yieldPerHarvest(&cfg));
}
