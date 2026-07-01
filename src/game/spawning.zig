const std = @import("std");
const state = @import("state.zig");
const unit = @import("../units/unit.zig");
const coords = @import("../lib/coords.zig");
const lib_spatial = @import("../lib/spatial.zig");
const building = @import("../buildings/building.zig");
const wildlife = @import("../resources/wildlife.zig");
const queries = @import("queries.zig");
const movement = @import("movement.zig");
const config = @import("../config.zig");
const selection = @import("selection.zig");
const notify = @import("notify.zig");

const State = state.State;

pub fn initStartingBuildings(s: *State) !void {
    const starting_buildings = [_]struct { tc_x: usize, tc_y: usize, owner: unit.Owner }{
        .{ .tc_x = s.world.player_tc_x, .tc_y = s.world.player_tc_y, .owner = .player },
        .{ .tc_x = s.world.enemy_tc_x, .tc_y = s.world.enemy_tc_y, .owner = .enemy },
    };
    for (starting_buildings, 0..) |def, i| {
        s.buildings[i] = .{
            .x = def.tc_x,
            .y = def.tc_y,
            .variant = .town_center,
            .owner = def.owner,
            .hp = building.maxHp(.town_center, s.cfg),
        };
        s.spatial_index.putBuilding(i, .{ .x = def.tc_x, .y = def.tc_y });
    }
    s.building_count = starting_buildings.len;
}

pub fn placeStartingFarm(s: *State) !void {
    const tc_x = s.world.player_tc_x;
    const tc_y = s.world.player_tc_y;
    const offsets = [_]struct { dx: isize, dy: isize }{
        .{ .dx = 3, .dy = 0 }, .{ .dx = -3, .dy = 0 },
        .{ .dx = 0, .dy = 3 }, .{ .dx = 0, .dy = -3 },
        .{ .dx = 4, .dy = 0 }, .{ .dx = -4, .dy = 0 },
        .{ .dx = 0, .dy = 4 }, .{ .dx = 0, .dy = -4 },
    };
    for (offsets) |o| {
        const fx = @as(isize, @intCast(tc_x)) + o.dx;
        const fy = @as(isize, @intCast(tc_y)) + o.dy;
        if (fx < 0 or fy < 0) continue;
        const ux: usize = @intCast(fx);
        const uy: usize = @intCast(fy);
        if (ux >= s.world.width or uy >= s.world.height) continue;
        if (!s.world.isWalkable(ux, uy)) continue;
        if (queries.occupied(s.spatialCtx(), ux, uy)) continue;
        if (s.building_count >= s.cfg.entity_limits.max_buildings) return;
        s.buildings[s.building_count] = .{
            .x = ux,
            .y = uy,
            .variant = .{ .farm = .{ .food_remaining = s.cfg.economy.farm_yield_total } },
            .owner = .player,
            .hp = building.maxHp(.farm, s.cfg),
        };
        s.spatial_index.putBuilding(s.building_count, .{ .x = ux, .y = uy });
        s.building_count += 1;
        return;
    }
}

pub fn initStartingWorkers(s: *State) !void {
    const starting_order = [_]struct { cx: usize, cy: usize, owner: unit.Owner }{
        .{ .cx = s.world.player_tc_x, .cy = s.world.player_tc_y, .owner = .player },
        .{ .cx = s.world.player_tc_x, .cy = s.world.player_tc_y, .owner = .player },
        .{ .cx = s.world.enemy_tc_x, .cy = s.world.enemy_tc_y, .owner = .enemy },
        .{ .cx = s.world.enemy_tc_x, .cy = s.world.enemy_tc_y, .owner = .enemy },
    };
    for (starting_order, 0..) |def, i| {
        const sp = findSpawn(s, def.cx, def.cy) orelse continue;
        s.units[i] = .{
            .x = sp.x,
            .y = sp.y,
            .variant = .worker,
            .owner = def.owner,
            .hp = unit.maxHp(.worker, s.cfg),
        };
        s.spatial_index.putUnit(i, sp);
        s.unit_count = i + 1;
    }
}

pub fn allocateUnitPaths(s: *State) !void {
    for (0..s.unit_count) |i| {
        s.units[i].path = s.allocator.alloc(coords.Pos, s.cfg.entity_limits.max_path) catch |e| {
            for (0..i) |j| s.allocator.free(s.units[j].path);
            return e;
        };
    }
}

