const std = @import("std");
const state = @import("state.zig");
const unit = @import("../units/unit.zig");
const coords = @import("../lib/coords.zig");
const building = @import("../buildings/building.zig");
const farm = @import("../buildings/farm.zig");
const wildlife = @import("../resources/wildlife.zig");
const map = @import("map.zig");
const queries = @import("queries.zig");
const lib_spatial = @import("../lib/spatial.zig");
const movement = @import("movement.zig");
const config = @import("../config.zig");
const notify = @import("notify.zig");
const tick = @import("tick.zig");

const Pos = coords.Pos;
const State = state.State;

pub const GatherKind = enum { wood, deer, farm };

fn resetCarry(u: *unit.Unit) void {
    u.carry = 0;
    u.carry_kind = .none;
    u.gather_accum_ms = 0;
    u.path_len = 0;
    u.path_idx = 0;
}

fn buildingPos(s: *const State, bi: usize) Pos {
    return .{ .x = s.buildings[bi].x, .y = s.buildings[bi].y };
}

fn beginToDropoff(s: *State, i: usize) bool {
    const u = &s.units[i];
    const di = findNearestDropoff(s, u.pos()) orelse {
        u.state = .idle;
        u.gather_phase = .none;
        resetCarry(u);
        return false;
    };
    u.dest = buildingPos(s, di);
    _ = movement.pathToAdjacent(s.allocator, s.spatialCtx(), &s.world, s.units, i, buildingPos(s, di), u.pos());
    return true;
}

fn routeDropoff(s: *State, i: usize, on_arrive: anytype) void {
    const u = &s.units[i];
    if (u.path_len == 0) {
        if (findNearestDropoff(s, u.pos())) |di| {
            const dp = buildingPos(s, di);
            if (coords.manhattan(u.pos(), dp) <= 1) {
                on_arrive(s, i);
                return;
            }
            u.dest = dp;
            _ = movement.pathToAdjacent(s.allocator, s.spatialCtx(), &s.world, s.units, i, dp, u.pos());
        } else {
            on_arrive(s, i);
            return;
        }
    }
    movement.advance(s.allocator, s.spatialCtx(), &s.world, s.units, i);
}

pub fn findNearestDropoff(s: *const State, from: Pos) ?usize {
    const Predicate = struct {
        fn ok(b: building.Building) bool {
            return b.owner == .player and b.isDropoff() and b.isComplete();
        }
    };
    return lib_spatial.findIndexNearestWhere(
        s.buildings[0..s.building_count],
        from,
        std.math.maxInt(usize),
        Predicate.ok,
    );
}

pub fn findNearestTree(s: *const State, from: Pos, radius: usize) ?Pos {
    const TreeCtx = struct {
        world: *const map.GameMap,
        ctx: queries.Ctx,
        fn isOpenTree(self: @This(), p: Pos) bool {
            if (self.world.at(p.x, p.y) != .tree) return false;
            return !queries.occupied(self.ctx, p.x, p.y);
        }
    };
    return lib_spatial.findNearestPosWhere(
        TreeCtx{ .world = &s.world, .ctx = s.spatialCtx() },
        from,
        radius,
        TreeCtx.isOpenTree,
    );
}

pub fn findNearestDeer(s: *const State, from: Pos, radius: usize) ?usize {
    const Pred = struct {
        fn alive(w: wildlife.Wildlife) bool {
            return !w.isDead();
        }
    };
    return lib_spatial.findIndexNearestWhere(s.wildlife[0..s.wildlife_count], from, radius, Pred.alive);
}

pub fn findFreeFarm(s: *const State, from: Pos) ?usize {
    const Predicate = struct {
        fn ok(b: building.Building) bool {
            if (b.kind() != .farm or b.owner != .player) return false;
            const f = &b.variant.farm;
            return !f.fallow and f.food_remaining > 0 and f.assigned_worker == null;
        }
    };
    return lib_spatial.findIndexNearestWhere(
        s.buildings[0..s.building_count],
        from,
        std.math.maxInt(usize),
        Predicate.ok,
    );
}

