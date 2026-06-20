const std = @import("std");
const entity = @import("entity.zig");

pub const MAX_MAP_WIDTH: usize = 200;
pub const MAX_MAP_HEIGHT: usize = 100;
pub const TC_CLEAR_RADIUS: usize = 5;
pub const PLAYER_TC_X_PCT: usize = 15;
pub const ENEMY_TC_X_PCT: usize = 85;
pub const SECTOR_SIZE: usize = 20;
pub const BIOME_ROLL_MAX: usize = 99;
pub const TREE_CLUSTER_PROB: usize = 40;
pub const WATER_CLUSTER_THRESH: usize = 48;
pub const TREE_CLUSTER_MIN: usize = 20;
pub const TREE_CLUSTER_AREA_DIV: usize = 60;
pub const WATER_CLUSTER_MIN: usize = 18;
pub const WATER_CLUSTER_AREA_DIV: usize = 70;
pub const TREE_TC_BUFFER: usize = 2;
pub const WATER_TC_BUFFER: usize = 4;
pub const CLUSTER_TC_BUFFER: usize = 1;
pub const CLUSTER_FRONTIER_CAP: usize = 600;
pub const DEER_AREA_DIVISOR: usize = 600;
pub const MIN_DEER: usize = 4;
pub const CORRIDOR_WIDTH: usize = 2;

pub const Tile = enum(u8) {
    grass = ' ',
    tree = 'T',
    water = '~',
    town_center = 'C',
    house = 'H',
    barracks = 'B',

    pub fn glyph(self: Tile) []const u8 {
        return switch (self) {
            .grass => " ",
            .tree => "T",
            .water => "~",
            .town_center => "C",
            .house => "H",
            .barracks => "B",
        };
    }

    pub fn is_walkable(self: Tile) bool {
        return switch (self) {
            .grass, .town_center => true,
            .tree, .water, .house, .barracks => false,
        };
    }

    pub fn label(self: Tile) []const u8 {
        return switch (self) {
            .grass => "Grass",
            .tree => "Forest",
            .water => "Water",
            .town_center => "TC",
            .house => "House",
            .barracks => "Barracks",
        };
    }
};

