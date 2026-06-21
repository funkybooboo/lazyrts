const std = @import("std");
const map = @import("map.zig");
const unit = @import("unit.zig");

const Pos = unit.Pos;

fn idx(m: *const map.GameMap, x: usize, y: usize) usize {
    return y * m.width + x;
}

fn heuristic(a: Pos, b: Pos) u32 {
    const dx = @abs(@as(isize, @intCast(a.x)) - @as(isize, @intCast(b.x)));
    const dy = @abs(@as(isize, @intCast(a.y)) - @as(isize, @intCast(b.y)));
    return @intCast(dx + dy);
}

pub fn find_path(allocator: std.mem.Allocator, m: *const map.GameMap, start: Pos, goal: Pos, out_path: []Pos, blocked: ?[]const Pos) ?usize {
    if (start.x == goal.x and start.y == goal.y) return 0;
    if (!m.is_walkable(goal.x, goal.y)) return null;
    if (!m.is_walkable(start.x, start.y)) return null;
    if (blocked) |b| {
        for (b) |pos| {
            if (pos.x == goal.x and pos.y == goal.y) return null;
        }
    }

    const map_size = @as(usize, m.width) * @as(usize, m.height);

    const g_score = allocator.alloc(u32, map_size) catch return null;
    defer allocator.free(g_score);
    const f_score = allocator.alloc(u32, map_size) catch return null;
    defer allocator.free(f_score);
    const came_from = allocator.alloc(?Pos, map_size) catch return null;
    defer allocator.free(came_from);
    const open = allocator.alloc(Pos, map_size) catch return null;
    defer allocator.free(open);
    const closed = allocator.alloc(bool, map_size) catch return null;
    defer allocator.free(closed);

    @memset(g_score, std.math.maxInt(u32));
    @memset(f_score, std.math.maxInt(u32));
    @memset(came_from, @as(?Pos, null));
    @memset(closed, false);

    var open_len: usize = 0;

    const si = idx(m, start.x, start.y);
    g_score[si] = 0;
    f_score[si] = heuristic(start, goal);
    open[0] = start;
    open_len = 1;

    const dirs = [_]struct { dx: isize, dy: isize }{
        .{ .dx = 0, .dy = -1 },
        .{ .dx = 0, .dy = 1 },
        .{ .dx = -1, .dy = 0 },
        .{ .dx = 1, .dy = 0 },
    };

    while (open_len > 0) {
        var best_i: usize = 0;
        var best_f = f_score[idx(m, open[0].x, open[0].y)];
        for (1..open_len) |i| {
            const f = f_score[idx(m, open[i].x, open[i].y)];
            if (f < best_f) {
                best_f = f;
                best_i = i;
            }
        }

        const current = open[best_i];

        if (current.x == goal.x and current.y == goal.y) {
            const reconstruct = allocator.alloc(Pos, map_size) catch return null;
            defer allocator.free(reconstruct);
            var recon_len: usize = 0;
            var cur = goal;
            while (true) {
                reconstruct[recon_len] = cur;
                recon_len += 1;
                if (cur.x == start.x and cur.y == start.y) break;
                cur = came_from[idx(m, cur.x, cur.y)].?;
            }
            const path_len = recon_len - 1;
            if (path_len > out_path.len) return null;
            for (0..path_len) |i| {
                out_path[i] = reconstruct[recon_len - 2 - i];
            }
            return path_len;
        }

        open[best_i] = open[open_len - 1];
        open_len -= 1;

        const ci = idx(m, current.x, current.y);
        closed[ci] = true;

        const cg = g_score[ci];

        for (dirs) |d| {
            const next_x = @as(isize, @intCast(current.x)) + d.dx;
            const next_y = @as(isize, @intCast(current.y)) + d.dy;
            if (next_x < 0 or next_y < 0) continue;
            const unit_x: usize = @intCast(next_x);
            const unit_y: usize = @intCast(next_y);
            if (unit_x >= m.width or unit_y >= m.height) continue;
            if (!m.is_walkable(unit_x, unit_y)) continue;
            
            // Check if this position is blocked
            var is_blocked = false;
            if (blocked) |b| {
                for (b) |pos| {
                    if (pos.x == unit_x and pos.y == unit_y) {
                        is_blocked = true;
                        break;
                    }
                }
            }
            if (is_blocked) continue;
            
            const ni = idx(m, unit_x, unit_y);
            if (closed[ni]) continue;

            const tentative_g = cg + 1;
            if (tentative_g < g_score[ni]) {
                came_from[ni] = current;
                g_score[ni] = tentative_g;
                f_score[ni] = tentative_g + heuristic(.{ .x = unit_x, .y = unit_y }, goal);
                open[open_len] = .{ .x = unit_x, .y = unit_y };
                open_len += 1;
            }
        }
    }

    return null;
}

