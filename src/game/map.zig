const std = @import("std");
const unit = @import("../units/unit.zig");
const coords = @import("../lib/coords.zig");
const config = @import("../config.zig");
const mapgen = @import("mapgen.zig");

pub const Tile = enum {
    grass,
    tree,
    water,
    town_center,
    house,
    barracks,

    pub fn glyph(self: Tile, cfg: *const config.Config) []const u8 {
        return switch (self) {
            .grass => cfg.glyphs.grass,
            .tree => cfg.glyphs.tree,
            .water => cfg.glyphs.water,
            .town_center => cfg.glyphs.town_center,
            .house => cfg.glyphs.house,
            .barracks => cfg.glyphs.barracks,
        };
    }

    pub fn isWalkable(self: Tile) bool {
        return switch (self) {
            .grass, .town_center => true,
            .tree, .water, .house, .barracks => false,
        };
    }

    pub fn label(self: Tile, cfg: *const config.Config) []const u8 {
        return switch (self) {
            .grass => cfg.labels.grass,
            .tree => cfg.labels.tree,
            .water => cfg.labels.water,
            .town_center => cfg.labels.town_center,
            .house => cfg.labels.house,
            .barracks => cfg.labels.barracks,
        };
    }
};

pub const GameMap = struct {
    tiles: []Tile,
    tree_remaining: []u16,
    width: u16,
    height: u16,
    player_tc_x: u16,
    player_tc_y: u16,
    enemy_tc_x: u16,
    enemy_tc_y: u16,

    pub fn init(allocator: std.mem.Allocator, seed: u64, w: u16, h: u16, cfg: *const config.Config) !GameMap {
        return mapgen.generate(allocator, seed, w, h, cfg);
    }

    pub fn deinit(self: *GameMap, allocator: std.mem.Allocator) void {
        allocator.free(self.tiles);
        allocator.free(self.tree_remaining);
        self.tiles = &[_]Tile{};
        self.tree_remaining = &[_]u16{};
    }

    pub fn at(self: *const GameMap, x: usize, y: usize) Tile {
        if (x >= self.width or y >= self.height) return .water;
        return self.tiles[y * self.width + x];
    }

    pub fn isWalkable(self: *const GameMap, x: usize, y: usize) bool {
        return self.at(x, y).isWalkable();
    }

    pub fn set(self: *GameMap, x: usize, y: usize, tile: Tile) void {
        if (x >= self.width or y >= self.height) return;
        const idx = y * self.width + x;
        self.tiles[idx] = tile;
        if (tile != .tree) self.tree_remaining[idx] = 0;
    }

    pub fn treeRemainingAt(self: *const GameMap, x: usize, y: usize) u16 {
        if (x >= self.width or y >= self.height) return 0;
        return self.tree_remaining[y * self.width + x];
    }

    pub fn depleteTree(self: *GameMap, x: usize, y: usize, amount: u16) void {
        if (x >= self.width or y >= self.height) return;
        const idx = y * self.width + x;
        if (self.tree_remaining[idx] <= amount) {
            self.tree_remaining[idx] = 0;
            self.tiles[idx] = .grass;
        } else {
            self.tree_remaining[idx] -= amount;
        }
    }

    pub fn nearTc(self: *const GameMap, x: usize, y: usize, min_dist: usize) bool {
        const dx_p = if (x > self.player_tc_x) x - self.player_tc_x else self.player_tc_x - x;
        const dy_p = if (y > self.player_tc_y) y - self.player_tc_y else self.player_tc_y - y;
        if (dx_p + dy_p < min_dist) return true;
        const dx_e = if (x > self.enemy_tc_x) x - self.enemy_tc_x else self.enemy_tc_x - x;
        const dy_e = if (y > self.enemy_tc_y) y - self.enemy_tc_y else self.enemy_tc_y - y;
        if (dx_e + dy_e < min_dist) return true;
        return false;
    }

    pub fn deerCount(self: *const GameMap, cfg: *const config.Config) usize {
        const area = @as(usize, self.width) * @as(usize, self.height);
        return @max(cfg.deer.min_count, area / cfg.deer.area_divisor);
    }
};

test "at returns water for out of bounds" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m = try GameMap.init(allocator, 1, 80, 40, &cfg);
    defer m.deinit(allocator);
    try std.testing.expectEqual(.water, m.at(80, 0));
    try std.testing.expectEqual(.water, m.at(0, 40));
}

test "at returns tile within bounds" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m = try GameMap.init(allocator, 1, 80, 40, &cfg);
    defer m.deinit(allocator);
    try std.testing.expectEqual(.town_center, m.at(m.player_tc_x, m.player_tc_y));
}

test "init places both TCs" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    const m = try GameMap.init(allocator, 99, 80, 40, &cfg);
    defer {
        var mut_m = m;
        mut_m.deinit(allocator);
    }
    try std.testing.expectEqual(.town_center, m.at(m.player_tc_x, m.player_tc_y));
    try std.testing.expectEqual(.town_center, m.at(m.enemy_tc_x, m.enemy_tc_y));
}