pub fn removeDeer(s: *State, idx: usize) void {
    if (idx >= s.wildlife_count) return;
    const last = s.wildlife_count - 1;
    if (idx != last) s.wildlife[idx] = s.wildlife[last];
    s.wildlife_count = last;
    for (0..s.unit_count) |i| {
        if (s.units[i].target_deer_idx) |td| {
            if (td == idx) {
                s.units[i].target_deer_idx = null;
            } else if (td == last) {
                s.units[i].target_deer_idx = idx;
            }
        }
    }
}

pub fn tickUnit(s: *State, i: usize) void {
    const u = &s.units[i];
    switch (u.state) {
        .gathering_wood => tickWood(s, i),
        .hunting => tickHunt(s, i),
        .gathering_food => tickFarm(s, i),
        else => {},
    }
}

fn tickWood(s: *State, i: usize) void {
    const u = &s.units[i];
    switch (u.gather_phase) {
        .none, .to_resource => {
            if (u.gather_target) |gt| {
                if (s.world.at(gt.x, gt.y) != .tree) {
                    const anchor = u.grove_anchor orelse gt;
                    if (findNearestTree(s, anchor, s.cfg.economy.grove_scan_radius)) |nt| {
                        u.gather_target = nt;
                        u.gather_phase = .to_resource;
                        _ = movement.pathToAdjacent(s.allocator, s.spatialCtx(), &s.world, s.units, i, nt, u.pos());
                    } else {
                        u.state = .idle;
                        u.gather_phase = .none;
                        u.gather_target = null;
                        u.grove_anchor = null;
                        return;
                    }
                }
                if (movement.isAdjacentTree(&s.world, u, gt)) {
                    u.gather_phase = .harvesting;
                    u.gather_accum_ms = 0;
                    u.path_len = 0;
                    u.path_idx = 0;
                    return;
                }
                if (u.path_len == 0) {
                    _ = movement.pathToAdjacent(s.allocator, s.spatialCtx(), &s.world, s.units, i, gt, u.pos());
                }
                movement.advance(s.allocator, s.spatialCtx(), &s.world, s.units, i);
            } else {
                u.state = .idle;
                u.gather_phase = .none;
            }
        },
        .harvesting => {
            if (u.gather_target) |gt| {
                if (s.world.at(gt.x, gt.y) != .tree) {
                    u.gather_phase = .to_resource;
                    return;
                }
                const tick_ms: u32 = @intCast(s.cfg.timing.tick_period_ns / 1_000_000);
                const interval_ms: u32 = 1000 / s.cfg.economy.wood_gather_rate;
                u.gather_accum_ms += tick_ms;
                while (u.gather_accum_ms >= interval_ms) {
                    u.gather_accum_ms -= interval_ms;
                    if (s.world.at(gt.x, gt.y) != .tree) break;
                    s.world.depleteTree(gt.x, gt.y, 1);
                    if (s.world.at(gt.x, gt.y) != .tree) {
                        notify.pushTreeDepleted(s);
                    }
                    u.carry += 1;
                    u.carry_kind = .wood;
                    if (u.carry >= s.cfg.economy.carry_capacity) break;
                }
                if (u.carry >= s.cfg.economy.carry_capacity or s.world.at(gt.x, gt.y) != .tree) {
                    u.gather_phase = .to_dropoff;
                    _ = beginToDropoff(s, i);
                }
            }
        },
        .to_dropoff => routeDropoff(s, i, dropAndContinueWood),
    }
}