pub fn has_path(allocator: std.mem.Allocator, m: *const map.GameMap, start: Pos, goal: Pos) bool {
    if (start.x == goal.x and start.y == goal.y) return true;
    if (!m.is_walkable(start.x, start.y)) return false;
    if (!m.is_walkable(goal.x, goal.y)) return false;

    const map_size = @as(usize, m.width) * @as(usize, m.height);
    const visited = allocator.alloc(bool, map_size) catch return false;
    defer allocator.free(visited);
    const queue = allocator.alloc(Pos, map_size) catch return false;
    defer allocator.free(queue);

    @memset(visited, false);

    var head: usize = 0;
    var tail: usize = 0;

    queue[tail] = start;
    tail += 1;
    visited[start.y * m.width + start.x] = true;

    const dirs = [_]struct { dx: isize, dy: isize }{
        .{ .dx = 0, .dy = -1 }, .{ .dx = 0, .dy = 1 },
        .{ .dx = -1, .dy = 0 }, .{ .dx = 1, .dy = 0 },
    };

    while (head < tail) {
        const cur = queue[head];
        head += 1;
        if (cur.x == goal.x and cur.y == goal.y) return true;
        for (dirs) |d| {
            const next_x = @as(isize, @intCast(cur.x)) + d.dx;
            const next_y = @as(isize, @intCast(cur.y)) + d.dy;
            if (next_x < 0 or next_y < 0) continue;
            const tile_x: usize = @intCast(next_x);
            const tile_y: usize = @intCast(next_y);
            if (tile_x >= m.width or tile_y >= m.height) continue;
            if (visited[tile_y * m.width + tile_x]) continue;
            if (!m.is_walkable(tile_x, tile_y)) continue;
            visited[tile_y * m.width + tile_x] = true;
            queue[tail] = .{ .x = tile_x, .y = tile_y };
            tail += 1;
        }
    }
    return false;
}

pub fn find_nearest_reachable(allocator: std.mem.Allocator, m: *const map.GameMap, goal: Pos, blocked: ?[]const Pos) ?Pos {
    const map_size = @as(usize, m.width) * @as(usize, m.height);
    const visited = allocator.alloc(bool, map_size) catch return null;
    defer allocator.free(visited);
    const queue = allocator.alloc(Pos, map_size) catch return null;
    defer allocator.free(queue);

    @memset(visited, false);

    var head: usize = 0;
    var tail: usize = 0;

    queue[tail] = goal;
    tail += 1;
    visited[goal.y * m.width + goal.x] = true;

    const dirs = [_]struct { dx: isize, dy: isize }{
        .{ .dx = 0, .dy = -1 }, .{ .dx = 0, .dy = 1 },
        .{ .dx = -1, .dy = 0 }, .{ .dx = 1, .dy = 0 },
    };

    while (head < tail) {
        const cur = queue[head];
        head += 1;

        if (m.is_walkable(cur.x, cur.y)) {
            var is_blocked = false;
            if (blocked) |b| {
                for (b) |pos| {
                    if (pos.x == cur.x and pos.y == cur.y) {
                        is_blocked = true;
                        break;
                    }
                }
            }
            if (!is_blocked) {
                return cur;
            }
        }

        for (dirs) |d| {
            const next_x = @as(isize, @intCast(cur.x)) + d.dx;
            const next_y = @as(isize, @intCast(cur.y)) + d.dy;
            if (next_x < 0 or next_y < 0) continue;
            const tile_x: usize = @intCast(next_x);
            const tile_y: usize = @intCast(next_y);
            if (tile_x >= m.width or tile_y >= m.height) continue;
            if (visited[tile_y * m.width + tile_x]) continue;
            visited[tile_y * m.width + tile_x] = true;
            queue[tail] = .{ .x = tile_x, .y = tile_y };
            tail += 1;
        }
    }

    return null;
}

