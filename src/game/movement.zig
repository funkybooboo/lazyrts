const std = @import("std");
const map = @import("map.zig");
const unit = @import("../units/unit.zig");
const coords = @import("../lib/coords.zig");
const lib_spatial = @import("../lib/spatial.zig");
const astar = @import("../lib/pathfinding.zig");
const queries = @import("queries.zig");

const Pos = coords.Pos;
const Unit = unit.Unit;
const GameMap = map.GameMap;

pub fn adjacentWalkable(ctx: queries.Ctx, m: *const GameMap, target: Pos, prefer_near: Pos) ?Pos {
    const dirs = coords.dirs4;
    var best: ?Pos = null;
    var best_d: usize = std.math.maxInt(usize);
    for (dirs) |d| {
        const nx = @as(isize, @intCast(target.x)) + d.dx;
        const ny = @as(isize, @intCast(target.y)) + d.dy;
        if (nx < 0 or ny < 0) continue;
        const ux: usize = @intCast(nx);
        const uy: usize = @intCast(ny);
        if (ux >= m.width or uy >= m.height) continue;
        if (!m.isWalkable(ux, uy)) continue;
        if (queries.occupied(ctx, ux, uy)) continue;
        const dd = coords.manhattan(prefer_near, .{ .x = ux, .y = uy });
        if (dd < best_d) {
            best_d = dd;
            best = .{ .x = ux, .y = uy };
        }
    }
    return best;
}

pub fn pathTo(scratch: *astar.Scratch, ctx: queries.Ctx, m: *const GameMap, units: []Unit, i: usize, goal: Pos) bool {
    return pathToInternal(scratch, ctx, m, units, i, goal, goal);
}

pub fn pathToAdjacent(scratch: *astar.Scratch, ctx: queries.Ctx, m: *const GameMap, units: []Unit, i: usize, target: Pos, approach_from: Pos) bool {
    const adj = adjacentWalkable(ctx, m, target, approach_from) orelse return false;
    return pathToInternal(scratch, ctx, m, units, i, adj, target);
}

fn pathToInternal(scratch: *astar.Scratch, ctx: queries.Ctx, m: *const GameMap, units: []Unit, i: usize, goal: Pos, dest_record: Pos) bool {
    const u = &units[i];
    const start = u.pos();
    if (start.x == goal.x and start.y == goal.y) {
        u.path_len = 0;
        u.path_idx = 0;
        u.dest = dest_record;
        return true;
    }
    var blocked_buf: [256]Pos = undefined;
    const blocked_count = queries.collectBlocked(ctx, &blocked_buf, i);
    const blocked_slice = if (blocked_count > 0) blocked_buf[0..blocked_count] else null;

    var target = goal;
    const len = astar.findPath(scratch, m, start, goal, u.path, blocked_slice) orelse blk: {
        const near = astar.findNearestReachable(scratch, m, goal, blocked_slice) orelse return false;
        target = near;
        break :blk astar.findPath(scratch, m, start, near, u.path, blocked_slice) orelse return false;
    };
    if (len == 0 and !(start.x == goal.x and start.y == goal.y)) return false;
    u.path_len = len;
    u.path_idx = 0;
    u.dest = dest_record;
    return true;
}

pub fn advance(scratch: *astar.Scratch, ctx: queries.Ctx, m: *const GameMap, units: []Unit, i: usize, now: usize, cooldown: usize, index: ?*queries.Index) void {
    const u = &units[i];
    if (u.path_idx >= u.path_len) return;
    const next = u.path[u.path_idx];
    var blocked = false;
    if (ctx.unitAt(next.x, next.y)) |other| {
        if (other != i) blocked = true;
    }
    if (ctx.buildingAt(next.x, next.y) != null) blocked = true;
    if (ctx.wildlifeAt(next.x, next.y) != null) blocked = true;
    if (blocked) {
        if (u.dest) |dest| {
            _ = repathBlocked(scratch, ctx, m, units, i, dest, now, cooldown);
        }
        return;
    }
    const old = u.pos();
    u.step();
    if (index) |idx| idx.moveUnit(i, old, u.pos());
}

pub fn arrived(u: *const Unit, target: Pos) bool {
    return coords.manhattan(u.pos(), target) == 1;
}

pub const RepathResult = enum { wait, ok, fail };

