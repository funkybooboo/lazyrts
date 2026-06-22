const std = @import("std");
const coords = @import("coords.zig");

pub const Pos = coords.Pos;

fn heuristic(a: Pos, b: Pos) u32 {
    const dx = @abs(@as(isize, @intCast(a.x)) - @as(isize, @intCast(b.x)));
    const dy = @abs(@as(isize, @intCast(a.y)) - @as(isize, @intCast(b.y)));
    return @intCast(dx + dy);
}

fn idx(width: usize, x: usize, y: usize) usize {
    return y * width + x;
}

const dirs = coords.dirs4;

pub fn findPath(allocator: std.mem.Allocator, grid: anytype, start: Pos, goal: Pos, out_path: []Pos, blocked: ?[]const Pos) ?usize {
    const width = grid.width;
    if (start.x == goal.x and start.y == goal.y) return 0;
    if (!grid.isWalkable(goal.x, goal.y)) return null;
    if (!grid.isWalkable(start.x, start.y)) return null;
    if (blocked) |b| {
        for (b) |pos| {
            if (pos.x == goal.x and pos.y == goal.y) return null;
        }
    }

    const map_size = @as(usize, width) * @as(usize, grid.height);

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

    const si = idx(width, start.x, start.y);
    g_score[si] = 0;
    f_score[si] = heuristic(start, goal);
    open[0] = start;
    open_len = 1;

    while (open_len > 0) {
        var best_i: usize = 0;
        var best_f = f_score[idx(width, open[0].x, open[0].y)];
        for (1..open_len) |i| {
            const f = f_score[idx(width, open[i].x, open[i].y)];
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
                cur = came_from[idx(width, cur.x, cur.y)].?;
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

        const ci = idx(width, current.x, current.y);
        closed[ci] = true;

        const cg = g_score[ci];

        for (dirs) |d| {
            const next_x = @as(isize, @intCast(current.x)) + d.dx;
            const next_y = @as(isize, @intCast(current.y)) + d.dy;
            if (next_x < 0 or next_y < 0) continue;
            const unit_x: usize = @intCast(next_x);
            const unit_y: usize = @intCast(next_y);
            if (unit_x >= width or unit_y >= grid.height) continue;
            if (!grid.isWalkable(unit_x, unit_y)) continue;

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

            const ni = idx(width, unit_x, unit_y);
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

pub fn hasPath(allocator: std.mem.Allocator, grid: anytype, start: Pos, goal: Pos) bool {
    const width = grid.width;
    if (start.x == goal.x and start.y == goal.y) return true;
    if (!grid.isWalkable(start.x, start.y)) return false;
    if (!grid.isWalkable(goal.x, goal.y)) return false;

    const map_size = @as(usize, width) * @as(usize, grid.height);
    const visited = allocator.alloc(bool, map_size) catch return false;
    defer allocator.free(visited);
    const queue = allocator.alloc(Pos, map_size) catch return false;
    defer allocator.free(queue);

    @memset(visited, false);

    var head: usize = 0;
    var tail: usize = 0;

    queue[tail] = start;
    tail += 1;
    visited[start.y * width + start.x] = true;

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
            if (tile_x >= width or tile_y >= grid.height) continue;
            if (visited[tile_y * width + tile_x]) continue;
            if (!grid.isWalkable(tile_x, tile_y)) continue;
            visited[tile_y * width + tile_x] = true;
            queue[tail] = .{ .x = tile_x, .y = tile_y };
            tail += 1;
        }
    }
    return false;
}

pub fn findNearestReachable(allocator: std.mem.Allocator, grid: anytype, goal: Pos, blocked: ?[]const Pos) ?Pos {
    const width = grid.width;
    const map_size = @as(usize, width) * @as(usize, grid.height);
    const visited = allocator.alloc(bool, map_size) catch return null;
    defer allocator.free(visited);
    const queue = allocator.alloc(Pos, map_size) catch return null;
    defer allocator.free(queue);

    @memset(visited, false);

    var head: usize = 0;
    var tail: usize = 0;

    queue[tail] = goal;
    tail += 1;
    visited[goal.y * width + goal.x] = true;

    while (head < tail) {
        const cur = queue[head];
        head += 1;

        if (grid.isWalkable(cur.x, cur.y)) {
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
            if (tile_x >= width or tile_y >= grid.height) continue;
            if (visited[tile_y * width + tile_x]) continue;
            visited[tile_y * width + tile_x] = true;
            queue[tail] = .{ .x = tile_x, .y = tile_y };
            tail += 1;
        }
    }

    return null;
}

const TestGrid = struct {
    tiles: []Tile,
    width: usize,
    height: usize,

    const Tile = enum { open, wall };

    fn init(allocator: std.mem.Allocator, w: usize, h: usize, fill: Tile) !TestGrid {
        const tiles = try allocator.alloc(Tile, w * h);
        for (tiles) |*t| t.* = fill;
        return .{ .tiles = tiles, .width = w, .height = h };
    }

    fn deinit(self: *TestGrid, allocator: std.mem.Allocator) void {
        allocator.free(self.tiles);
    }

    fn isWalkable(self: *const TestGrid, x: usize, y: usize) bool {
        return self.tiles[y * self.width + x] == .open;
    }

    fn setWall(self: *TestGrid, x: usize, y: usize) void {
        self.tiles[y * self.width + x] = .wall;
    }
};

test "findPath: straight line" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 80, 40, .open);
    defer m.deinit(allocator);
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const len = findPath(allocator, &m, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 5 }, path_buf, null) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 5), len);
    try std.testing.expectEqual(@as(usize, 6), path_buf[0].x);
    try std.testing.expectEqual(@as(usize, 10), path_buf[4].x);
}