fn dropAndContinueWood(s: *State, i: usize) void {
    const u = &s.units[i];
    if (u.carry_kind == .wood and u.carry > 0) {
        notify.pushWoodDrop(s, u.carry);
        s.wood += u.carry;
        u.carry = 0;
        u.carry_kind = .none;
    }
    const anchor = u.grove_anchor orelse u.gather_target orelse u.pos();
    if (findNearestTree(s, anchor, s.cfg.economy.grove_scan_radius)) |nt| {
        u.gather_target = nt;
        u.grove_anchor = anchor;
        u.gather_phase = .to_resource;
        _ = movement.pathToAdjacent(s.allocator, s.spatialCtx(), &s.world, s.units, i, nt, u.pos());
    } else {
        u.state = .idle;
        u.gather_phase = .none;
        u.gather_target = null;
        u.grove_anchor = null;
    }
}

fn tickHunt(s: *State, i: usize) void {
    const u = &s.units[i];
    switch (u.gather_phase) {
        .none, .to_resource => {
            if (u.target_deer_idx) |di| {
                if (di >= s.wildlife_count or s.wildlife[di].kind() != .deer) {
                    u.target_deer_idx = null;
                }
            }
            if (u.target_deer_idx == null) {
                if (findNearestDeer(s, u.pos(), s.cfg.economy.deer_hunt_radius)) |di| {
                    u.target_deer_idx = di;
                } else {
                    u.state = .idle;
                    u.gather_phase = .none;
                    return;
                }
            }
            const di = u.target_deer_idx.?;
            const dpos = s.wildlife[di].pos();
            u.gather_target = dpos;
            if (movement.arrived(u, dpos)) {
                const n = &s.wildlife[di];
                if (!n.deer.dead) {
                    n.deer.dead = true;
                    notify.pushDeerKilled(s);
                }
                u.gather_phase = .harvesting;
                u.gather_accum_ms = 0;
                u.path_len = 0;
                u.path_idx = 0;
                return;
            }
            if (u.path_len == 0 or !pathHeadsTo(u, dpos)) {
                _ = movement.pathToAdjacent(s.allocator, s.spatialCtx(), &s.world, s.units, i, dpos, u.pos());
            }
            movement.advance(s.allocator, s.spatialCtx(), &s.world, s.units, i);
        },
        .harvesting => {
            const di = u.target_deer_idx orelse {
                u.gather_phase = .to_resource;
                return;
            };
            if (di >= s.wildlife_count or s.wildlife[di].kind() != .deer) {
                u.target_deer_idx = null;
                u.gather_phase = .to_resource;
                return;
            }
            const n = &s.wildlife[di];
            const dpos = n.pos();
            if (!movement.arrived(u, dpos)) {
                u.gather_phase = .to_resource;
                return;
            }
            const tick_ms: u32 = @intCast(s.cfg.timing.tick_period_ns / 1_000_000);
            const interval_ms: u32 = 1000 / s.cfg.economy.food_gather_rate;
            u.gather_accum_ms += tick_ms;
            var carcass_done = false;
            while (u.gather_accum_ms >= interval_ms) {
                u.gather_accum_ms -= interval_ms;
                if (n.deer.food_remaining == 0) {
                    removeDeer(s, di);
                    u.target_deer_idx = null;
                    carcass_done = true;
                    break;
                }
                n.deer.food_remaining -= 1;
                u.carry += 1;
                u.carry_kind = .food;
                if (u.carry >= s.cfg.economy.carry_capacity) break;
            }
            if (carcass_done or u.carry >= s.cfg.economy.carry_capacity) {
                u.gather_phase = .to_dropoff;
                _ = beginToDropoff(s, i);
            }
        },
        .to_dropoff => routeDropoff(s, i, dropAndContinueHunt),
    }
}

fn pathHeadsTo(u: *const unit.Unit, target: Pos) bool {
    if (u.path_len == 0) return false;
    const end = u.path[u.path_len - 1];
    return coords.manhattan(end, target) <= 1;
}