pub fn spawnDeer(s: *State) void {
    var rng = std.Random.DefaultPrng.init(s.tick_count + s.cfg.deer.spawn_seed_offset);
    const rand = rng.random();

    const tc_positions = [_]struct { x: usize, y: usize }{
        .{ .x = s.world.player_tc_x, .y = s.world.player_tc_y },
        .{ .x = s.world.enemy_tc_x, .y = s.world.enemy_tc_y },
    };

    for (tc_positions) |tc| {
        placeHerdNear(s, rand, tc.x, tc.y, s.cfg.deer.herd_size, s.cfg.deer.tc_herd_offset, s.cfg.deer.herd_radius);
    }

    const herds = s.cfg.deer.scatter_herd_count;
    const herd_size = s.cfg.deer.herd_size;
    const radius = s.cfg.deer.herd_radius;
    const min_dist = s.cfg.deer.herd_min_spacing;
    var centers: [64]coords.Pos = undefined;
    var center_count: usize = 0;
    centers[0] = .{ .x = s.world.player_tc_x, .y = s.world.player_tc_y };
    centers[1] = .{ .x = s.world.enemy_tc_x, .y = s.world.enemy_tc_y };
    center_count = 2;
    var h: usize = 0;
    var tries: usize = 0;
    while (h < herds and tries < herds * 8) : (tries += 1) {
        const cx = rand.intRangeAtMost(usize, 0, s.world.width -| 1);
        const cy = rand.intRangeAtMost(usize, 0, s.world.height -| 1);
        var too_close = false;
        for (0..center_count) |ci| {
            const c = centers[ci];
            const dx = if (cx > c.x) cx - c.x else c.x - cx;
            const dy = if (cy > c.y) cy - c.y else c.y - cy;
            if (dx + dy < min_dist) {
                too_close = true;
                break;
            }
        }

        if (too_close) continue;
        const placed = placeCluster(s, rand, cx, cy, herd_size, radius, true);
        if (placed > 0) {
            centers[center_count] = .{ .x = cx, .y = cy };
            center_count += 1;
            h += 1;
        }
    }
}

fn placeHerdNear(s: *State, rand: std.Random, tc_x: usize, tc_y: usize, size: usize, offset: usize, radius: usize) void {
    // Order matters: rng picks by index, drives deterministic deer placement.
    const dirs = [_]struct { dx: isize, dy: isize }{
        .{ .dx = 1, .dy = 0 }, .{ .dx = -1, .dy = 0 },
        .{ .dx = 0, .dy = 1 }, .{ .dx = 0, .dy = -1 },
    };
    const d = dirs[rand.intRangeAtMost(usize, 0, dirs.len - 1)];
    const cx: isize = @as(isize, @intCast(tc_x)) + d.dx * @as(isize, @intCast(offset));
    const cy: isize = @as(isize, @intCast(tc_y)) + d.dy * @as(isize, @intCast(offset));
    if (cx < 0 or cy < 0) return;
    const ux: usize = @intCast(cx);
    const uy: usize = @intCast(cy);
    if (ux >= s.world.width or uy >= s.world.height) return;
    _ = placeCluster(s, rand, ux, uy, size, radius, false);
}

fn placeCluster(s: *State, rand: std.Random, cx: usize, cy: usize, size: usize, radius: usize, avoid_tc: bool) usize {
    var placed: usize = 0;
    var attempts: usize = 0;
    while (placed < size and attempts < size * 8) : (attempts += 1) {
        const dx = rand.intRangeAtMost(usize, 0, radius * 2);
        const dy = rand.intRangeAtMost(usize, 0, radius * 2);
        const ex: isize = @as(isize, @intCast(cx)) + @as(isize, @intCast(dx)) - @as(isize, @intCast(radius));
        const ey: isize = @as(isize, @intCast(cy)) + @as(isize, @intCast(dy)) - @as(isize, @intCast(radius));
        if (ex < 0 or ey < 0) continue;
        const fx: usize = @intCast(ex);
        const fy: usize = @intCast(ey);
        if (fx >= s.world.width or fy >= s.world.height) continue;
        if (!s.world.isWalkable(fx, fy) or queries.occupied(s.spatialCtx(), fx, fy)) continue;
        if (avoid_tc and s.world.nearTc(fx, fy, s.cfg.deer.scatter_min_dist)) continue;
        if (spawnDeerInHerd(s, fx, fy, cx, cy)) placed += 1;
    }
    return placed;
}

fn spawnDeerInHerd(s: *State, x: usize, y: usize, cx: usize, cy: usize) bool {
    if (!spawnWildlife(s, .deer, x, y)) return false;
    const n = &s.wildlife[s.wildlife_count - 1];
    n.deer.herd_cx = cx;
    n.deer.herd_cy = cy;
    n.deer.herd_radius = s.cfg.deer.herd_wander_radius;
    return true;
}

pub fn spawnWildlife(s: *State, kind: wildlife.Kind, x: usize, y: usize) bool {
    if (s.wildlife_count >= s.cfg.entity_limits.max_wildlife) return false;
    s.wildlife[s.wildlife_count] = switch (kind) {
        .deer => .{ .deer = .{
            .x = x,
            .y = y,
            .hp = wildlife.maxHp(kind, s.cfg),
            .food_remaining = wildlife.maxFood(kind, s.cfg),
        } },
    };
    s.spatial_index.putWildlife(s.wildlife_count, .{ .x = x, .y = y });
    s.wildlife_count += 1;
    return true;
}

