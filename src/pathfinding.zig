const std = @import("std");
const map = @import("map.zig");
const entity = @import("entity.zig");

const Pos = entity.Pos;

const MAP_SIZE = map.WIDTH * map.HEIGHT;

fn idx(x: usize, y: usize) usize {
    return y * map.WIDTH + x;
}

fn heuristic(a: Pos, b: Pos) u32 {
    const dx = @abs(@as(isize, @intCast(a.x)) - @as(isize, @intCast(b.x)));
    const dy = @abs(@as(isize, @intCast(a.y)) - @as(isize, @intCast(b.y)));
    return @intCast(dx + dy);
}

pub fn find_path(m: *const map.GameMap, start: Pos, goal: Pos, out_path: []Pos) ?usize {
    if (start.x == goal.x and start.y == goal.y) return 0;
    if (!m.is_walkable(goal.x, goal.y)) return null;
    if (!m.is_walkable(start.x, start.y)) return null;

    var g_score: [MAP_SIZE]u32 = undefined;
    var f_score: [MAP_SIZE]u32 = undefined;
    var came_from: [MAP_SIZE]?Pos = undefined;
    var open: [MAP_SIZE]Pos = undefined;
    var open_len: usize = 0;
    var closed: [MAP_SIZE]bool = undefined;

    for (&g_score) |*g| g.* = std.math.maxInt(u32);
    for (&f_score) |*f| f.* = std.math.maxInt(u32);
    for (&came_from) |*c| c.* = null;
    for (&closed) |*c| c.* = false;

    const si = idx(start.x, start.y);
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
        var best_f = f_score[idx(open[0].x, open[0].y)];
        for (1..open_len) |i| {
            const f = f_score[idx(open[i].x, open[i].y)];
            if (f < best_f) {
                best_f = f;
                best_i = i;
            }
        }

        const current = open[best_i];

        if (current.x == goal.x and current.y == goal.y) {
            var reconstruct: [MAP_SIZE]Pos = undefined;
            var recon_len: usize = 0;
            var cur = goal;
            while (true) {
                reconstruct[recon_len] = cur;
                recon_len += 1;
                if (cur.x == start.x and cur.y == start.y) break;
                cur = came_from[idx(cur.x, cur.y)].?;
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

        const ci = idx(current.x, current.y);
        closed[ci] = true;

        const cg = g_score[ci];

        for (dirs) |d| {
            const nx = @as(isize, @intCast(current.x)) + d.dx;
            const ny = @as(isize, @intCast(current.y)) + d.dy;
            if (nx < 0 or ny < 0) continue;
            const nux: usize = @intCast(nx);
            const nuy: usize = @intCast(ny);
            if (nux >= map.WIDTH or nuy >= map.HEIGHT) continue;
            if (!m.is_walkable(nux, nuy)) continue;
            const ni = idx(nux, nuy);
            if (closed[ni]) continue;

            const tentative_g = cg + 1;
            if (tentative_g < g_score[ni]) {
                came_from[ni] = current;
                g_score[ni] = tentative_g;
                f_score[ni] = tentative_g + heuristic(.{ .x = nux, .y = nuy }, goal);
                open[open_len] = .{ .x = nux, .y = nuy };
                open_len += 1;
            }
        }
    }

    return null;
}

test "find_path: straight line" {
    var m: map.GameMap = undefined;
    for (&m.tiles) |*row| {
        for (row) |*t| t.* = .grass;
    }
    var path: [256]Pos = undefined;
    const len = find_path(&m, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 5 }, &path) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 5), len);
    try std.testing.expectEqual(@as(usize, 6), path[0].x);
    try std.testing.expectEqual(@as(usize, 10), path[4].x);
}

test "find_path: around obstacle" {
    var m: map.GameMap = undefined;
    for (&m.tiles) |*row| {
        for (row) |*t| t.* = .grass;
    }
    for (0..10) |y| {
        m.tiles[y][5] = .tree;
    }
    var path: [256]Pos = undefined;
    const len = find_path(&m, .{ .x = 3, .y = 5 }, .{ .x = 7, .y = 5 }, &path) orelse unreachable;
    try std.testing.expect(len > 4);
    for (0..len) |i| {
        try std.testing.expect(m.tiles[path[i].y][path[i].x] == .grass);
    }
}

test "find_path: unreachable" {
    var m: map.GameMap = undefined;
    for (&m.tiles) |*row| {
        for (row) |*t| t.* = .grass;
    }
    for (8..13) |y| {
        for (8..13) |x| {
            if (x == 8 or x == 12 or y == 8 or y == 12) {
                m.tiles[y][x] = .water;
            }
        }
    }
    var path: [256]Pos = undefined;
    const result = find_path(&m, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 10 }, &path);
    try std.testing.expect(result == null);
}

test "find_path: start equals goal" {
    var m: map.GameMap = undefined;
    for (&m.tiles) |*row| {
        for (row) |*t| t.* = .grass;
    }
    var path: [256]Pos = undefined;
    const len = find_path(&m, .{ .x = 5, .y = 5 }, .{ .x = 5, .y = 5 }, &path) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 0), len);
}

test "find_path: goal is unwalkable" {
    var m: map.GameMap = undefined;
    for (&m.tiles) |*row| {
        for (row) |*t| t.* = .grass;
    }
    m.tiles[5][10] = .water;
    var path: [256]Pos = undefined;
    const result = find_path(&m, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 5 }, &path);
    try std.testing.expect(result == null);
}
