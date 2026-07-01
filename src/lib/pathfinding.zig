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

pub const Scratch = struct {
    allocator: std.mem.Allocator,
    g_score: []u32 = &.{},
    f_score: []u32 = &.{},
    came_from: []?Pos = &.{},
    open: []Pos = &.{},
    closed: []bool = &.{},
    capacity: usize = 0,
    find_calls: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, map_size: usize) !Scratch {
        var s: Scratch = .{ .allocator = allocator };
        try s.ensure(map_size);
        return s;
    }

    pub fn deinit(self: *Scratch) void {
        if (self.capacity == 0) return;
        self.allocator.free(self.g_score);
        self.allocator.free(self.f_score);
        self.allocator.free(self.came_from);
        self.allocator.free(self.open);
        self.allocator.free(self.closed);
        self.g_score = &.{};
        self.f_score = &.{};
        self.came_from = &.{};
        self.open = &.{};
        self.closed = &.{};
        self.capacity = 0;
    }

    pub fn ensure(self: *Scratch, map_size: usize) !void {
        if (map_size <= self.capacity) return;
        self.deinit();
        self.g_score = try self.allocator.alloc(u32, map_size);
        self.f_score = try self.allocator.alloc(u32, map_size);
        self.came_from = try self.allocator.alloc(?Pos, map_size);
        self.open = try self.allocator.alloc(Pos, map_size);
        self.closed = try self.allocator.alloc(bool, map_size);
        self.capacity = map_size;
    }
};

fn heapPush(heap: []Pos, len: *usize, f: []const u32, width: usize, pos: Pos) void {
    var i = len.*;
    heap[i] = pos;
    len.* += 1;
    while (i > 0) {
        const parent = (i - 1) / 2;
        if (f[idx(width, heap[i].x, heap[i].y)] < f[idx(width, heap[parent].x, heap[parent].y)]) {
            const tmp = heap[i];
            heap[i] = heap[parent];
            heap[parent] = tmp;
            i = parent;
        } else break;
    }
}

fn heapPop(heap: []Pos, len: *usize, f: []const u32, width: usize) Pos {
    const top = heap[0];
    len.* -= 1;
    heap[0] = heap[len.*];
    var i: usize = 0;
    while (true) {
        const l = 2 * i + 1;
        const r = 2 * i + 2;
        var smallest = i;
        if (l < len.* and f[idx(width, heap[l].x, heap[l].y)] < f[idx(width, heap[smallest].x, heap[smallest].y)]) smallest = l;
        if (r < len.* and f[idx(width, heap[r].x, heap[r].y)] < f[idx(width, heap[smallest].x, heap[smallest].y)]) smallest = r;
        if (smallest == i) break;
        const tmp = heap[i];
        heap[i] = heap[smallest];
        heap[smallest] = tmp;
        i = smallest;
    }
    return top;
}

pub fn findPath(scratch: *Scratch, grid: anytype, start: Pos, goal: Pos, out_path: []Pos, blocked: ?[]const Pos) ?usize {
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
    scratch.ensure(map_size) catch return null;
    scratch.find_calls += 1;
    const g = scratch.g_score[0..map_size];
    const f = scratch.f_score[0..map_size];
    const came = scratch.came_from[0..map_size];
    const closed = scratch.closed[0..map_size];
    const heap = scratch.open;

    @memset(g, std.math.maxInt(u32));
    @memset(f, std.math.maxInt(u32));
    @memset(came, @as(?Pos, null));
    @memset(closed, false);

    var open_len: usize = 0;

    const si = idx(width, start.x, start.y);
    g[si] = 0;
    f[si] = heuristic(start, goal);
    heapPush(heap, &open_len, f, width, start);

    while (open_len > 0) {
        const current = heapPop(heap, &open_len, f, width);
        const ci = idx(width, current.x, current.y);

        if (current.x == goal.x and current.y == goal.y) {
            var n: usize = 0;
            var cur = goal;
            while (true) {
                n += 1;
                if (cur.x == start.x and cur.y == start.y) break;
                cur = came[idx(width, cur.x, cur.y)].?;
            }
            const path_len = n - 1;
            if (path_len > out_path.len) return null;
            var ip: usize = path_len;
            cur = goal;
            while (ip > 0) {
                ip -= 1;
                out_path[ip] = cur;
                cur = came[idx(width, cur.x, cur.y)].?;
            }
            return path_len;
        }

        if (closed[ci]) continue;
        closed[ci] = true;

        const cg = g[ci];

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
            if (tentative_g < g[ni]) {
                came[ni] = current;
                g[ni] = tentative_g;
                f[ni] = tentative_g + heuristic(.{ .x = unit_x, .y = unit_y }, goal);
                heapPush(heap, &open_len, f, width, .{ .x = unit_x, .y = unit_y });
            }
        }
    }

    return null;
}

pub fn hasPath(scratch: *Scratch, grid: anytype, start: Pos, goal: Pos) bool {
    const width = grid.width;
    if (start.x == goal.x and start.y == goal.y) return true;
    if (!grid.isWalkable(start.x, start.y)) return false;
    if (!grid.isWalkable(goal.x, goal.y)) return false;

    const map_size = @as(usize, width) * @as(usize, grid.height);
    scratch.ensure(map_size) catch return false;
    const visited = scratch.closed[0..map_size];
    const queue = scratch.open[0..map_size];

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

pub fn findNearestReachable(scratch: *Scratch, grid: anytype, goal: Pos, blocked: ?[]const Pos) ?Pos {
    const width = grid.width;
    const map_size = @as(usize, width) * @as(usize, grid.height);
    scratch.ensure(map_size) catch return null;
    const visited = scratch.closed[0..map_size];
    const queue = scratch.open[0..map_size];

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
            if (!is_blocked) return cur;
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
    var scratch = try Scratch.init(allocator, 80 * 40);
    defer scratch.deinit();
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const len = findPath(&scratch, &m, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 5 }, path_buf, null) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 5), len);
    try std.testing.expectEqual(@as(usize, 6), path_buf[0].x);
    try std.testing.expectEqual(@as(usize, 10), path_buf[4].x);
}