fn dropAndContinueHunt(s: *State, i: usize) void {
    const u = &s.units[i];
    if (u.carry_kind == .food and u.carry > 0) {
        notify.pushFoodDrop(s, u.carry);
        s.food += u.carry;
        u.carry = 0;
        u.carry_kind = .none;
    }
    if (u.target_deer_idx) |di| {
        if (di < s.wildlife_count and s.wildlife[di].kind() == .deer and s.wildlife[di].deer.food_remaining > 0) {
            u.gather_phase = .to_resource;
            return;
        }
        u.target_deer_idx = null;
    }
    const hunt_origin = u.gather_target orelse u.pos();
    if (findNearestDeer(s, hunt_origin, s.cfg.economy.deer_hunt_radius)) |di| {
        u.target_deer_idx = di;
        u.gather_phase = .to_resource;
    } else {
        u.state = .idle;
        u.gather_phase = .none;
        u.target_deer_idx = null;
    }
}

fn tickFarm(s: *State, i: usize) void {
    const u = &s.units[i];
    const fi = u.target_farm_idx orelse {
        u.state = .idle;
        u.gather_phase = .none;
        return;
    };
    if (fi >= s.building_count or s.buildings[fi].kind() != .farm) {
        u.target_farm_idx = null;
        u.state = .idle;
        u.gather_phase = .none;
        return;
    }
    const fpos = Pos{ .x = s.buildings[fi].x, .y = s.buildings[fi].y };
    u.gather_target = fpos;
    switch (u.gather_phase) {
        .none, .to_resource => {
            if (movement.arrived(u, fpos)) {
                const b = &s.buildings[fi];
                if (b.variant.farm.fallow or b.variant.farm.food_remaining == 0) {
                    if (autoResow(s, fi)) {
                        u.gather_phase = .harvesting;
                        u.gather_accum_ms = 0;
                        u.path_len = 0;
                        u.path_idx = 0;
                        return;
                    }
                    b.variant.farm.assigned_worker = null;
                    u.state = .idle;
                    u.gather_phase = .none;
                    u.target_farm_idx = null;
                    return;
                }
                u.gather_phase = .harvesting;
                u.gather_accum_ms = 0;
                u.path_len = 0;
                u.path_idx = 0;
                return;
            }
            if (u.path_len == 0) _ = movement.pathToAdjacent(s.allocator, s.spatialCtx(), &s.world, s.units, i, fpos, u.pos());
            movement.advance(s.allocator, s.spatialCtx(), &s.world, s.units, i);
        },
        .harvesting => {
            const b = &s.buildings[fi];
            if (b.variant.farm.fallow or b.variant.farm.food_remaining == 0) {
                b.variant.farm.assigned_worker = null;
                u.state = .idle;
                u.gather_phase = .none;
                u.target_farm_idx = null;
                return;
            }
            const tick_ms: u32 = @intCast(s.cfg.timing.tick_period_ns / 1_000_000);
            const interval_ms: u32 = 1000 / s.cfg.economy.farm_gather_rate;
            u.gather_accum_ms += tick_ms;
            while (u.gather_accum_ms >= interval_ms) {
                u.gather_accum_ms -= interval_ms;
                if (b.variant.farm.food_remaining == 0) break;
                b.variant.farm.food_remaining -= 1;
                u.carry += 1;
                u.carry_kind = .food;
                if (u.carry >= s.cfg.economy.carry_capacity) break;
            }
            if (b.variant.farm.food_remaining == 0) {
                b.variant.farm.fallow = true;
                notify.pushFarmDepleted(s);
            }
            if (u.carry >= s.cfg.economy.carry_capacity or b.variant.farm.food_remaining == 0) {
                u.gather_phase = .to_dropoff;
                if (findNearestDropoff(s, u.pos())) |di| {
                    u.dest = .{ .x = s.buildings[di].x, .y = s.buildings[di].y };
                    _ = movement.pathToAdjacent(s.allocator, s.spatialCtx(), &s.world, s.units, i, .{ .x = s.buildings[di].x, .y = s.buildings[di].y }, u.pos());
                }
            }
        },
        .to_dropoff => routeDropoff(s, i, dropAndContinueFarm),
    }
}