pub const GameMap = struct {
    tiles: [MAX_MAP_HEIGHT][MAX_MAP_WIDTH]Tile,
    width: u16,
    height: u16,
    player_tc_x: u16,
    player_tc_y: u16,
    enemy_tc_x: u16,
    enemy_tc_y: u16,

    pub fn init(seed: u64, w: u16, h: u16) GameMap {
        const mw: usize = @min(@as(usize, w), MAX_MAP_WIDTH);
        const mh: usize = @min(@as(usize, h), MAX_MAP_HEIGHT);

        const ptx: usize = mw * PLAYER_TC_X_PCT / 100;
        const pty: usize = mh / 2;
        const etx: usize = @max(mw * ENEMY_TC_X_PCT / 100, @as(usize, 1));
        const ety: usize = mh / 2;

        var m: GameMap = .{
            .tiles = undefined,
            .width = @intCast(mw),
            .height = @intCast(mh),
            .player_tc_x = @intCast(ptx),
            .player_tc_y = @intCast(pty),
            .enemy_tc_x = @intCast(etx),
            .enemy_tc_y = @intCast(ety),
        };

        if (m.player_tc_x == m.enemy_tc_x and mw > 2) {
            m.enemy_tc_x = @intCast(mw - 1 - ptx);
        }

        var rng_obj = std.Random.DefaultPrng.init(seed);
        const rng = rng_obj.random();

        for (&m.tiles) |*row| {
            for (row) |*t| t.* = .grass;
        }

        m.clear(m.player_tc_x, m.player_tc_y, TC_CLEAR_RADIUS);
        m.clear(m.enemy_tc_x, m.enemy_tc_y, TC_CLEAR_RADIUS);

        const area = @as(usize, mw) * @as(usize, mh);

        const sectors_x = mw / SECTOR_SIZE + 1;
        const sectors_y = mh / SECTOR_SIZE + 1;

        for (0..sectors_y) |sy| {
            for (0..sectors_x) |sx| {
                const base_x = sx * SECTOR_SIZE + SECTOR_SIZE / 2;
                const base_y = sy * SECTOR_SIZE + SECTOR_SIZE / 2;
                const ox = rng.intRangeAtMost(usize, 0, SECTOR_SIZE / 2);
                const oy = rng.intRangeAtMost(usize, 0, SECTOR_SIZE / 2);
                const seed_x = @min(base_x + ox, mw - 1);
                const seed_y = @min(base_y + oy, mh - 1);

                const roll = rng.intRangeAtMost(usize, 0, BIOME_ROLL_MAX);
                if (roll < TREE_CLUSTER_PROB) {
                    const cluster_size = rng.intRangeAtMost(usize, TREE_CLUSTER_MIN, @max(TREE_CLUSTER_MIN + 1, area / TREE_CLUSTER_AREA_DIV));
                    if (!m.near_tc(seed_x, seed_y, TC_CLEAR_RADIUS + TREE_TC_BUFFER)) {
                        m.grow_cluster(seed_x, seed_y, .tree, cluster_size, rng);
                    }
                } else if (roll < WATER_CLUSTER_THRESH) {
                    const cluster_size = rng.intRangeAtMost(usize, WATER_CLUSTER_MIN, @max(WATER_CLUSTER_MIN + 1, area / WATER_CLUSTER_AREA_DIV));
                    if (!m.near_tc(seed_x, seed_y, TC_CLEAR_RADIUS + WATER_TC_BUFFER)) {
                        m.grow_cluster(seed_x, seed_y, .water, cluster_size, rng);
                    }
                }
            }
        }

        m.tiles[m.player_tc_y][m.player_tc_x] = .town_center;
        m.tiles[m.enemy_tc_y][m.enemy_tc_x] = .town_center;

        if (!m.has_path(m.player_tc_x, m.player_tc_y, m.enemy_tc_x, m.enemy_tc_y)) {
            m.carve_corridor(m.player_tc_x, m.player_tc_y, m.enemy_tc_x, m.enemy_tc_y);
        }

        return m;
    }

    pub fn at(self: *const GameMap, x: usize, y: usize) Tile {
        if (x >= self.width or y >= self.height) return .water;
        return self.tiles[y][x];
    }

    pub fn is_walkable(self: *const GameMap, x: usize, y: usize) bool {
        return self.at(x, y).is_walkable();
    }

    pub fn set(self: *GameMap, x: usize, y: usize, tile: Tile) void {
        if (x >= self.width or y >= self.height) return;
        self.tiles[y][x] = tile;
    }

    fn clear(self: *GameMap, cx: usize, cy: usize, radius: usize) void {
        const y0 = if (cy > radius) cy - radius else 0;
        const y1 = @min(cy + radius + 1, self.height);
        const x0 = if (cx > radius) cx - radius else 0;
        const x1 = @min(cx + radius + 1, self.width);
        for (y0..y1) |y| {
            for (x0..x1) |x| {
                self.tiles[y][x] = .grass;
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

    fn grow_cluster(self: *GameMap, sx: usize, sy: usize, tile: Tile, count: usize, rng: std.Random) void {
        var frontier: [CLUSTER_FRONTIER_CAP]entity.Pos = undefined;
        var fhead: usize = 1;
        var ftail: usize = 0;
        frontier[0] = .{ .x = sx, .y = sy };
        var placed: usize = 0;
        while (placed < count and ftail < fhead) {
            const idx = rng.intRangeAtMost(usize, ftail, fhead - 1);
            const cand = frontier[idx];
            frontier[idx] = frontier[ftail];
            frontier[ftail] = cand;
            ftail += 1;
            if (cand.x < self.width and cand.y < self.height) {
                if (self.tiles[cand.y][cand.x] == .grass and !self.near_tc(cand.x, cand.y, TC_CLEAR_RADIUS + CLUSTER_TC_BUFFER)) {
                    self.tiles[cand.y][cand.x] = tile;
                    placed += 1;
                    const offsets = [_]struct { dx: isize, dy: isize }{
                        .{ .dx = 0, .dy = -1 }, .{ .dx = 0, .dy = 1 },
                        .{ .dx = -1, .dy = 0 }, .{ .dx = 1, .dy = 0 },
                    };
                    for (offsets) |off| {
                        const nx = @as(isize, @intCast(cand.x)) + off.dx;
                        const ny = @as(isize, @intCast(cand.y)) + off.dy;
                        if (nx >= 0 and ny >= 0) {
                            const unx: usize = @intCast(nx);
                            const uny: usize = @intCast(ny);
                            if (unx < self.width and uny < self.height and fhead < frontier.len) {
                                if (self.tiles[uny][unx] == .grass) {
                                    frontier[fhead] = .{ .x = unx, .y = uny };
                                    fhead += 1;
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    fn has_path(self: *const GameMap, x0: usize, y0: usize, x1: usize, y1: usize) bool {
        var visited: [MAX_MAP_HEIGHT][MAX_MAP_WIDTH]bool = @splat(@splat(false));
        var queue: [MAX_MAP_WIDTH * MAX_MAP_HEIGHT]entity.Pos = undefined;
        var head: usize = 0;
        var tail: usize = 0;

        queue[tail] = .{ .x = x0, .y = y0 };
        tail += 1;
        visited[y0][x0] = true;

        const dirs = [_]struct { dx: isize, dy: isize }{
            .{ .dx = 0, .dy = -1 }, .{ .dx = 0, .dy = 1 },
            .{ .dx = -1, .dy = 0 }, .{ .dx = 1, .dy = 0 },
        };

        while (head < tail) {
            const cur = queue[head];
            head += 1;
            if (cur.x == x1 and cur.y == y1) return true;
            for (dirs) |d| {
                const nx = @as(isize, @intCast(cur.x)) + d.dx;
                const ny = @as(isize, @intCast(cur.y)) + d.dy;
                if (nx < 0 or ny < 0) continue;
                const ux: usize = @intCast(nx);
                const uy: usize = @intCast(ny);
                if (ux >= self.width or uy >= self.height) continue;
                if (visited[uy][ux]) continue;
                if (!self.tiles[uy][ux].is_walkable()) continue;
                visited[uy][ux] = true;
                queue[tail] = .{ .x = ux, .y = uy };
                tail += 1;
            }
        }
        return false;
    }

    fn carve_corridor(self: *GameMap, x0: usize, y0: usize, x1: usize, y1: usize) void {
        var cx: isize = @intCast(x0);
        var cy: isize = @intCast(y0);
        const ex: isize = @intCast(x1);
        const ey: isize = @intCast(y1);

        while (cx != ex) : (cx += if (ex > cx) 1 else -1) {
            self.carve_wide(@intCast(cx), @intCast(cy), CORRIDOR_WIDTH);
        }
        while (cy != ey) : (cy += if (ey > cy) 1 else -1) {
            self.carve_wide(@intCast(cx), @intCast(cy), CORRIDOR_WIDTH);
        }
        self.carve_wide(@intCast(ex), @intCast(ey), CORRIDOR_WIDTH);
    }

    fn carve_wide(self: *GameMap, cx: usize, cy: usize, width: usize) void {
        for (0..width) |dy| {
            for (0..width) |dx| {
                const x = cx + dx;
                const y = cy + dy;
                if (x < self.width and y < self.height) {
                    if (self.tiles[y][x] != .town_center) {
                        self.tiles[y][x] = .grass;
                    }
                }
            }
        }
    }

    pub fn deer_count(self: *const GameMap) usize {
        const area = @as(usize, self.width) * @as(usize, self.height);
        return @max(MIN_DEER, area / DEER_AREA_DIVISOR);
    }
};

test "at returns water for out of bounds" {
    var m = GameMap.init(1, 80, 40);
    try std.testing.expectEqual(.water, m.at(80, 0));
    try std.testing.expectEqual(.water, m.at(0, 40));
}

test "at returns tile within bounds" {
    var m = GameMap.init(1, 80, 40);
    try std.testing.expectEqual(.town_center, m.at(m.player_tc_x, m.player_tc_y));
}

test "init places both TCs" {
    const m = GameMap.init(99, 80, 40);
    try std.testing.expectEqual(.town_center, m.at(m.player_tc_x, m.player_tc_y));
    try std.testing.expectEqual(.town_center, m.at(m.enemy_tc_x, m.enemy_tc_y));
}

test "init clears areas around TCs" {
    var m = GameMap.init(99, 80, 40);
    try std.testing.expectEqual(.grass, m.at(m.player_tc_x + 1, m.player_tc_y + 1));
}

test "player TC on left, enemy on right" {
    const m = GameMap.init(99, 80, 40);
    try std.testing.expect(m.player_tc_x < m.enemy_tc_x);
}

test "glyph returns single char" {
    try std.testing.expectEqualStrings("T", Tile.tree.glyph());
    try std.testing.expectEqualStrings(" ", Tile.grass.glyph());
    try std.testing.expectEqualStrings("~", Tile.water.glyph());
    try std.testing.expectEqualStrings("C", Tile.town_center.glyph());
}

test "is_walkable on Tile" {
    try std.testing.expect(Tile.grass.is_walkable());
    try std.testing.expect(Tile.town_center.is_walkable());
    try std.testing.expect(!Tile.tree.is_walkable());
    try std.testing.expect(!Tile.water.is_walkable());
    try std.testing.expect(!Tile.house.is_walkable());
}

test "is_walkable on GameMap" {
    var m = GameMap.init(99, 80, 40);
    try std.testing.expect(m.is_walkable(m.player_tc_x, m.player_tc_y));
    try std.testing.expect(!m.is_walkable(80, 0));
}

test "set changes a tile" {
    var m = GameMap.init(99, 80, 40);
    const tx = m.player_tc_x + 1;
    const ty = m.player_tc_y;
    m.set(tx, ty, .house);
    try std.testing.expectEqual(.house, m.at(tx, ty));
}

test "set ignores out of bounds" {
    var m = GameMap.init(99, 80, 40);
    m.set(80, 0, .house);
    try std.testing.expectEqual(.water, m.at(80, 0));
}

test "path exists between TCs" {
    var m = GameMap.init(42, 80, 40);
    try std.testing.expect(m.has_path(m.player_tc_x, m.player_tc_y, m.enemy_tc_x, m.enemy_tc_y));
}

test "has_path returns false for blocked maps" {
    var m: GameMap = .{
        .tiles = undefined,
        .width = 10,
        .height = 10,
        .player_tc_x = 0,
        .player_tc_y = 0,
        .enemy_tc_x = 9,
        .enemy_tc_y = 9,
    };
    for (&m.tiles) |*row| {
        for (row) |*t| t.* = .grass;
    }
    for (0..10) |y| {
        m.tiles[y][5] = .water;
    }
    try std.testing.expect(!m.has_path(0, 0, 9, 9));
}

test "deer_count scales with map size" {
    var m80 = GameMap.init(1, 80, 40);
    var m120 = GameMap.init(1, 120, 50);
    try std.testing.expect(m120.deer_count() > m80.deer_count());
}

test "deer_count minimum is 4" {
    var m = GameMap.init(1, 20, 10);
    try std.testing.expect(m.deer_count() >= 4);
}

test "near_tc detects proximity" {
    var m = GameMap.init(42, 80, 40);
    try std.testing.expect(m.near_tc(m.player_tc_x, m.player_tc_y, 1));
    try std.testing.expect(!m.near_tc(m.width - 1, m.height - 1, 2));
}

test "init always has path between TCs" {
    for (0..20) |seed| {
        var m = GameMap.init(seed, 80, 40);
        try std.testing.expect(m.has_path(m.player_tc_x, m.player_tc_y, m.enemy_tc_x, m.enemy_tc_y));
    }
}

test "init clears walkable area around TCs" {
    var m = GameMap.init(42, 80, 40);
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
    var m = GameMap.init(42, 120, 50);
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
    var m1 = GameMap.init(1, 80, 40);
    var m2 = GameMap.init(2, 80, 40);
    var diffs: usize = 0;
    for (0..m1.height) |y| {
        for (0..m1.width) |x| {
            if (m1.at(x, y) != m2.at(x, y)) diffs += 1;
        }
    }
    try std.testing.expect(diffs > 0);
}

test "clear radius is large enough for walking" {
    var m = GameMap.init(42, 80, 40);
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
    var m_small = GameMap.init(42, 40, 20);
    var m_large = GameMap.init(42, 160, 80);
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
    var any_water = false;
    for (0..5) |seed| {
        var m = GameMap.init(seed, 120, 50);
        for (0..m.height) |y| {
            for (0..m.width) |x| {
                if (m.at(x, y) == .water) any_water = true;
            }
        }
    }
    try std.testing.expect(any_water);
}