test "init clears areas around TCs" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m = try GameMap.init(allocator, 99, 80, 40, &cfg);
    defer m.deinit(allocator);
    try std.testing.expectEqual(.grass, m.at(m.player_tc_x + 1, m.player_tc_y + 1));
}

test "player TC on left, enemy on right" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    const m = try GameMap.init(allocator, 99, 80, 40, &cfg);
    defer {
        var mut_m = m;
        mut_m.deinit(allocator);
    }
    try std.testing.expect(m.player_tc_x < m.enemy_tc_x);
}

test "glyph returns single char" {
    const cfg = config.default();
    try std.testing.expectEqualStrings(cfg.glyphs.tree, Tile.tree.glyph(&cfg));
    try std.testing.expectEqualStrings(cfg.glyphs.grass, Tile.grass.glyph(&cfg));
    try std.testing.expectEqualStrings(cfg.glyphs.water, Tile.water.glyph(&cfg));
    try std.testing.expectEqualStrings(cfg.glyphs.town_center, Tile.town_center.glyph(&cfg));
}

test "isWalkable on Tile" {
    try std.testing.expect(Tile.grass.isWalkable());
    try std.testing.expect(Tile.town_center.isWalkable());
    try std.testing.expect(!Tile.tree.isWalkable());
    try std.testing.expect(!Tile.water.isWalkable());
    try std.testing.expect(!Tile.house.isWalkable());
}

test "isWalkable on GameMap" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m = try GameMap.init(allocator, 99, 80, 40, &cfg);
    defer m.deinit(allocator);
    try std.testing.expect(m.isWalkable(m.player_tc_x, m.player_tc_y));
    try std.testing.expect(!m.isWalkable(80, 0));
}

test "set changes a tile" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m = try GameMap.init(allocator, 99, 80, 40, &cfg);
    defer m.deinit(allocator);
    const tx = m.player_tc_x + 1;
    const ty = m.player_tc_y;
    m.set(tx, ty, .house);
    try std.testing.expectEqual(.house, m.at(tx, ty));
}

test "set ignores out of bounds" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m = try GameMap.init(allocator, 99, 80, 40, &cfg);
    defer m.deinit(allocator);
    m.set(80, 0, .house);
    try std.testing.expectEqual(.water, m.at(80, 0));
}

test "path exists between TCs" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m = try GameMap.init(allocator, 42, 80, 40, &cfg);
    defer m.deinit(allocator);
    try std.testing.expect(mapgen.hasWalkablePath(&m, allocator, m.player_tc_x, m.player_tc_y, m.enemy_tc_x, m.enemy_tc_y));
}

test "hasPath returns false for blocked maps" {
    const allocator = std.testing.allocator;
    const map_size: usize = 10 * 10;
    const tiles = try allocator.alloc(Tile, map_size);
    defer allocator.free(tiles);
    for (tiles) |*t| t.* = .grass;
    var m: GameMap = .{
        .tiles = tiles,
        .tree_remaining = &[_]u16{},
        .width = 10,
        .height = 10,
        .player_tc_x = 0,
        .player_tc_y = 0,
        .enemy_tc_x = 9,
        .enemy_tc_y = 9,
    };
    for (0..10) |y| {
        m.tiles[y * 10 + 5] = .water;
    }
    try std.testing.expect(!mapgen.hasWalkablePath(&m, allocator, 0, 0, 9, 9));
}

test "deerCount scales with map size" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m80 = try GameMap.init(allocator, 1, 80, 40, &cfg);
    defer m80.deinit(allocator);
    var m120 = try GameMap.init(allocator, 1, 120, 50, &cfg);
    defer m120.deinit(allocator);
    try std.testing.expect(m120.deerCount(&cfg) > m80.deerCount(&cfg));
}

test "deerCount minimum is 4" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m = try GameMap.init(allocator, 1, 20, 10, &cfg);
    defer m.deinit(allocator);
    try std.testing.expect(m.deerCount(&cfg) >= 4);
}

test "nearTc detects proximity" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m = try GameMap.init(allocator, 42, 80, 40, &cfg);
    defer m.deinit(allocator);
    try std.testing.expect(m.nearTc(m.player_tc_x, m.player_tc_y, 1));
    try std.testing.expect(!m.nearTc(m.width - 1, m.height - 1, 2));
}

test "init always has path between TCs" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    for (0..20) |seed| {
        var m = try GameMap.init(allocator, seed, 80, 40, &cfg);
        defer m.deinit(allocator);
        try std.testing.expect(mapgen.hasWalkablePath(&m, allocator, m.player_tc_x, m.player_tc_y, m.enemy_tc_x, m.enemy_tc_y));
    }
}