test "find_path: straight line" {
    const allocator = std.testing.allocator;
    const map_size: usize = 80 * 40;
    const tiles = try allocator.alloc(map.Tile, map_size);
    defer allocator.free(tiles);
    for (tiles) |*t| t.* = .grass;
    const m: map.GameMap = .{
        .tiles = tiles,
        .tree_remaining = &[_]u16{},
        .width = 80,
        .height = 40,
        .player_tc_x = 12,
        .player_tc_y = 20,
        .enemy_tc_x = 68,
        .enemy_tc_y = 20,
    };
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const len = find_path(allocator, &m, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 5 }, path_buf, null) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 5), len);
    try std.testing.expectEqual(@as(usize, 6), path_buf[0].x);
    try std.testing.expectEqual(@as(usize, 10), path_buf[4].x);
}

test "find_path: around obstacle" {
    const allocator = std.testing.allocator;
    const map_size: usize = 80 * 40;
    const tiles = try allocator.alloc(map.Tile, map_size);
    defer allocator.free(tiles);
    for (tiles) |*t| t.* = .grass;
    var m: map.GameMap = .{
        .tiles = tiles,
        .tree_remaining = &[_]u16{},
        .width = 80,
        .height = 40,
        .player_tc_x = 12,
        .player_tc_y = 20,
        .enemy_tc_x = 68,
        .enemy_tc_y = 20,
    };
    for (5..35) |y| {
        m.tiles[y * 80 + 20] = .tree;
    }
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const len = find_path(allocator, &m, .{ .x = 10, .y = 20 }, .{ .x = 30, .y = 20 }, path_buf, null) orelse unreachable;
    try std.testing.expect(len > 20);
}

test "find_path: unreachable" {
    const allocator = std.testing.allocator;
    const map_size: usize = 80 * 40;
    const tiles = try allocator.alloc(map.Tile, map_size);
    defer allocator.free(tiles);
    for (tiles) |*t| t.* = .grass;
    var m: map.GameMap = .{
        .tiles = tiles,
        .tree_remaining = &[_]u16{},
        .width = 80,
        .height = 40,
        .player_tc_x = 12,
        .player_tc_y = 20,
        .enemy_tc_x = 68,
        .enemy_tc_y = 20,
    };
    for (8..13) |y| {
        for (8..13) |x| {
            if (x == 8 or x == 12 or y == 8 or y == 12) {
                m.tiles[y * 80 + x] = .water;
            }
        }
    }
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const result = find_path(allocator, &m, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 10 }, path_buf, null);
    try std.testing.expect(result == null);
}

test "find_path: start equals goal" {
    const allocator = std.testing.allocator;
    const map_size: usize = 80 * 40;
    const tiles = try allocator.alloc(map.Tile, map_size);
    defer allocator.free(tiles);
    for (tiles) |*t| t.* = .grass;
    const m: map.GameMap = .{
        .tiles = tiles,
        .tree_remaining = &[_]u16{},
        .width = 80,
        .height = 40,
        .player_tc_x = 12,
        .player_tc_y = 20,
        .enemy_tc_x = 68,
        .enemy_tc_y = 20,
    };
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const len = find_path(allocator, &m, .{ .x = 5, .y = 5 }, .{ .x = 5, .y = 5 }, path_buf, null) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 0), len);
}