fn dropAndContinueFarm(s: *State, i: usize) void {
    const u = &s.units[i];
    if (u.carry_kind == .food and u.carry > 0) {
        notify.pushFoodDrop(s, u.carry);
        s.food += u.carry;
        u.carry = 0;
        u.carry_kind = .none;
    }
    u.gather_phase = .to_resource;
}

fn tryResow(s: *State, fi: usize, require_owner_player: bool) bool {
    const b = &s.buildings[fi];
    if (b.kind() != .farm) return false;
    if (require_owner_player and b.owner != .player) return false;
    if (!b.variant.farm.fallow) return false;
    if (s.wood < s.cfg.economy.resow_wood_cost) return false;
    s.wood -= s.cfg.economy.resow_wood_cost;
    farm.resow(&b.variant.farm, s.cfg);
    return true;
}

pub fn autoResow(s: *State, fi: usize) bool {
    return tryResow(s, fi, true);
}

pub fn resowFarm(s: *State, building_idx: usize) bool {
    return tryResow(s, building_idx, true);
}

pub fn startGatherAt(s: *State, i: usize, target: Pos) bool {
    const u = &s.units[i];
    if (u.kind() != .worker or u.owner != .player) return false;
    if (s.world.at(target.x, target.y) == .tree) {
        if (queries.occupied(s.spatialCtx(), target.x, target.y)) return false;
        u.state = .gathering_wood;
        u.gather_phase = .to_resource;
        u.gather_target = target;
        u.grove_anchor = target;
        resetCarry(u);
        return movement.pathToAdjacent(s.allocator, s.spatialCtx(), &s.world, s.units, i, target, u.pos());
    }
    if (lib_spatial.indexOfAt((s.spatialCtx()).wildlife, target.x, target.y)) |ni| {
        if (s.wildlife[ni].kind() != .deer) return false;
        u.state = .hunting;
        u.gather_phase = .to_resource;
        u.target_deer_idx = ni;
        u.gather_target = s.wildlife[ni].pos();
        resetCarry(u);
        return movement.pathToAdjacent(s.allocator, s.spatialCtx(), &s.world, s.units, i, s.wildlife[ni].pos(), u.pos());
    }
    if (lib_spatial.indexOfAt((s.spatialCtx()).buildings, target.x, target.y)) |bi| {
        const b = &s.buildings[bi];
        if (b.kind() != .farm or b.owner != .player) return false;
        if (b.variant.farm.fallow or b.variant.farm.food_remaining == 0) return false;
        if (b.variant.farm.assigned_worker != null and b.variant.farm.assigned_worker.? != i) return false;
        b.variant.farm.assigned_worker = i;
        u.state = .gathering_food;
        u.gather_phase = .to_resource;
        u.target_farm_idx = bi;
        u.gather_target = .{ .x = b.x, .y = b.y };
        resetCarry(u);
        return movement.pathToAdjacent(s.allocator, s.spatialCtx(), &s.world, s.units, i, .{ .x = b.x, .y = b.y }, u.pos());
    }
    return false;
}

pub fn startGatherNearest(s: *State, i: usize, kind: GatherKind) bool {
    const u = &s.units[i];
    if (u.kind() != .worker or u.owner != .player) return false;
    const p = u.pos();
    switch (kind) {
        .wood => {
            const t = findNearestTree(s, p, s.cfg.economy.deer_hunt_radius) orelse return false;
            return startGatherAt(s, i, t);
        },
        .deer => {
            const di = findNearestDeer(s, p, s.cfg.economy.deer_hunt_radius) orelse return false;
            return startGatherAt(s, i, s.wildlife[di].pos());
        },
        .farm => {
            const fi = findFreeFarm(s, p) orelse return false;
            return startGatherAt(s, i, .{ .x = s.buildings[fi].x, .y = s.buildings[fi].y });
        },
    }
}