test "init clears walkable area around TCs" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m = try GameMap.init(allocator, 42, 80, 40, &cfg);
    defer m.deinit(allocator);
    const offsets = coords.dirs4;
    for (offsets) |o| {
        const nx: isize = @as(isize, @intCast(m.player_tc_x)) + o.dx;
        const ny: isize = @as(isize, @intCast(m.player_tc_y)) + o.dy;
        if (nx >= 0 and ny >= 0) {
            const ux: usize = @intCast(nx);
            const uy: usize = @intCast(ny);
            if (ux < m.width and uy < m.height) {
                try std.testing.expect(m.isWalkable(ux, uy));
            }
        }
    }
}

test "sector generation covers whole map" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m = try GameMap.init(allocator, 42, 120, 50, &cfg);
    defer m.deinit(allocator);
    var tree_count: usize = 0;
    for (0..m.height) |y| {
        for (0..m.width) |x| {
            if (m.at(x, y) == .tree) tree_count += 1;
        }
    }
    try std.testing.expect(tree_count > 0);
    const top_half = m.height / 2;
    var top_trees: usize = 0;
    var bot_trees: usize = 0;
    for (0..m.height) |y| {
        for (0..m.width) |x| {
            if (m.at(x, y) == .tree) {
                if (y < top_half) top_trees += 1 else bot_trees += 1;
            }
        }
    }
    const ratio = if (bot_trees > 0) @as(f64, @floatFromInt(top_trees)) / @as(f64, @floatFromInt(bot_trees)) else 999;
    try std.testing.expect(ratio > 0.3 and ratio < 3.0);
}

test "different seeds produce different maps" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m1 = try GameMap.init(allocator, 1, 80, 40, &cfg);
    defer m1.deinit(allocator);
    var m2 = try GameMap.init(allocator, 2, 80, 40, &cfg);
    defer m2.deinit(allocator);
    var diffs: usize = 0;
    for (0..m1.height) |y| {
        for (0..m1.width) |x| {
            if (m1.at(x, y) != m2.at(x, y)) diffs += 1;
        }
    }
    try std.testing.expect(diffs > 0);
}

test "clear radius is large enough for walking" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m = try GameMap.init(allocator, 42, 80, 40, &cfg);
    defer m.deinit(allocator);
    for (0..4) |dy| {
        for (0..4) |dx| {
            const x = m.player_tc_x + dx;
            const y = m.player_tc_y + dy;
            if (x < m.width and y < m.height) {
                try std.testing.expect(m.isWalkable(x, y));
            }
        }
    }
}

test "clusters are larger with bigger maps" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m_small = try GameMap.init(allocator, 42, 40, 20, &cfg);
    defer m_small.deinit(allocator);
    var m_large = try GameMap.init(allocator, 42, 160, 80, &cfg);
    defer m_large.deinit(allocator);
    var small_trees: usize = 0;
    var large_trees: usize = 0;
    for (0..m_small.height) |y| {
        for (0..m_small.width) |x| {
            if (m_small.at(x, y) == .tree) small_trees += 1;
        }
    }
    for (0..m_large.height) |y| {
        for (0..m_large.width) |x| {
            if (m_large.at(x, y) == .tree) large_trees += 1;
        }
    }
    try std.testing.expect(large_trees > small_trees);
}

test "water clusters exist on large maps" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var any_water = false;
    for (0..20) |seed| {
        var m = try GameMap.init(allocator, seed, 120, 50, &cfg);
        defer m.deinit(allocator);
        for (0..m.height) |y| {
            for (0..m.width) |x| {
                if (m.at(x, y) == .water) any_water = true;
            }
        }
    }
    try std.testing.expect(any_water);
}

test "different seeds produce varying tree counts" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var min_trees: usize = std.math.maxInt(usize);
    var max_trees: usize = 0;
    for (0..10) |seed| {
        var m = try GameMap.init(allocator, seed, 80, 40, &cfg);
        defer m.deinit(allocator);
        var tree_count: usize = 0;
        for (0..m.height) |y| {
            for (0..m.width) |x| {
                if (m.at(x, y) == .tree) tree_count += 1;
            }
        }
        if (tree_count < min_trees) min_trees = tree_count;
        if (tree_count > max_trees) max_trees = tree_count;
    }
    // Expect at least 30% variance across seeds
    try std.testing.expect(max_trees > min_trees * 13 / 10);
}

test "different seeds produce varying water counts" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var min_water: usize = std.math.maxInt(usize);
    var max_water: usize = 0;
    for (0..10) |seed| {
        var m = try GameMap.init(allocator, seed, 80, 40, &cfg);
        defer m.deinit(allocator);
        var water_count: usize = 0;
        for (0..m.height) |y| {
            for (0..m.width) |x| {
                if (m.at(x, y) == .water) water_count += 1;
            }
        }
        if (water_count < min_water) min_water = water_count;
        if (water_count > max_water) max_water = water_count;
    }
    // Expect some variance (at least 2 tiles difference)
    try std.testing.expect(max_water >= min_water + 2);
}