pub fn spawnUnit(s: *State, kind: unit.UnitKind, owner: unit.Owner, center_x: usize, center_y: usize) bool {
    if (s.unit_count >= s.cfg.entity_limits.max_units) return false;
    if (owner == .player and state.playerPop(s) >= state.playerPopCap(s)) return false;

    const spawn = findSpawn(s, center_x, center_y) orelse return false;

    const path_buf = s.allocator.alloc(coords.Pos, s.cfg.entity_limits.max_path) catch return false;
    s.units[s.unit_count] = .{
        .x = spawn.x,
        .y = spawn.y,
        .variant = unit.variantOf(kind),
        .owner = owner,
        .hp = unit.maxHp(kind, s.cfg),
        .path = path_buf,
    };
    if (owner == .player) {
        selection.selectSingle(s.unitSelection(), s.unit_count);
        const label = switch (kind) {
            .worker => s.cfg.labels.worker,
            .soldier => s.cfg.labels.soldier,
        };
        notify.pushUnitTrained(s, label);
    }
    s.spatial_index.putUnit(s.unit_count, spawn);
    s.unit_count += 1;
    return true;
}

fn findSpawn(s: *const State, center_x: usize, center_y: usize) ?coords.Pos {
    const offsets = [_]struct { dx: isize, dy: isize }{
        .{ .dx = 1, .dy = 0 },  .{ .dx = -1, .dy = 0 },
        .{ .dx = 0, .dy = 1 },  .{ .dx = 0, .dy = -1 },
        .{ .dx = 1, .dy = 1 },  .{ .dx = -1, .dy = -1 },
        .{ .dx = 1, .dy = -1 }, .{ .dx = -1, .dy = 1 },
    };
    for (offsets) |o| {
        const next_x: isize = @as(isize, @intCast(center_x)) + o.dx;
        const next_y: isize = @as(isize, @intCast(center_y)) + o.dy;
        if (next_x < 0 or next_y < 0) continue;
        const ux: usize = @intCast(next_x);
        const uy: usize = @intCast(next_y);
        if (ux >= s.world.width or uy >= s.world.height) continue;
        if (!s.world.isWalkable(ux, uy)) continue;
        if (queries.occupied(s.spatialCtx(), ux, uy)) continue;
        return .{ .x = ux, .y = uy };
    }
    return null;
}

test "init places both TCs as buildings" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    const s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer {
        var mut_s = s;
        mut_s.deinit();
    }
    try std.testing.expectEqual(@as(usize, 2), s.building_count - countPlayerFarms(&s));
    try std.testing.expectEqual(building.BuildingKind.town_center, s.buildings[0].kind());
    try std.testing.expectEqual(unit.Owner.player, s.buildings[0].owner);
    try std.testing.expectEqual(building.BuildingKind.town_center, s.buildings[1].kind());
    try std.testing.expectEqual(unit.Owner.enemy, s.buildings[1].owner);
}

fn countPlayerFarms(s: *const State) usize {
    const Pred = struct {
        fn ok(b: building.Building) bool {
            return b.kind() == .farm and b.owner == .player;
        }
    };
    return lib_spatial.countWhere(s.buildings[0..s.building_count], Pred.ok);
}

test "init spawns starting workers" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    const s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer {
        var mut_s = s;
        mut_s.deinit();
    }
    var player_workers: usize = 0;
    var enemy_workers: usize = 0;
    for (0..s.unit_count) |i| {
        if (s.units[i].owner == .player and s.units[i].kind() == .worker) player_workers += 1;
        if (s.units[i].owner == .enemy and s.units[i].kind() == .worker) enemy_workers += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), player_workers);
    try std.testing.expectEqual(@as(usize, 2), enemy_workers);
}

test "init spawns deer" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    const s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer {
        var mut_s = s;
        mut_s.deinit();
    }
    try std.testing.expect(s.wildlife_count > 0);
}

test "init buildings start complete" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    const s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer {
        var mut_s = s;
        mut_s.deinit();
    }
    for (0..s.building_count) |i| {
        try std.testing.expect(s.buildings[i].isComplete());
    }
}

test "spawnUnit returns false at capacity" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.unit_count = s.cfg.entity_limits.max_units;
    try std.testing.expect(!spawnUnit(&s, .worker, .player, s.world.player_tc_x, s.world.player_tc_y));
}

test "spawnUnit with enemy owner does not set selection" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const before = selection.primarySelected(s.unitSelection()).?;
    _ = spawnUnit(&s, .worker, .enemy, s.world.enemy_tc_x, s.world.enemy_tc_y);
    try std.testing.expectEqual(before, selection.primarySelected(s.unitSelection()).?);
}

test "units cannot occupy same tile" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();

    for (0..s.unit_count) |i| {
        for (i + 1..s.unit_count) |j| {
            const same = s.units[i].x == s.units[j].x and s.units[i].y == s.units[j].y;
            try std.testing.expect(!same);
        }
    }
}
