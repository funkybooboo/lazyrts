const std = @import("std");
const unit = @import("../units/unit.zig");
const coords = @import("../lib/coords.zig");
const map = @import("map.zig");
const config = @import("../config.zig");

const GameMap = map.GameMap;
const Tile = map.Tile;
const Pos = coords.Pos;

pub fn generate(allocator: std.mem.Allocator, seed: u64, w: u16, h: u16, cfg: *const config.Config) !GameMap {
    const map_width: usize = @as(usize, w);
    const map_height: usize = @as(usize, h);

    const tiles = try allocator.alloc(Tile, map_width * map_height);
    errdefer allocator.free(tiles);
    const tree_remaining = try allocator.alloc(u16, map_width * map_height);
    errdefer allocator.free(tree_remaining);
    @memset(tree_remaining, 0);

    const player_tc_x_pos: usize = map_width * cfg.map_gen.player_tc_x_pct / 100;
    const player_tc_y_pos: usize = map_height / 2;
    const enemy_tc_x_pos: usize = @max(map_width * cfg.map_gen.enemy_tc_x_pct / 100, @as(usize, 1));
    const enemy_tc_y_pos: usize = map_height / 2;

    var m: GameMap = .{
        .tiles = tiles,
        .tree_remaining = tree_remaining,
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
    clear(&m, m.player_tc_x, m.player_tc_y, tc_clear);
    clear(&m, m.enemy_tc_x, m.enemy_tc_y, tc_clear);

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
                if (!m.nearTc(seed_x, seed_y, tc_clear + cfg.map_gen.tree_tc_buffer)) {
                    try growCluster(&m, allocator, seed_x, seed_y, .tree, cluster_size, rng, tc_clear, cfg);
                }
            } else if (roll < tree_density + water_density) {
                const cluster_min = cfg.map_gen.water_cluster_min;
                const cluster_max = @max(cluster_min + 1, area / cfg.map_gen.water_cluster_max_div);
                const cluster_size = rng.intRangeAtMost(usize, cluster_min, cluster_max);
                if (!m.nearTc(seed_x, seed_y, tc_clear + cfg.map_gen.water_tc_buffer)) {
                    try growCluster(&m, allocator, seed_x, seed_y, .water, cluster_size, rng, tc_clear, cfg);
                }
            }
        }
    }

    // Scattered trees: break up grove monotony
    const scatter_pct = rng.intRangeAtMost(usize, cfg.map_gen.scatter_tree_min, cfg.map_gen.scatter_tree_max);
    if (scatter_pct > 0) {
        scatterTrees(&m, rng, scatter_pct, tc_clear, cfg);
    }

    // Guaranteed starting grove near each TC
    try placeStartGrove(&m, allocator, m.player_tc_x, m.player_tc_y, tc_clear, rng, cfg);
    try placeStartGrove(&m, allocator, m.enemy_tc_x, m.enemy_tc_y, tc_clear, rng, cfg);

    m.set(m.player_tc_x, m.player_tc_y, .town_center);
    m.set(m.enemy_tc_x, m.enemy_tc_y, .town_center);

    if (!hasWalkablePath(&m, allocator, m.player_tc_x, m.player_tc_y, m.enemy_tc_x, m.enemy_tc_y)) {
        carveCorridor(&m, m.player_tc_x, m.player_tc_y, m.enemy_tc_x, m.enemy_tc_y, cfg);
    }

    return m;
}

pub fn hasWalkablePath(m: *const GameMap, allocator: std.mem.Allocator, start_x: usize, start_y: usize, goal_x: usize, goal_y: usize) bool {
    if (!m.isWalkable(start_x, start_y) or !m.isWalkable(goal_x, goal_y)) return false;
    if (start_x == goal_x and start_y == goal_y) return true;

    const map_size = @as(usize, m.width) * @as(usize, m.height);
    const visited = allocator.alloc(bool, map_size) catch return false;
    defer allocator.free(visited);
    const queue = allocator.alloc(coords.Pos, map_size) catch return false;
    defer allocator.free(queue);

    @memset(visited, false);

    var head: usize = 0;
    var tail: usize = 0;

    queue[tail] = .{ .x = start_x, .y = start_y };
    tail += 1;
    visited[start_y * m.width + start_x] = true;

    const dirs = coords.dirs4;

    while (head < tail) {
        const cur = queue[head];
        head += 1;
        if (cur.x == goal_x and cur.y == goal_y) return true;
        for (dirs) |d| {
            const next_x = @as(isize, @intCast(cur.x)) + d.dx;
            const next_y = @as(isize, @intCast(cur.y)) + d.dy;
            if (next_x < 0 or next_y < 0) continue;
            const tile_x: usize = @intCast(next_x);
            const tile_y: usize = @intCast(next_y);
            if (tile_x >= m.width or tile_y >= m.height) continue;
            if (visited[tile_y * m.width + tile_x]) continue;
            if (!m.isWalkable(tile_x, tile_y)) continue;
            visited[tile_y * m.width + tile_x] = true;
            queue[tail] = .{ .x = tile_x, .y = tile_y };
            tail += 1;
        }
    }
    return false;
}

