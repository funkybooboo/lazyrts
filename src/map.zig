const std = @import("std");
const unit = @import("unit.zig");
const config = @import("config.zig");

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

    pub fn is_walkable(self: Tile) bool {
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
    width: u16,
    height: u16,
    player_tc_x: u16,
    player_tc_y: u16,
    enemy_tc_x: u16,
    enemy_tc_y: u16,

    pub fn init(allocator: std.mem.Allocator, seed: u64, w: u16, h: u16, cfg: *const config.Config) !GameMap {
        const map_width: usize = @as(usize, w);
        const map_height: usize = @as(usize, h);

        const tiles = try allocator.alloc(Tile, map_width * map_height);
        errdefer allocator.free(tiles);

        const player_tc_x_pos: usize = map_width * cfg.map_gen.player_tc_x_pct / 100;
        const player_tc_y_pos: usize = map_height / 2;
        const enemy_tc_x_pos: usize = @max(map_width * cfg.map_gen.enemy_tc_x_pct / 100, @as(usize, 1));
        const enemy_tc_y_pos: usize = map_height / 2;

        var m: GameMap = .{
            .tiles = tiles,
            .width = @intCast(map_width),
            .height = @intCast(map_height),
            .player_tc_x = @intCast(player_tc_x_pos),
            .player_tc_y = @intCast(player_tc_y_pos),
            .enemy_tc_x = @intCast(enemy_tc_x_pos),
            .enemy_tc_y = @intCast(enemy_tc_y_pos),
        };

        if (m.player_tc_x == m.enemy_tc_x and map_width > 2) {
            m.enemy_tc_x = @intCast(map_width - 1 - player_tc_x_pos);
        }

        var rng_obj = std.Random.DefaultPrng.init(seed);
        const rng = rng_obj.random();

        for (tiles) |*t| t.* = .grass;

        // Randomized TC clear radius
        const tc_clear = rng.intRangeAtMost(usize, cfg.map_gen.tc_clear_min, cfg.map_gen.tc_clear_max);
        m.clear(m.player_tc_x, m.player_tc_y, tc_clear);
        m.clear(m.enemy_tc_x, m.enemy_tc_y, tc_clear);

        // Randomized sector size per game
        const sector_size = rng.intRangeAtMost(usize, cfg.map_gen.sector_size_min, cfg.map_gen.sector_size_max);
        const sectors_x = map_width / sector_size + 1;
        const sectors_y = map_height / sector_size + 1;

        // Randomized biome probabilities per game
        const tree_density = rng.intRangeAtMost(usize, cfg.map_gen.tree_density_min, cfg.map_gen.tree_density_max);
        const water_density = rng.intRangeAtMost(usize, cfg.map_gen.water_density_min, cfg.map_gen.water_density_max);

        const area = map_width * map_height;

        for (0..sectors_y) |sector_y| {
            for (0..sectors_x) |sector_x| {
                const base_x = sector_x * sector_size + sector_size / 2;
                const base_y = sector_y * sector_size + sector_size / 2;
                const offset_x = rng.intRangeAtMost(usize, 0, sector_size / 2);
                const offset_y = rng.intRangeAtMost(usize, 0, sector_size / 2);
                const seed_x = @min(base_x + offset_x, map_width - 1);
                const seed_y = @min(base_y + offset_y, map_height - 1);

                const roll = rng.intRangeAtMost(usize, 0, 99);
                if (roll < tree_density) {
                    const cluster_min = cfg.map_gen.tree_cluster_min;
                    const cluster_max = @max(cluster_min + 1, area / cfg.map_gen.tree_cluster_max_div);
                    const cluster_size = rng.intRangeAtMost(usize, cluster_min, cluster_max);
                    if (!m.near_tc(seed_x, seed_y, tc_clear + cfg.map_gen.tree_tc_buffer)) {
                        try m.grow_cluster(allocator, seed_x, seed_y, .tree, cluster_size, rng, tc_clear, cfg);
                    }
                } else if (roll < tree_density + water_density) {
                    const cluster_min = cfg.map_gen.water_cluster_min;
                    const cluster_max = @max(cluster_min + 1, area / cfg.map_gen.water_cluster_max_div);
                    const cluster_size = rng.intRangeAtMost(usize, cluster_min, cluster_max);
                    if (!m.near_tc(seed_x, seed_y, tc_clear + cfg.map_gen.water_tc_buffer)) {
                        try m.grow_cluster(allocator, seed_x, seed_y, .water, cluster_size, rng, tc_clear, cfg);
                    }
                }
            }
        }

        // Scattered trees: break up grove monotony
        const scatter_pct = rng.intRangeAtMost(usize, cfg.map_gen.scatter_tree_min, cfg.map_gen.scatter_tree_max);
        if (scatter_pct > 0) {
            m.scatterTrees(rng, scatter_pct, tc_clear);
        }

        // Guaranteed starting grove near each TC
        try m.placeStartGrove(allocator, m.player_tc_x, m.player_tc_y, tc_clear, rng, cfg);
        try m.placeStartGrove(allocator, m.enemy_tc_x, m.enemy_tc_y, tc_clear, rng, cfg);

        m.set(m.player_tc_x, m.player_tc_y, .town_center);
        m.set(m.enemy_tc_x, m.enemy_tc_y, .town_center);

        if (!m.has_path(allocator, m.player_tc_x, m.player_tc_y, m.enemy_tc_x, m.enemy_tc_y)) {
            m.carve_corridor(m.player_tc_x, m.player_tc_y, m.enemy_tc_x, m.enemy_tc_y, cfg);
        }

        return m;
    }

    pub fn deinit(self: *GameMap, allocator: std.mem.Allocator) void {
        allocator.free(self.tiles);
        self.tiles = &[_]Tile{};
    }

    pub fn at(self: *const GameMap, x: usize, y: usize) Tile {
        if (x >= self.width or y >= self.height) return .water;
        return self.tiles[y * self.width + x];
    }

    pub fn is_walkable(self: *const GameMap, x: usize, y: usize) bool {
        return self.at(x, y).is_walkable();
    }

    pub fn set(self: *GameMap, x: usize, y: usize, tile: Tile) void {
        if (x >= self.width or y >= self.height) return;
        self.tiles[y * self.width + x] = tile;
    }

    fn clear(self: *GameMap, center_x: usize, center_y: usize, radius: usize) void {
        const y0 = if (center_y > radius) center_y - radius else 0;
        const y1 = @min(center_y + radius + 1, @as(usize, self.height));
        const x0 = if (center_x > radius) center_x - radius else 0;
        const x1 = @min(center_x + radius + 1, @as(usize, self.width));
        for (y0..y1) |y| {
            for (x0..x1) |x| {
                self.tiles[y * self.width + x] = .grass;
            }
        }
    }

    pub fn near_tc(self: *const GameMap, x: usize, y: usize, min_dist: usize) bool {
        const dx_p = if (x > self.player_tc_x) x - self.player_tc_x else self.player_tc_x - x;
        const dy_p = if (y > self.player_tc_y) y - self.player_tc_y else self.player_tc_y - y;
        if (dx_p + dy_p < min_dist) return true;
        const dx_e = if (x > self.enemy_tc_x) x - self.enemy_tc_x else self.enemy_tc_x - x;
        const dy_e = if (y > self.enemy_tc_y) y - self.enemy_tc_y else self.enemy_tc_y - y;
        if (dx_e + dy_e < min_dist) return true;
        return false;
    }

    fn grow_cluster(self: *GameMap, allocator: std.mem.Allocator, start_x: usize, start_y: usize, tile: Tile, count: usize, rng: std.Random, tc_clear: usize, cfg: *const config.Config) !void {
        const frontier_cap = cfg.map_gen.cluster_frontier_cap;
        const frontier = try allocator.alloc(unit.Pos, frontier_cap);
        defer allocator.free(frontier);
        
        var fhead: usize = 1;
        var ftail: usize = 0;
        frontier[0] = .{ .x = start_x, .y = start_y };
        var placed: usize = 0;
        while (placed < count and ftail < fhead) {
            const idx = rng.intRangeAtMost(usize, ftail, fhead - 1);
            const cand = frontier[idx];
            frontier[idx] = frontier[ftail];
            frontier[ftail] = cand;
            ftail += 1;
            if (cand.x < self.width and cand.y < self.height) {
                if (self.tiles[cand.y * self.width + cand.x] == .grass and !self.near_tc(cand.x, cand.y, tc_clear + cfg.map_gen.cluster_tc_buffer)) {
                    self.tiles[cand.y * self.width + cand.x] = tile;
                    placed += 1;
                    const offsets = [_]struct { dx: isize, dy: isize }{
                        .{ .dx = 0, .dy = -1 }, .{ .dx = 0, .dy = 1 },
                        .{ .dx = -1, .dy = 0 }, .{ .dx = 1, .dy = 0 },
                    };
                    for (offsets) |off| {
                        const next_x = @as(isize, @intCast(cand.x)) + off.dx;
                        const next_y = @as(isize, @intCast(cand.y)) + off.dy;
                        if (next_x >= 0 and next_y >= 0) {
                            const tile_x: usize = @intCast(next_x);
                            const tile_y: usize = @intCast(next_y);
                            if (tile_x < self.width and tile_y < self.height and fhead < frontier.len) {
                                if (self.tiles[tile_y * self.width + tile_x] == .grass) {
                                    frontier[fhead] = .{ .x = tile_x, .y = tile_y };
                                    fhead += 1;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    fn scatterTrees(self: *GameMap, rng: std.Random, pct: usize, tc_clear: usize) void {
        const area = @as(usize, self.width) * @as(usize, self.height);
        const target = area * pct / 100;
        var placed: usize = 0;
        var attempts: usize = 0;
        const max_attempts = target * 3;
        while (placed < target and attempts < max_attempts) : (attempts += 1) {
            const x = rng.intRangeAtMost(usize, 0, self.width - 1);
            const y = rng.intRangeAtMost(usize, 0, self.height - 1);
            if (self.tiles[y * self.width + x] == .grass and !self.near_tc(x, y, tc_clear + 1)) {
                self.tiles[y * self.width + x] = .tree;
                placed += 1;
            }
        }
    }

    fn placeStartGrove(self: *GameMap, allocator: std.mem.Allocator, tc_x: usize, tc_y: usize, tc_clear: usize, rng: std.Random, cfg: *const config.Config) !void {
        const dirs = [_]struct { dx: isize, dy: isize }{
            .{ .dx = 1, .dy = 0 },
            .{ .dx = -1, .dy = 0 },
            .{ .dx = 0, .dy = 1 },
            .{ .dx = 0, .dy = -1 },
        };
        const d = dirs[rng.intRangeAtMost(usize, 0, dirs.len - 1)];
        const offset = tc_clear + cfg.map_gen.start_grove_offset;
        const start_x = @as(isize, @intCast(tc_x)) + d.dx * @as(isize, @intCast(offset));
        const start_y = @as(isize, @intCast(tc_y)) + d.dy * @as(isize, @intCast(offset));
        if (start_x >= 0 and start_y >= 0) {
            const sx: usize = @intCast(start_x);
            const sy: usize = @intCast(start_y);
            if (sx < self.width and sy < self.height) {
                try self.grow_cluster(allocator, sx, sy, .tree, cfg.map_gen.start_grove_count, rng, tc_clear, cfg);
            }
        }
    }

    fn has_path(self: *GameMap, allocator: std.mem.Allocator, x0: usize, y0: usize, x1: usize, y1: usize) bool {
        const map_size = @as(usize, self.width) * @as(usize, self.height);
        const visited = allocator.alloc(bool, map_size) catch return false;
        defer allocator.free(visited);
        const queue = allocator.alloc(unit.Pos, map_size) catch return false;
        defer allocator.free(queue);
        
        for (visited) |*v| v.* = false;

        var head: usize = 0;
        var tail: usize = 0;

        queue[tail] = .{ .x = x0, .y = y0 };
        tail += 1;
        visited[y0 * self.width + x0] = true;

        const dirs = [_]struct { dx: isize, dy: isize }{
            .{ .dx = 0, .dy = -1 }, .{ .dx = 0, .dy = 1 },
            .{ .dx = -1, .dy = 0 }, .{ .dx = 1, .dy = 0 },
        };

        while (head < tail) {
            const cur = queue[head];
            head += 1;
            if (cur.x == x1 and cur.y == y1) return true;
            for (dirs) |d| {
                const next_x = @as(isize, @intCast(cur.x)) + d.dx;
                const next_y = @as(isize, @intCast(cur.y)) + d.dy;
                if (next_x < 0 or next_y < 0) continue;
                const tile_x: usize = @intCast(next_x);
                const tile_y: usize = @intCast(next_y);
                if (tile_x >= self.width or tile_y >= self.height) continue;
                if (visited[tile_y * self.width + tile_x]) continue;
                if (!self.tiles[tile_y * self.width + tile_x].is_walkable()) continue;
                visited[tile_y * self.width + tile_x] = true;
                queue[tail] = .{ .x = tile_x, .y = tile_y };
                tail += 1;
            }
        }
        return false;
    }

    fn carve_corridor(self: *GameMap, x0: usize, y0: usize, x1: usize, y1: usize, cfg: *const config.Config) void {
        var cur_x: isize = @intCast(x0);
        var cur_y: isize = @intCast(y0);
        const end_x: isize = @intCast(x1);
        const end_y: isize = @intCast(y1);

        while (cur_x != end_x) : (cur_x += if (end_x > cur_x) 1 else -1) {
            self.carve_wide(@intCast(cur_x), @intCast(cur_y), cfg.map_gen.corridor_width);
        }
        while (cur_y != end_y) : (cur_y += if (end_y > cur_y) 1 else -1) {
            self.carve_wide(@intCast(cur_x), @intCast(cur_y), cfg.map_gen.corridor_width);
        }
        self.carve_wide(@intCast(end_x), @intCast(end_y), cfg.map_gen.corridor_width);
    }

    fn carve_wide(self: *GameMap, center_x: usize, center_y: usize, width: usize) void {
        for (0..width) |dy| {
            for (0..width) |dx| {
                const x = center_x + dx;
                const y = center_y + dy;
                if (x < self.width and y < self.height) {
                    if (self.tiles[y * self.width + x] != .town_center) {
                        self.tiles[y * self.width + x] = .grass;
                    }
                }
            }
        }
    }

    pub fn deer_count(self: *const GameMap, cfg: *const config.Config) usize {
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

test "is_walkable on Tile" {
    try std.testing.expect(Tile.grass.is_walkable());
    try std.testing.expect(Tile.town_center.is_walkable());
    try std.testing.expect(!Tile.tree.is_walkable());
    try std.testing.expect(!Tile.water.is_walkable());
    try std.testing.expect(!Tile.house.is_walkable());
}

test "is_walkable on GameMap" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m = try GameMap.init(allocator, 99, 80, 40, &cfg);
    defer m.deinit(allocator);
    try std.testing.expect(m.is_walkable(m.player_tc_x, m.player_tc_y));
    try std.testing.expect(!m.is_walkable(80, 0));
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
    try std.testing.expect(m.has_path(allocator, m.player_tc_x, m.player_tc_y, m.enemy_tc_x, m.enemy_tc_y));
}

test "has_path returns false for blocked maps" {
    const allocator = std.testing.allocator;
    const map_size: usize = 10 * 10;
    const tiles = try allocator.alloc(Tile, map_size);
    defer allocator.free(tiles);
    for (tiles) |*t| t.* = .grass;
    var m: GameMap = .{
        .tiles = tiles,
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
    try std.testing.expect(!m.has_path(allocator, 0, 0, 9, 9));
}

test "deer_count scales with map size" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m80 = try GameMap.init(allocator, 1, 80, 40, &cfg);
    defer m80.deinit(allocator);
    var m120 = try GameMap.init(allocator, 1, 120, 50, &cfg);
    defer m120.deinit(allocator);
    try std.testing.expect(m120.deer_count(&cfg) > m80.deer_count(&cfg));
}

test "deer_count minimum is 4" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m = try GameMap.init(allocator, 1, 20, 10, &cfg);
    defer m.deinit(allocator);
    try std.testing.expect(m.deer_count(&cfg) >= 4);
}

test "near_tc detects proximity" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m = try GameMap.init(allocator, 42, 80, 40, &cfg);
    defer m.deinit(allocator);
    try std.testing.expect(m.near_tc(m.player_tc_x, m.player_tc_y, 1));
    try std.testing.expect(!m.near_tc(m.width - 1, m.height - 1, 2));
}

test "init always has path between TCs" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    for (0..20) |seed| {
        var m = try GameMap.init(allocator, seed, 80, 40, &cfg);
        defer m.deinit(allocator);
        try std.testing.expect(m.has_path(allocator, m.player_tc_x, m.player_tc_y, m.enemy_tc_x, m.enemy_tc_y));
    }
}

test "init clears walkable area around TCs" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    var m = try GameMap.init(allocator, 42, 80, 40, &cfg);
    defer m.deinit(allocator);
    const offsets = [_]struct { dx: isize, dy: isize }{
        .{ .dx = 1, .dy = 0 }, .{ .dx = -1, .dy = 0 },
        .{ .dx = 0, .dy = 1 }, .{ .dx = 0, .dy = -1 },
    };
    for (offsets) |o| {
        const nx: isize = @as(isize, @intCast(m.player_tc_x)) + o.dx;
        const ny: isize = @as(isize, @intCast(m.player_tc_y)) + o.dy;
        if (nx >= 0 and ny >= 0) {
            const ux: usize = @intCast(nx);
            const uy: usize = @intCast(ny);
            if (ux < m.width and uy < m.height) {
                try std.testing.expect(m.is_walkable(ux, uy));
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
                try std.testing.expect(m.is_walkable(x, y));
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