test "findNearestDropoff picks closest TC" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const di = findNearestDropoff(&s, .{ .x = s.world.player_tc_x + 1, .y = s.world.player_tc_y }).?;
    try std.testing.expect(s.buildings[di].isDropoff());
    try std.testing.expectEqual(unit.Owner.player, s.buildings[di].owner);
}

test "findNearestTree finds tree tile" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    var found = false;
    for (0..s.world.height) |y| {
        for (0..s.world.width) |x| {
            if (s.world.at(x, y) == .tree) {
                if (findNearestTree(&s, .{ .x = x, .y = y }, 1)) |t| {
                    try std.testing.expectEqual(@as(map.Tile, .tree), s.world.at(t.x, t.y));
                    found = true;
                }
            }
        }
        if (found) break;
    }
    try std.testing.expect(found);
}

test "startGatherAt wood sets gathering_wood" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    var tx: usize = 0;
    var ty: usize = 0;
    var ok = false;
    for (0..s.world.height) |y| {
        for (0..s.world.width) |x| {
            if (s.world.at(x, y) == .tree and !queries.occupied(s.spatialCtx(), x, y)) {
                tx = x; ty = y; ok = true; break;
            }
        }
        if (ok) break;
    }
    try std.testing.expect(ok);
    s.units[0].x = s.world.player_tc_x;
    s.units[0].y = s.world.player_tc_y;
    try std.testing.expect(startGatherAt(&s, 0, .{ .x = tx, .y = ty }));
    try std.testing.expectEqual(unit.UnitActivity.gathering_wood, s.units[0].state);
    try std.testing.expectEqual(unit.GatherPhase.to_resource, s.units[0].gather_phase);
}

test "resowFarm costs wood and restores food" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.building_count = 3;
    s.buildings[2] = .{
        .x = 5, .y = 5, .variant = .{ .farm = .{ .food_remaining = 0, .fallow = true } }, .owner = .player,
        .hp = 100,
    };
    s.wood = s.cfg.economy.resow_wood_cost;
    try std.testing.expect(resowFarm(&s, 2));
    try std.testing.expectEqual(@as(u32, 0), s.wood);
    try std.testing.expect(!s.buildings[2].variant.farm.fallow);
    try std.testing.expectEqual(s.cfg.economy.farm_yield_total, s.buildings[2].variant.farm.food_remaining);
}

test "resowFarm fails without wood" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.building_count = 3;
    s.buildings[2] = .{
        .x = 5, .y = 5, .variant = .{ .farm = .{ .food_remaining = 0, .fallow = true } }, .owner = .player,
        .hp = 100,
    };
    s.wood = 0;
    try std.testing.expect(!resowFarm(&s, 2));
}

test "removeDeer updates other workers' indices" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const before = s.wildlife_count;
    try std.testing.expect(before >= 2);
    s.units[0].target_deer_idx = before - 1;
    removeDeer(&s, 0);
    try std.testing.expectEqual(before - 1, s.wildlife_count);
    try std.testing.expectEqual(@as(?usize, 0), s.units[0].target_deer_idx);
}

fn findTreeNearTc(s: *State) ?struct { tree: Pos, stand: Pos } {
    const tc = Pos{ .x = s.world.player_tc_x, .y = s.world.player_tc_y };
    const tree = findNearestTree(s, tc, 15) orelse return null;
    const dirs = coords.dirs4;
    for (dirs) |d| {
        const nx = @as(isize, @intCast(tree.x)) + d.dx;
        const ny = @as(isize, @intCast(tree.y)) + d.dy;
        if (nx < 0 or ny < 0) continue;
        const ux: usize = @intCast(nx);
        const uy: usize = @intCast(ny);
        if (ux >= s.world.width or uy >= s.world.height) continue;
        if (!s.world.isWalkable(ux, uy)) continue;
        if (queries.occupied(s.spatialCtx(), ux, uy)) continue;
        return .{ .tree = tree, .stand = .{ .x = ux, .y = uy } };
    }
    return null;
}