test "findPath: around obstacle" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 80, 40, .open);
    defer m.deinit(allocator);
    for (5..35) |y| m.setWall(20, y);
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const len = findPath(allocator, &m, .{ .x = 10, .y = 20 }, .{ .x = 30, .y = 20 }, path_buf, null) orelse unreachable;
    try std.testing.expect(len > 20);
}

test "findPath: unreachable" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 80, 40, .open);
    defer m.deinit(allocator);
    for (8..13) |y| {
        for (8..13) |x| {
            if (x == 8 or x == 12 or y == 8 or y == 12) m.setWall(x, y);
        }
    }
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const result = findPath(allocator, &m, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 10 }, path_buf, null);
    try std.testing.expect(result == null);
}

test "findPath: start equals goal" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 80, 40, .open);
    defer m.deinit(allocator);
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const len = findPath(allocator, &m, .{ .x = 5, .y = 5 }, .{ .x = 5, .y = 5 }, path_buf, null) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 0), len);
}

test "findPath: goal is unwalkable" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 80, 40, .open);
    defer m.deinit(allocator);
    m.setWall(10, 5);
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const result = findPath(allocator, &m, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 5 }, path_buf, null);
    try std.testing.expect(result == null);
}

test "findPath: start is unwalkable" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 80, 40, .open);
    defer m.deinit(allocator);
    m.setWall(5, 5);
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const result = findPath(allocator, &m, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 5 }, path_buf, null);
    try std.testing.expect(result == null);
}

test "findPath: diagonal path" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 80, 40, .open);
    defer m.deinit(allocator);
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const len = findPath(allocator, &m, .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 10 }, path_buf, null) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 20), len);
}

test "findPath: corridor" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 80, 40, .open);
    defer m.deinit(allocator);
    for (0..79) |x| {
        if (x == 40) continue;
        m.setWall(x, 19);
        m.setWall(x, 21);
    }
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const result = findPath(allocator, &m, .{ .x = 10, .y = 20 }, .{ .x = 50, .y = 20 }, path_buf, null);
    try std.testing.expect(result != null);
}

test "findPath: blocked positions" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 80, 40, .open);
    defer m.deinit(allocator);
    const blocked = [_]Pos{ .{ .x = 7, .y = 5 } };
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const result = findPath(allocator, &m, .{ .x = 5, .y = 5 }, .{ .x = 7, .y = 5 }, path_buf, &blocked);
    try std.testing.expect(result == null);
}

test "hasPath: reachable" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 20, 20, .open);
    defer m.deinit(allocator);
    try std.testing.expect(hasPath(allocator, &m, .{ .x = 0, .y = 0 }, .{ .x = 19, .y = 19 }));
}

test "hasPath: blocked by wall" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 20, 20, .open);
    defer m.deinit(allocator);
    for (0..20) |y| m.setWall(10, y);
    try std.testing.expect(!hasPath(allocator, &m, .{ .x = 0, .y = 0 }, .{ .x = 19, .y = 0 }));
}

test "findNearestReachable: returns goal when walkable" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 20, 20, .open);
    defer m.deinit(allocator);
    const near = findNearestReachable(allocator, &m, .{ .x = 10, .y = 10 }, null);
    try std.testing.expectEqual(@as(usize, 10), near.?.x);
    try std.testing.expectEqual(@as(usize, 10), near.?.y);
}

test "findNearestReachable: skips blocked goal" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 20, 20, .open);
    defer m.deinit(allocator);
    const blocked = [_]Pos{ .{ .x = 10, .y = 10 } };
    const near = findNearestReachable(allocator, &m, .{ .x = 10, .y = 10 }, &blocked);
    try std.testing.expect(near != null);
    try std.testing.expect(!((near.?.x == 10) and (near.?.y == 10)));
}