test "findPath: around obstacle" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 80, 40, .open);
    defer m.deinit(allocator);
    for (5..35) |y| m.setWall(20, y);
    var scratch = try Scratch.init(allocator, 80 * 40);
    defer scratch.deinit();
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const len = findPath(&scratch, &m, .{ .x = 10, .y = 20 }, .{ .x = 30, .y = 20 }, path_buf, null) orelse unreachable;
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
    var scratch = try Scratch.init(allocator, 80 * 40);
    defer scratch.deinit();
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const result = findPath(&scratch, &m, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 10 }, path_buf, null);
    try std.testing.expect(result == null);
}

test "findPath: start equals goal" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 80, 40, .open);
    defer m.deinit(allocator);
    var scratch = try Scratch.init(allocator, 80 * 40);
    defer scratch.deinit();
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const len = findPath(&scratch, &m, .{ .x = 5, .y = 5 }, .{ .x = 5, .y = 5 }, path_buf, null) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 0), len);
}

test "findPath: goal is unwalkable" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 80, 40, .open);
    defer m.deinit(allocator);
    m.setWall(10, 5);
    var scratch = try Scratch.init(allocator, 80 * 40);
    defer scratch.deinit();
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const result = findPath(&scratch, &m, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 5 }, path_buf, null);
    try std.testing.expect(result == null);
}

test "findPath: start is unwalkable" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 80, 40, .open);
    defer m.deinit(allocator);
    m.setWall(5, 5);
    var scratch = try Scratch.init(allocator, 80 * 40);
    defer scratch.deinit();
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const result = findPath(&scratch, &m, .{ .x = 5, .y = 5 }, .{ .x = 10, .y = 5 }, path_buf, null);
    try std.testing.expect(result == null);
}

test "findPath: diagonal path" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 80, 40, .open);
    defer m.deinit(allocator);
    var scratch = try Scratch.init(allocator, 80 * 40);
    defer scratch.deinit();
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const len = findPath(&scratch, &m, .{ .x = 0, .y = 0 }, .{ .x = 10, .y = 10 }, path_buf, null) orelse unreachable;
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
    var scratch = try Scratch.init(allocator, 80 * 40);
    defer scratch.deinit();
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const result = findPath(&scratch, &m, .{ .x = 10, .y = 20 }, .{ .x = 50, .y = 20 }, path_buf, null);
    try std.testing.expect(result != null);
}

test "findPath: blocked positions" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 80, 40, .open);
    defer m.deinit(allocator);
    const blocked = [_]Pos{.{ .x = 7, .y = 5 }};
    var scratch = try Scratch.init(allocator, 80 * 40);
    defer scratch.deinit();
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const result = findPath(&scratch, &m, .{ .x = 5, .y = 5 }, .{ .x = 7, .y = 5 }, path_buf, &blocked);
    try std.testing.expect(result == null);
}

test "findPath: optimal on open grid (heap correctness)" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 40, 40, .open);
    defer m.deinit(allocator);
    var scratch = try Scratch.init(allocator, 40 * 40);
    defer scratch.deinit();
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const len = findPath(&scratch, &m, .{ .x = 0, .y = 0 }, .{ .x = 15, .y = 15 }, path_buf, null) orelse unreachable;
    try std.testing.expectEqual(@as(usize, 30), len);
}

test "hasPath: reachable" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 20, 20, .open);
    defer m.deinit(allocator);
    var scratch = try Scratch.init(allocator, 20 * 20);
    defer scratch.deinit();
    try std.testing.expect(hasPath(&scratch, &m, .{ .x = 0, .y = 0 }, .{ .x = 19, .y = 19 }));
}

test "hasPath: blocked by wall" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 20, 20, .open);
    defer m.deinit(allocator);
    for (0..20) |y| m.setWall(10, y);
    var scratch = try Scratch.init(allocator, 20 * 20);
    defer scratch.deinit();
    try std.testing.expect(!hasPath(&scratch, &m, .{ .x = 0, .y = 0 }, .{ .x = 19, .y = 0 }));
}

test "findNearestReachable: returns goal when walkable" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 20, 20, .open);
    defer m.deinit(allocator);
    var scratch = try Scratch.init(allocator, 20 * 20);
    defer scratch.deinit();
    const near = findNearestReachable(&scratch, &m, .{ .x = 10, .y = 10 }, null);
    try std.testing.expectEqual(@as(usize, 10), near.?.x);
    try std.testing.expectEqual(@as(usize, 10), near.?.y);
}

test "findNearestReachable: skips blocked goal" {
    const allocator = std.testing.allocator;
    var m = try TestGrid.init(allocator, 20, 20, .open);
    defer m.deinit(allocator);
    const blocked = [_]Pos{.{ .x = 10, .y = 10 }};
    var scratch = try Scratch.init(allocator, 20 * 20);
    defer scratch.deinit();
    const near = findNearestReachable(&scratch, &m, .{ .x = 10, .y = 10 }, &blocked);
    try std.testing.expect(near != null);
    try std.testing.expect(!((near.?.x == 10) and (near.?.y == 10)));
}

test "Scratch ensure grows and frees cleanly" {
    const allocator = std.testing.allocator;
    var s = try Scratch.init(allocator, 10 * 10);
    s.ensure(80 * 40) catch unreachable;
    try std.testing.expectEqual(@as(usize, 80 * 40), s.capacity);
    s.deinit();
}