test "find_path: goal is unwalkable" {
    const allocator = std.testing.allocator;
    const map_size: usize = 80 * 40;
    const tiles = try allocator.alloc(map.Tile, map_size);
    defer allocator.free(tiles);
    for (tiles) |*t| t.* = .grass;
    var m: map.GameMap = .{
        .tiles = tiles,
        .tree_remaining = &[_]u16{},
        .width = 80,
        .height = 40,
        .player_tc_x = 12,
        .player_tc_y = 20,
        .enemy_tc_x = 68,
        .enemy_tc_y = 20,
    };
    m.tiles[5 * 80 + 10] = .water;
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const result = find_path(allocator, &m, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 5 }, path_buf, null);
    try std.testing.expect(result == null);
}

test "find_path: start is unwalkable" {
    const allocator = std.testing.allocator;
    const map_size: usize = 80 * 40;
    const tiles = try allocator.alloc(map.Tile, map_size);
    defer allocator.free(tiles);
    for (tiles) |*t| t.* = .grass;
    var m: map.GameMap = .{
        .tiles = tiles,
        .tree_remaining = &[_]u16{},
        .width = 80,
        .height = 40,
        .player_tc_x = 12,
        .player_tc_y = 20,
        .enemy_tc_x = 68,
        .enemy_tc_y = 20,
    };
    m.tiles[5 * 80 + 5] = .water;
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const result = find_path(allocator, &m, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 5 }, path_buf, null);
    try std.testing.expect(result == null);
}

test "find_path: diagonal path" {
    const allocator = std.testing.allocator;
    const map_size: usize = 80 * 40;
    const tiles = try allocator.alloc(map.Tile, map_size);
    defer allocator.free(tiles);
    for (tiles) |*t| t.* = .grass;
    const m: map.GameMap = .{
        .tiles = tiles,
        .tree_remaining = &[_]u16{},
        .width = 80,
        .height = 40,
        .player_tc_x = 12,
        .player_tc_y = 20,
        .enemy_tc_x = 68,
        .enemy_tc_y = 20,
    };
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const len = find_path(allocator, &m, .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 10 }, path_buf, null) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 20), len);
}

test "find_path: corridor" {
    const allocator = std.testing.allocator;
    const map_size: usize = 80 * 40;
    const tiles = try allocator.alloc(map.Tile, map_size);
    defer allocator.free(tiles);
    for (tiles) |*t| t.* = .grass;
    var m: map.GameMap = .{
        .tiles = tiles,
        .tree_remaining = &[_]u16{},
        .width = 80,
        .height = 40,
        .player_tc_x = 12,
        .player_tc_y = 20,
        .enemy_tc_x = 68,
        .enemy_tc_y = 20,
    };
    for (0..79) |x| {
        if (x == 40) continue;
        m.tiles[19 * 80 + x] = .tree;
        m.tiles[21 * 80 + x] = .tree;
    }
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const result = find_path(allocator, &m, .{ .x = 10, .y = 20 }, .{ .x = 50, .y = 20 }, path_buf, null);
    try std.testing.expect(result != null);
}

test "find_path: blocked positions" {
    const allocator = std.testing.allocator;
    const map_size: usize = 80 * 40;
    const tiles = try allocator.alloc(map.Tile, map_size);
    defer allocator.free(tiles);
    for (tiles) |*t| t.* = .grass;
    const m: map.GameMap = .{
        .tiles = tiles,
        .tree_remaining = &[_]u16{},
        .width = 80,
        .height = 40,
        .player_tc_x = 12,
        .player_tc_y = 20,
        .enemy_tc_x = 68,
        .enemy_tc_y = 20,
    };
    const blocked = [_]Pos{ .{ .x = 7, .y = 5 } };
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const result = find_path(allocator, &m, .{ .x = 5, .y = 5 }, .{ .x = 7, .y = 5 }, path_buf, &blocked);
    try std.testing.expect(result == null);
}