pub fn repathBlocked(scratch: *astar.Scratch, ctx: queries.Ctx, m: *const GameMap, units: []Unit, i: usize, dest: Pos, now: usize, cooldown: usize) RepathResult {
    const u = &units[i];
    if (now - u.last_repath_tick < cooldown) return .wait;
    u.last_repath_tick = now;
    var blocked_buf: [256]Pos = undefined;
    const cnt = queries.collectBlocked(ctx, &blocked_buf, i);
    const bs = if (cnt > 0) blocked_buf[0..cnt] else null;
    if (astar.findPath(scratch, m, u.pos(), dest, u.path, bs)) |new_len| {
        if (new_len > 0) {
            u.path_len = new_len;
            u.path_idx = 0;
            return .ok;
        }
        u.path_len = 0;
        u.path_idx = 0;
        return .fail;
    } else {
        u.path_len = 0;
        u.path_idx = 0;
        return .fail;
    }
}

pub fn isAdjacentTree(m: *const GameMap, u: *const Unit, target: Pos) bool {
    if (m.at(target.x, target.y) != .tree) return false;
    return arrived(u, target);
}

test "pathTo: routes unit around wall" {
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
    for (5..35) |y| m.tiles[y * 80 + 20] = .tree;

    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    const u: Unit = .{ .x = 10, .y = 20, .variant = .worker, .owner = .player, .hp = 50, .path = path_buf };
    var units = [_]Unit{u};
    const ctx: queries.Ctx = .{ .units = &units, .buildings = &[_]@import("../buildings/building.zig").Building{}, .wildlife = &[_]@import("../resources/wildlife.zig").Wildlife{} };
    var scratch = try astar.Scratch.init(allocator, 80 * 40);
    defer scratch.deinit();

    try std.testing.expect(pathTo(&scratch, ctx, &m, &units, 0, .{ .x = 30, .y = 20 }));
    try std.testing.expect(units[0].path_len > 20);
}

test "arrived: true when adjacent" {
    const path_buf = try std.testing.allocator.alloc(Pos, 1);
    defer std.testing.allocator.free(path_buf);
    const u: Unit = .{ .x = 5, .y = 5, .variant = .worker, .owner = .player, .hp = 50, .path = path_buf };
    try std.testing.expect(arrived(&u, .{ .x = 5, .y = 6 }));
    try std.testing.expect(arrived(&u, .{ .x = 6, .y = 5 }));
}

test "arrived: false when not adjacent" {
    const path_buf = try std.testing.allocator.alloc(Pos, 1);
    defer std.testing.allocator.free(path_buf);
    const u: Unit = .{ .x = 5, .y = 5, .variant = .worker, .owner = .player, .hp = 50, .path = path_buf };
    try std.testing.expect(!arrived(&u, .{ .x = 5, .y = 5 }));
    try std.testing.expect(!arrived(&u, .{ .x = 7, .y = 5 }));
}

test "repathBlocked: cooldown returns wait without re-pathing" {
    const allocator = std.testing.allocator;
    const map_size: usize = 20 * 20;
    const tiles = try allocator.alloc(map.Tile, map_size);
    defer allocator.free(tiles);
    for (tiles) |*t| t.* = .grass;
    var m: map.GameMap = .{
        .tiles = tiles,
        .tree_remaining = &[_]u16{},
        .width = 20,
        .height = 20,
        .player_tc_x = 2,
        .player_tc_y = 10,
        .enemy_tc_x = 17,
        .enemy_tc_y = 10,
    };
    const path_buf = try allocator.alloc(Pos, 256);
    defer allocator.free(path_buf);
    var units = [_]Unit{
        .{ .x = 5, .y = 10, .variant = .worker, .owner = .player, .hp = 50, .path = path_buf, .dest = .{ .x = 15, .y = 10 } },
        .{ .x = 6, .y = 10, .variant = .worker, .owner = .player, .hp = 50, .path = try allocator.alloc(Pos, 1) },
    };
    defer allocator.free(units[1].path);
    const ctx: queries.Ctx = .{ .units = &units, .buildings = &[_]@import("../buildings/building.zig").Building{}, .wildlife = &[_]@import("../resources/wildlife.zig").Wildlife{} };
    var scratch = try astar.Scratch.init(allocator, 20 * 20);
    defer scratch.deinit();

    const r1 = repathBlocked(&scratch, ctx, &m, &units, 0, .{ .x = 15, .y = 10 }, 100, 3);
    try std.testing.expect(r1 == .ok or r1 == .fail);
    try std.testing.expectEqual(@as(usize, 100), units[0].last_repath_tick);
    // same tick-window -> wait, no new re-path
    const r2 = repathBlocked(&scratch, ctx, &m, &units, 0, .{ .x = 15, .y = 10 }, 101, 3);
    try std.testing.expectEqual(RepathResult.wait, r2);
    // past cooldown -> re-path again
    const r3 = repathBlocked(&scratch, ctx, &m, &units, 0, .{ .x = 15, .y = 10 }, 104, 3);
    try std.testing.expect(r3 == .ok or r3 == .fail);
    try std.testing.expectEqual(@as(usize, 104), units[0].last_repath_tick);
}