fn clear(m: *GameMap, center_x: usize, center_y: usize, radius: usize) void {
    const y0 = if (center_y > radius) center_y - radius else 0;
    const y1 = @min(center_y + radius + 1, @as(usize, m.height));
    const x0 = if (center_x > radius) center_x - radius else 0;
    const x1 = @min(center_x + radius + 1, @as(usize, m.width));
    for (y0..y1) |y| {
        for (x0..x1) |x| {
            m.tiles[y * m.width + x] = .grass;
        }
    }
}

fn growCluster(m: *GameMap, allocator: std.mem.Allocator, start_x: usize, start_y: usize, tile: Tile, count: usize, rng: std.Random, tc_clear: usize, cfg: *const config.Config) !void {
    const frontier_cap = cfg.map_gen.cluster_frontier_cap;
    const frontier = try allocator.alloc(coords.Pos, frontier_cap);
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
        if (cand.x < m.width and cand.y < m.height) {
            if (m.tiles[cand.y * m.width + cand.x] == .grass and !m.nearTc(cand.x, cand.y, tc_clear + cfg.map_gen.cluster_tc_buffer)) {
                m.tiles[cand.y * m.width + cand.x] = tile;
                if (tile == .tree) m.tree_remaining[cand.y * m.width + cand.x] = cfg.economy.tree_total_yield;
                placed += 1;
    const offsets = coords.dirs4;
                for (offsets) |off| {
                    const next_x = @as(isize, @intCast(cand.x)) + off.dx;
                    const next_y = @as(isize, @intCast(cand.y)) + off.dy;
                    if (next_x >= 0 and next_y >= 0) {
                        const tile_x: usize = @intCast(next_x);
                        const tile_y: usize = @intCast(next_y);
                        if (tile_x < m.width and tile_y < m.height and fhead < frontier.len) {
                            if (m.tiles[tile_y * m.width + tile_x] == .grass) {
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

fn scatterTrees(m: *GameMap, rng: std.Random, pct: usize, tc_clear: usize, cfg: *const config.Config) void {
    const area = @as(usize, m.width) * @as(usize, m.height);
    const target = area * pct / 100;
    var placed: usize = 0;
    var attempts: usize = 0;
    const max_attempts = target * 3;
    while (placed < target and attempts < max_attempts) : (attempts += 1) {
        const x = rng.intRangeAtMost(usize, 0, m.width - 1);
        const y = rng.intRangeAtMost(usize, 0, m.height - 1);
        if (m.tiles[y * m.width + x] == .grass and !m.nearTc(x, y, tc_clear + 1)) {
            m.tiles[y * m.width + x] = .tree;
            m.tree_remaining[y * m.width + x] = cfg.economy.tree_total_yield;
            placed += 1;
        }
    }
}

fn placeStartGrove(m: *GameMap, allocator: std.mem.Allocator, tc_x: usize, tc_y: usize, tc_clear: usize, rng: std.Random, cfg: *const config.Config) !void {
    // Order matters: rng picks by index, drives deterministic mapgen.
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
        if (sx < m.width and sy < m.height) {
            try growCluster(m, allocator, sx, sy, .tree, cfg.map_gen.start_grove_count, rng, tc_clear, cfg);
        }
    }
}

fn carveCorridor(m: *GameMap, x0: usize, y0: usize, x1: usize, y1: usize, cfg: *const config.Config) void {
    var cur_x: isize = @intCast(x0);
    var cur_y: isize = @intCast(y0);
    const end_x: isize = @intCast(x1);
    const end_y: isize = @intCast(y1);

    while (cur_x != end_x) : (cur_x += if (end_x > cur_x) 1 else -1) {
        carveWide(m, @intCast(cur_x), @intCast(cur_y), cfg.map_gen.corridor_width);
    }
    while (cur_y != end_y) : (cur_y += if (end_y > cur_y) 1 else -1) {
        carveWide(m, @intCast(cur_x), @intCast(cur_y), cfg.map_gen.corridor_width);
    }
    carveWide(m, @intCast(end_x), @intCast(end_y), cfg.map_gen.corridor_width);
}

fn carveWide(m: *GameMap, center_x: usize, center_y: usize, width: usize) void {
    for (0..width) |dy| {
        for (0..width) |dx| {
            const x = center_x + dx;
            const y = center_y + dy;
            if (x < m.width and y < m.height) {
                if (m.tiles[y * m.width + x] != .town_center) {
                    m.tiles[y * m.width + x] = .grass;
                }
            }
        }
    }
}