test "wood gather: harvest depletes tree and sets carry" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const spot = findTreeNearTc(&s) orelse return;
    s.units[0].x = spot.stand.x;
    s.units[0].y = spot.stand.y;
    try std.testing.expect(startGatherAt(&s, 0, spot.tree));
    tickUnit(&s, 0);
    try std.testing.expectEqual(unit.GatherPhase.harvesting, s.units[0].gather_phase);
    const ticks_to_fill = @as(usize, @intCast(@divFloor(1000, cfg.economy.wood_gather_rate) * cfg.economy.carry_capacity / @as(u32, @intCast(cfg.timing.tick_period_ns / 1_000_000))));
    for (0..ticks_to_fill + 5) |_| tickUnit(&s, 0);
    try std.testing.expectEqual(@as(u16, cfg.economy.carry_capacity), s.units[0].carry);
    try std.testing.expectEqual(unit.CargoKind.wood, s.units[0].carry_kind);
    try std.testing.expectEqual(unit.GatherPhase.to_dropoff, s.units[0].gather_phase);
    try std.testing.expectEqual(@as(u16, cfg.economy.tree_total_yield - cfg.economy.carry_capacity), s.world.treeRemainingAt(spot.tree.x, spot.tree.y));
}

test "wood gather: drop-off increments wood counter" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const spot = findTreeNearTc(&s) orelse return;
    s.units[0].x = spot.stand.x;
    s.units[0].y = spot.stand.y;
    _ = startGatherAt(&s, 0, spot.tree);
    const wood_before = s.wood;
    for (0..600) |_| tickUnit(&s, 0);
    try std.testing.expect(s.wood > wood_before);
}

test "tree fully depletes after total/yield trips" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const spot = findTreeNearTc(&s) orelse return;
    s.units[0].x = spot.stand.x;
    s.units[0].y = spot.stand.y;
    for (1..s.unit_count) |i| {
        s.units[i].x = 0;
        s.units[i].y = 0;
        s.units[i].state = .idle;
        s.units[i].path_len = 0;
    }
    _ = startGatherAt(&s, 0, spot.tree);
    const trips_needed = (s.cfg.economy.tree_total_yield + s.cfg.economy.carry_capacity - 1) / s.cfg.economy.carry_capacity;
    for (0..trips_needed * 200) |_| {
        tickUnit(&s, 0);
        if (s.world.at(spot.tree.x, spot.tree.y) == .grass) break;
    }
    try std.testing.expectEqual(@as(map.Tile, .grass), s.world.at(spot.tree.x, spot.tree.y));
    const total_gathered = s.wood + @as(u32, if (s.units[0].carry_kind == .wood) s.units[0].carry else 0);
    try std.testing.expectEqual(@as(u32, s.cfg.economy.tree_total_yield), total_gathered);
}

test "deer dies on contact and carcass harvested over multiple trips" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    var di: usize = 0;
    for (0..s.wildlife_count) |i| {
        if (s.wildlife[i].kind() == .deer) { di = i; break; }
    }
    s.wildlife[di].deer.food_remaining = s.cfg.economy.deer_total_yield;
    s.wildlife[di].deer.x = s.units[0].x + 1;
    s.wildlife[di].deer.y = s.units[0].y;
    try std.testing.expect(startGatherAt(&s, 0, s.wildlife[di].pos()));
    try std.testing.expectEqual(unit.UnitActivity.hunting, s.units[0].state);
    
    // Run a few ticks to get to the deer
    for (0..10) |_| tickUnit(&s, 0);
    
    // Deer should be dead immediately on contact
    try std.testing.expect(s.wildlife[di].deer.dead);
    
    const trips_needed = (s.cfg.economy.deer_total_yield + s.cfg.economy.carry_capacity - 1) / s.cfg.economy.carry_capacity;
    for (0..trips_needed * 200) |_| {
        tickUnit(&s, 0);
        if (s.wildlife_count == 0 or s.units[0].state == .idle) break;
    }
    try std.testing.expect(s.food >= s.cfg.economy.deer_total_yield);
}

test "dead deer carcass rots over time" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    
    // Place a dead deer manually
    s.wildlife[0] = .{ .deer = .{
        .x = 10,
        .y = 10,
        .hp = 25,
        .dead = true,
        .food_remaining = 50,
        .rot_accum_ms = 0,
    } };
    s.wildlife_count = 1;
    
    const initial_food = s.wildlife[0].deer.food_remaining;
    
    // Run tick which includes rot pass
    // At deer_rot_rate=1/sec and tick_rate=10/sec, food should decrease by 1 every 10 ticks
    for (0..15) |_| tick.tick(&s);
    
    // Food should have decreased due to rot
    try std.testing.expect(s.wildlife[0].deer.food_remaining < initial_food);
}

test "carcass removed when food reaches zero" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    
    // Place a dead deer with low food
    s.wildlife[0] = .{ .deer = .{
        .x = 10,
        .y = 10,
        .hp = 25,
        .dead = true,
        .food_remaining = 2,
        .rot_accum_ms = 0,
    } };
    s.wildlife_count = 1;
    
    // Run enough ticks for food to rot away (2 food at 1/sec = 20 ticks at 10 ticks/sec)
    for (0..30) |_| tick.tick(&s);
    
    // Carcass should be removed
    try std.testing.expectEqual(@as(usize, 0), s.wildlife_count);
}

test "farm gather: depletes and goes fallow" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    var fi: usize = 0;
    var found = false;
    for (0..s.building_count) |i| {
        if (s.buildings[i].kind() == .farm and s.buildings[i].owner == .player) {
            fi = i; found = true; break;
        }
    }
    try std.testing.expect(found);
    const fpos = Pos{ .x = s.buildings[fi].x, .y = s.buildings[fi].y };
    const dirs = coords.dirs4;
    var placed = false;
    for (dirs) |d| {
        const nx = @as(isize, @intCast(fpos.x)) + d.dx;
        const ny = @as(isize, @intCast(fpos.y)) + d.dy;
        if (nx < 0 or ny < 0) continue;
        const ux: usize = @intCast(nx);
        const uy: usize = @intCast(ny);
        if (ux >= s.world.width or uy >= s.world.height) continue;
        if (!s.world.isWalkable(ux, uy) or queries.occupied(s.spatialCtx(), ux, uy)) continue;
        s.units[0].x = ux;
        s.units[0].y = uy;
        placed = true;
        break;
    }
    try std.testing.expect(placed);
    try std.testing.expect(startGatherAt(&s, 0, fpos));
    try std.testing.expectEqual(unit.UnitActivity.gathering_food, s.units[0].state);
    for (0..3000) |_| {
        tickUnit(&s, 0);
        if (s.buildings[fi].variant.farm.fallow and s.units[0].carry == 0 and s.units[0].gather_phase != .to_dropoff) break;
    }
    for (0..200) |_| tickUnit(&s, 0);
    try std.testing.expect(s.buildings[fi].variant.farm.fallow);
    try std.testing.expectEqual(@as(u16, 0), s.buildings[fi].variant.farm.food_remaining);
    try std.testing.expectEqual(@as(u32, s.cfg.economy.farm_yield_total), s.food);
}

test "gatherNearest wood finds a tree" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const ok = startGatherNearest(&s, 0, .wood);
    if (ok) {
        try std.testing.expectEqual(unit.UnitActivity.gathering_wood, s.units[0].state);
    }
}
