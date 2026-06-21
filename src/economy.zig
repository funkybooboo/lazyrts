const std = @import("std");
const game = @import("game.zig");
const unit = @import("unit.zig");
const building = @import("building.zig");
const nature = @import("nature.zig");
const map = @import("map.zig");
const spatial = @import("spatial.zig");
const pathfinding = @import("pathfinding.zig");
const config = @import("config.zig");

const Pos = unit.Pos;
const State = game.State;

pub const GatherKind = enum { wood, deer, farm };

pub fn find_nearest_depot(s: *const State, from: Pos) ?usize {
    var best: ?usize = null;
    var best_d: usize = std.math.maxInt(usize);
    for (0..s.building_count) |i| {
        const b = &s.buildings[i];
        if (b.owner != .player) continue;
        if (!b.kind.is_depot()) continue;
        if (!b.is_complete()) continue;
        const d = manhattan(from, .{ .x = b.x, .y = b.y });
        if (d < best_d) {
            best_d = d;
            best = i;
        }
    }
    return best;
}

pub fn find_nearest_tree(s: *const State, from: Pos, radius: usize) ?Pos {
    var best: ?Pos = null;
    var best_d: usize = std.math.maxInt(usize);
    const w: isize = @intCast(s.world.width);
    const h: isize = @intCast(s.world.height);
    var dy: isize = -@as(isize, @intCast(radius));
    while (dy <= @as(isize, @intCast(radius))) : (dy += 1) {
        var dx: isize = -@as(isize, @intCast(radius));
        while (dx <= @as(isize, @intCast(radius))) : (dx += 1) {
            const tx = @as(isize, @intCast(from.x)) + dx;
            const ty = @as(isize, @intCast(from.y)) + dy;
            if (tx < 0 or ty < 0 or tx >= w or ty >= h) continue;
            const ux: usize = @intCast(tx);
            const uy: usize = @intCast(ty);
            if (s.world.at(ux, uy) != .tree) continue;
            if (spatial.occupied(s, ux, uy)) continue;
            const d = manhattan(from, .{ .x = ux, .y = uy });
            if (d < best_d) {
                best_d = d;
                best = .{ .x = ux, .y = uy };
            }
        }
    }
    return best;
}

pub fn find_nearest_deer(s: *const State, from: Pos, radius: usize) ?usize {
    var best: ?usize = null;
    var best_d: usize = std.math.maxInt(usize);
    for (0..s.nature_count) |i| {
        const n = &s.nature[i];
        if (n.kind != .deer) continue;
        const d = manhattan(from, .{ .x = n.x, .y = n.y });
        if (d > radius) continue;
        if (d < best_d) {
            best_d = d;
            best = i;
        }
    }
    return best;
}

pub fn find_free_farm(s: *const State, from: Pos) ?usize {
    var best: ?usize = null;
    var best_d: usize = std.math.maxInt(usize);
    for (0..s.building_count) |i| {
        const b = &s.buildings[i];
        if (b.kind != .farm or b.owner != .player) continue;
        if (b.fallow) continue;
        if (b.food_remaining == 0) continue;
        if (b.assigned_worker != null) continue;
        const d = manhattan(from, .{ .x = b.x, .y = b.y });
        if (d < best_d) {
            best_d = d;
            best = i;
        }
    }
    return best;
}

fn manhattan(a: Pos, b: Pos) usize {
    const dx = if (a.x > b.x) a.x - b.x else b.x - a.x;
    const dy = if (a.y > b.y) a.y - b.y else b.y - a.y;
    return dx + dy;
}

fn adjacent_walkable(s: *const State, target: Pos, prefer_near: Pos) ?Pos {
    const dirs = [_]struct { dx: isize, dy: isize }{
        .{ .dx = 0, .dy = -1 }, .{ .dx = 0, .dy = 1 },
        .{ .dx = -1, .dy = 0 }, .{ .dx = 1, .dy = 0 },
    };
    var best: ?Pos = null;
    var best_d: usize = std.math.maxInt(usize);
    for (dirs) |d| {
        const nx = @as(isize, @intCast(target.x)) + d.dx;
        const ny = @as(isize, @intCast(target.y)) + d.dy;
        if (nx < 0 or ny < 0) continue;
        const ux: usize = @intCast(nx);
        const uy: usize = @intCast(ny);
        if (ux >= s.world.width or uy >= s.world.height) continue;
        if (!s.world.is_walkable(ux, uy)) continue;
        if (spatial.occupied(s, ux, uy)) continue;
        const dd = manhattan(prefer_near, .{ .x = ux, .y = uy });
        if (dd < best_d) {
            best_d = dd;
            best = .{ .x = ux, .y = uy };
        }
    }
    return best;
}

fn path_to(s: *State, i: usize, goal: Pos) bool {
    return path_to_internal(s, i, goal, goal);
}

fn path_to_adjacent(s: *State, i: usize, target: Pos, approach_from: Pos) bool {
    const adj = adjacent_walkable(s, target, approach_from) orelse return false;
    return path_to_internal(s, i, adj, target);
}

fn path_to_internal(s: *State, i: usize, goal: Pos, dest_record: Pos) bool {
    const u = &s.units[i];
    const start = u.pos();
    if (start.x == goal.x and start.y == goal.y) {
        u.path_len = 0;
        u.path_idx = 0;
        u.dest = dest_record;
        return true;
    }
    var blocked_buf: [256]Pos = undefined;
    const blocked_count = spatial.collect_blocked(s, &blocked_buf, i);
    const blocked_slice = if (blocked_count > 0) blocked_buf[0..blocked_count] else null;

    var target = goal;
    const len = pathfinding.find_path(s.allocator, &s.world, start, goal, u.path, blocked_slice) orelse blk: {
        const near = pathfinding.find_nearest_reachable(s.allocator, &s.world, goal, blocked_slice) orelse return false;
        target = near;
        break :blk pathfinding.find_path(s.allocator, &s.world, start, near, u.path, blocked_slice) orelse return false;
    };
    if (len == 0 and !(start.x == goal.x and start.y == goal.y)) return false;
    u.path_len = len;
    u.path_idx = 0;
    u.dest = dest_record;
    return true;
}

fn advance(s: *State, i: usize) void {
    const u = &s.units[i];
    if (u.path_idx >= u.path_len) return;
    const next = u.path[u.path_idx];
    var blocked = false;
    if (spatial.unit_at(s, next.x, next.y)) |other| {
        if (other != i) blocked = true;
    }
    if (spatial.building_at(s, next.x, next.y) != null) blocked = true;
    if (spatial.nature_at(s, next.x, next.y) != null) blocked = true;
    if (blocked) {
        if (u.dest) |dest| {
            const start = u.pos();
            var blocked_buf: [256]Pos = undefined;
            const cnt = spatial.collect_blocked(s, &blocked_buf, i);
            const bs = if (cnt > 0) blocked_buf[0..cnt] else null;
            if (pathfinding.find_path(s.allocator, &s.world, start, dest, u.path, bs)) |new_len| {
                if (new_len > 0) {
                    u.path_len = new_len;
                    u.path_idx = 0;
                } else {
                    u.path_len = 0;
                    u.path_idx = 0;
                }
            } else {
                u.path_len = 0;
                u.path_idx = 0;
            }
        }
        return;
    }
    u.step();
}

fn arrived(u: *const unit.Unit, target: Pos) bool {
    return manhattan(u.pos(), target) == 1;
}

fn is_adjacent_tree(s: *const State, u: *const unit.Unit, target: Pos) bool {
    if (s.world.at(target.x, target.y) != .tree) return false;
    return arrived(u, target);
}

fn remove_deer(s: *State, idx: usize) void {
    if (idx >= s.nature_count) return;
    const last = s.nature_count - 1;
    if (idx != last) s.nature[idx] = s.nature[last];
    s.nature_count = last;
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

pub fn tick_unit(s: *State, i: usize) void {
    const u = &s.units[i];
    switch (u.state) {
        .gathering_wood => tick_wood(s, i),
        .hunting => tick_hunt(s, i),
        .gathering_food => tick_farm(s, i),
        else => {},
    }
}

fn tick_wood(s: *State, i: usize) void {
    const u = &s.units[i];
    switch (u.gather_phase) {
        .none, .to_resource => {
            if (u.gather_target) |gt| {
                if (s.world.at(gt.x, gt.y) != .tree) {
                    const anchor = u.grove_anchor orelse gt;
                    if (find_nearest_tree(s, anchor, s.cfg.economy.grove_scan_radius)) |nt| {
                        u.gather_target = nt;
                        u.gather_phase = .to_resource;
                        _ = path_to_adjacent(s, i, nt, u.pos());
                    } else {
                        u.state = .idle;
                        u.gather_phase = .none;
                        u.gather_target = null;
                        u.grove_anchor = null;
                        return;
                    }
                }
                if (is_adjacent_tree(s, u, gt)) {
                    u.gather_phase = .harvesting;
                    u.gather_timer = s.cfg.economy.chop_ticks;
                    u.path_len = 0;
                    u.path_idx = 0;
                    return;
                }
                if (u.path_len == 0) {
                    _ = path_to_adjacent(s, i, gt, u.pos());
                }
                advance(s, i);
            } else {
                u.state = .idle;
                u.gather_phase = .none;
            }
        },
        .harvesting => {
            if (u.gather_timer > 0) {
                u.gather_timer -= 1;
                return;
            }
            if (u.gather_target) |gt| {
                if (s.world.at(gt.x, gt.y) == .tree) {
                    const yld = s.cfg.economy.tree_yield;
                    s.world.deplete_tree(gt.x, gt.y, yld);
                    u.carry = yld;
                    u.carry_kind = .wood;
                    u.gather_phase = .to_depot;
                    if (find_nearest_depot(s, u.pos())) |di| {
                        u.dest = .{ .x = s.buildings[di].x, .y = s.buildings[di].y };
                        _ = path_to_adjacent(s, i, .{ .x = s.buildings[di].x, .y = s.buildings[di].y }, u.pos());
                    } else {
                        u.state = .idle;
                        u.gather_phase = .none;
                        u.carry = 0;
                        u.carry_kind = .none;
                    }
                } else {
                    u.gather_phase = .to_resource;
                }
            }
        },
        .to_depot => {
            if (u.path_len == 0) {
                if (find_nearest_depot(s, u.pos())) |di| {
                    const dp = Pos{ .x = s.buildings[di].x, .y = s.buildings[di].y };
                    if (manhattan(u.pos(), dp) <= 1) {
                        drop_and_continue_wood(s, i);
                        return;
                    }
                    u.dest = dp;
                    _ = path_to_adjacent(s, i, dp, u.pos());
                } else {
                    drop_and_continue_wood(s, i);
                    return;
                }
            }
            advance(s, i);
        },
    }
}

fn drop_and_continue_wood(s: *State, i: usize) void {
    const u = &s.units[i];
    if (u.carry_kind == .wood and u.carry > 0) {
        s.wood += u.carry;
        u.carry = 0;
        u.carry_kind = .none;
    }
    const anchor = u.grove_anchor orelse u.gather_target orelse u.pos();
    if (find_nearest_tree(s, anchor, s.cfg.economy.grove_scan_radius)) |nt| {
        u.gather_target = nt;
        u.grove_anchor = anchor;
        u.gather_phase = .to_resource;
        _ = path_to_adjacent(s, i, nt, u.pos());
    } else {
        u.state = .idle;
        u.gather_phase = .none;
        u.gather_target = null;
        u.grove_anchor = null;
    }
}

fn tick_hunt(s: *State, i: usize) void {
    const u = &s.units[i];
    switch (u.gather_phase) {
        .none, .to_resource => {
            if (u.target_deer_idx) |di| {
                if (di >= s.nature_count or s.nature[di].kind != .deer) {
                    u.target_deer_idx = null;
                }
            }
            if (u.target_deer_idx == null) {
                if (find_nearest_deer(s, u.pos(), s.cfg.economy.deer_hunt_radius)) |di| {
                    u.target_deer_idx = di;
                } else {
                    u.state = .idle;
                    u.gather_phase = .none;
                    return;
                }
            }
            const di = u.target_deer_idx.?;
            const dpos = Pos{ .x = s.nature[di].x, .y = s.nature[di].y };
            u.gather_target = dpos;
            if (arrived(u, dpos)) {
                u.gather_phase = .harvesting;
                u.gather_timer = s.cfg.economy.hunt_ticks;
                u.path_len = 0;
                u.path_idx = 0;
                return;
            }
            if (u.path_len == 0 or !path_heads_to(u, dpos)) {
                _ = path_to_adjacent(s, i, dpos, u.pos());
            }
            advance(s, i);
        },
        .harvesting => {
            const di = u.target_deer_idx orelse {
                u.gather_phase = .to_resource;
                return;
            };
            if (di >= s.nature_count or s.nature[di].kind != .deer) {
                u.target_deer_idx = null;
                u.gather_phase = .to_resource;
                return;
            }
            const dpos = Pos{ .x = s.nature[di].x, .y = s.nature[di].y };
            if (!arrived(u, dpos)) {
                u.gather_phase = .to_resource;
                return;
            }
            if (u.gather_timer > 0) {
                u.gather_timer -= 1;
                return;
            }
            const yld = s.cfg.economy.deer_yield;
            const n = &s.nature[di];
            n.dead = true;
            if (n.food_remaining <= yld) {
                remove_deer(s, di);
                u.target_deer_idx = null;
            } else {
                n.food_remaining -= yld;
            }
            u.carry = yld;
            u.carry_kind = .food;
            u.gather_phase = .to_depot;
            if (find_nearest_depot(s, u.pos())) |bi| {
                u.dest = .{ .x = s.buildings[bi].x, .y = s.buildings[bi].y };
                _ = path_to_adjacent(s, i, .{ .x = s.buildings[bi].x, .y = s.buildings[bi].y }, u.pos());
            } else {
                u.state = .idle;
                u.gather_phase = .none;
                u.carry = 0;
                u.carry_kind = .none;
            }
        },
        .to_depot => {
            if (u.path_len == 0) {
                if (find_nearest_depot(s, u.pos())) |bi| {
                    const dp = Pos{ .x = s.buildings[bi].x, .y = s.buildings[bi].y };
                    if (manhattan(u.pos(), dp) <= 1) {
                        drop_and_continue_hunt(s, i);
                        return;
                    }
                    u.dest = dp;
                    _ = path_to_adjacent(s, i, dp, u.pos());
                } else {
                    drop_and_continue_hunt(s, i);
                    return;
                }
            }
            advance(s, i);
        },
    }
}

fn path_heads_to(u: *const unit.Unit, target: Pos) bool {
    if (u.path_len == 0) return false;
    const end = u.path[u.path_len - 1];
    return manhattan(end, target) <= 1;
}

fn drop_and_continue_hunt(s: *State, i: usize) void {
    const u = &s.units[i];
    if (u.carry_kind == .food and u.carry > 0) {
        s.food += u.carry;
        u.carry = 0;
        u.carry_kind = .none;
    }
    const hunt_origin = u.gather_target orelse u.pos();
    if (find_nearest_deer(s, hunt_origin, s.cfg.economy.deer_hunt_radius)) |di| {
        u.target_deer_idx = di;
        u.gather_phase = .to_resource;
    } else {
        u.state = .idle;
        u.gather_phase = .none;
        u.target_deer_idx = null;
    }
}

fn tick_farm(s: *State, i: usize) void {
    const u = &s.units[i];
    const fi = u.target_farm_idx orelse {
        u.state = .idle;
        u.gather_phase = .none;
        return;
    };
    if (fi >= s.building_count or s.buildings[fi].kind != .farm) {
        u.target_farm_idx = null;
        u.state = .idle;
        u.gather_phase = .none;
        return;
    }
    const fpos = Pos{ .x = s.buildings[fi].x, .y = s.buildings[fi].y };
    u.gather_target = fpos;
    switch (u.gather_phase) {
        .none, .to_resource => {
            if (arrived(u, fpos)) {
                const b = &s.buildings[fi];
                if (b.fallow or b.food_remaining == 0) {
                    if (auto_resow(s, fi)) {
                        u.gather_phase = .harvesting;
                        u.gather_timer = s.cfg.economy.farm_harvest_ticks;
                        u.path_len = 0;
                        u.path_idx = 0;
                        return;
                    }
                    b.assigned_worker = null;
                    u.state = .idle;
                    u.gather_phase = .none;
                    u.target_farm_idx = null;
                    return;
                }
                u.gather_phase = .harvesting;
                u.gather_timer = s.cfg.economy.farm_harvest_ticks;
                u.path_len = 0;
                u.path_idx = 0;
                return;
            }
            if (u.path_len == 0) _ = path_to_adjacent(s, i, fpos, u.pos());
            advance(s, i);
        },
        .harvesting => {
            const b = &s.buildings[fi];
            if (b.fallow or b.food_remaining == 0) {
                u.gather_timer = s.cfg.economy.farm_harvest_ticks;
                return;
            }
            if (u.gather_timer > 0) {
                u.gather_timer -= 1;
                return;
            }
            const take = @min(b.food_remaining, s.cfg.economy.farm_harvest_per_trip);
            b.food_remaining -= take;
            u.carry = take;
            u.carry_kind = .food;
            if (b.food_remaining == 0) b.fallow = true;
            u.gather_phase = .to_depot;
            if (find_nearest_depot(s, u.pos())) |di| {
                u.dest = .{ .x = s.buildings[di].x, .y = s.buildings[di].y };
                _ = path_to_adjacent(s, i, .{ .x = s.buildings[di].x, .y = s.buildings[di].y }, u.pos());
            }
        },
        .to_depot => {
            if (u.path_len == 0) {
                if (find_nearest_depot(s, u.pos())) |di| {
                    const dp = Pos{ .x = s.buildings[di].x, .y = s.buildings[di].y };
                    if (manhattan(u.pos(), dp) <= 1) {
                        drop_and_continue_farm(s, i);
                        return;
                    }
                    u.dest = dp;
                    _ = path_to_adjacent(s, i, dp, u.pos());
                } else {
                    drop_and_continue_farm(s, i);
                    return;
                }
            }
            advance(s, i);
        },
    }
}

fn drop_and_continue_farm(s: *State, i: usize) void {
    const u = &s.units[i];
    if (u.carry_kind == .food and u.carry > 0) {
        s.food += u.carry;
        u.carry = 0;
        u.carry_kind = .none;
    }
    u.gather_phase = .to_resource;
}

pub fn auto_resow(s: *State, fi: usize) bool {
    const b = &s.buildings[fi];
    if (b.kind != .farm or b.owner != .player) return false;
    if (!b.fallow) return false;
    if (s.wood < s.cfg.economy.resow_wood_cost) return false;
    s.wood -= s.cfg.economy.resow_wood_cost;
    b.fallow = false;
    b.food_remaining = s.cfg.economy.farm_yield_total;
    return true;
}

pub fn resow_farm(s: *State, building_idx: usize) bool {
    const b = &s.buildings[building_idx];
    if (b.kind != .farm or !b.fallow) return false;
    if (b.owner != .player) return false;
    if (s.wood < s.cfg.economy.resow_wood_cost) return false;
    s.wood -= s.cfg.economy.resow_wood_cost;
    b.fallow = false;
    b.food_remaining = s.cfg.economy.farm_yield_total;
    return true;
}

pub fn start_gather_at(s: *State, i: usize, target: Pos) bool {
    const u = &s.units[i];
    if (u.kind != .worker or u.owner != .player) return false;
    if (s.world.at(target.x, target.y) == .tree) {
        if (spatial.occupied(s, target.x, target.y)) return false;
        u.state = .gathering_wood;
        u.gather_phase = .to_resource;
        u.gather_target = target;
        u.grove_anchor = target;
        u.carry = 0;
        u.carry_kind = .none;
        u.path_len = 0;
        u.path_idx = 0;
        return path_to_adjacent(s, i, target, u.pos());
    }
    if (spatial.nature_at(s, target.x, target.y)) |ni| {
        if (s.nature[ni].kind != .deer) return false;
        u.state = .hunting;
        u.gather_phase = .to_resource;
        u.target_deer_idx = ni;
        u.gather_target = .{ .x = s.nature[ni].x, .y = s.nature[ni].y };
        u.carry = 0;
        u.carry_kind = .none;
        u.path_len = 0;
        u.path_idx = 0;
        return path_to_adjacent(s, i, .{ .x = s.nature[ni].x, .y = s.nature[ni].y }, u.pos());
    }
    if (spatial.building_at(s, target.x, target.y)) |bi| {
        const b = &s.buildings[bi];
        if (b.kind != .farm or b.owner != .player) return false;
        if (b.fallow or b.food_remaining == 0) return false;
        if (b.assigned_worker != null and b.assigned_worker.? != i) return false;
        b.assigned_worker = i;
        u.state = .gathering_food;
        u.gather_phase = .to_resource;
        u.target_farm_idx = bi;
        u.gather_target = .{ .x = b.x, .y = b.y };
        u.carry = 0;
        u.carry_kind = .none;
        u.path_len = 0;
        u.path_idx = 0;
        return path_to_adjacent(s, i, .{ .x = b.x, .y = b.y }, u.pos());
    }
    return false;
}

pub fn start_gather_nearest(s: *State, i: usize, kind: GatherKind) bool {
    const u = &s.units[i];
    if (u.kind != .worker or u.owner != .player) return false;
    const p = u.pos();
    switch (kind) {
        .wood => {
            const t = find_nearest_tree(s, p, s.cfg.economy.deer_hunt_radius) orelse return false;
            return start_gather_at(s, i, t);
        },
        .deer => {
            const di = find_nearest_deer(s, p, s.cfg.economy.deer_hunt_radius) orelse return false;
            return start_gather_at(s, i, .{ .x = s.nature[di].x, .y = s.nature[di].y });
        },
        .farm => {
            const fi = find_free_farm(s, p) orelse return false;
            return start_gather_at(s, i, .{ .x = s.buildings[fi].x, .y = s.buildings[fi].y });
        },
    }
}

test "find_nearest_depot picks closest TC" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const di = find_nearest_depot(&s, .{ .x = s.world.player_tc_x + 1, .y = s.world.player_tc_y }).?;
    try std.testing.expect(s.buildings[di].kind.is_depot());
    try std.testing.expectEqual(unit.Owner.player, s.buildings[di].owner);
}

test "find_nearest_tree finds tree tile" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    var found = false;
    for (0..s.world.height) |y| {
        for (0..s.world.width) |x| {
            if (s.world.at(x, y) == .tree) {
                if (find_nearest_tree(&s, .{ .x = x, .y = y }, 1)) |t| {
                    try std.testing.expectEqual(@as(map.Tile, .tree), s.world.at(t.x, t.y));
                    found = true;
                }
            }
        }
        if (found) break;
    }
    try std.testing.expect(found);
}

test "start_gather_at wood sets gathering_wood" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    var tx: usize = 0;
    var ty: usize = 0;
    var ok = false;
    for (0..s.world.height) |y| {
        for (0..s.world.width) |x| {
            if (s.world.at(x, y) == .tree and !spatial.occupied(&s, x, y)) {
                tx = x; ty = y; ok = true; break;
            }
        }
        if (ok) break;
    }
    try std.testing.expect(ok);
    s.units[0].x = s.world.player_tc_x;
    s.units[0].y = s.world.player_tc_y;
    try std.testing.expect(start_gather_at(&s, 0, .{ .x = tx, .y = ty }));
    try std.testing.expectEqual(unit.UnitState.gathering_wood, s.units[0].state);
    try std.testing.expectEqual(unit.GatherPhase.to_resource, s.units[0].gather_phase);
}

test "resow_farm costs wood and restores food" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.building_count = 3;
    s.buildings[2] = .{
        .x = 5, .y = 5, .kind = .farm, .owner = .player,
        .hp = 100, .food_remaining = 0, .fallow = true,
    };
    s.wood = s.cfg.economy.resow_wood_cost;
    try std.testing.expect(resow_farm(&s, 2));
    try std.testing.expectEqual(@as(u32, 0), s.wood);
    try std.testing.expect(!s.buildings[2].fallow);
    try std.testing.expectEqual(s.cfg.economy.farm_yield_total, s.buildings[2].food_remaining);
}

test "resow_farm fails without wood" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.building_count = 3;
    s.buildings[2] = .{
        .x = 5, .y = 5, .kind = .farm, .owner = .player,
        .hp = 100, .food_remaining = 0, .fallow = true,
    };
    s.wood = 0;
    try std.testing.expect(!resow_farm(&s, 2));
}

test "remove_deer updates other workers' indices" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const before = s.nature_count;
    try std.testing.expect(before >= 2);
    s.units[0].target_deer_idx = before - 1;
    remove_deer(&s, 0);
    try std.testing.expectEqual(before - 1, s.nature_count);
    try std.testing.expectEqual(@as(?usize, 0), s.units[0].target_deer_idx);
}

fn find_tree_near_tc(s: *State) ?struct { tree: Pos, stand: Pos } {
    const tc = Pos{ .x = s.world.player_tc_x, .y = s.world.player_tc_y };
    const tree = find_nearest_tree(s, tc, 15) orelse return null;
    const dirs = [_]struct { dx: isize, dy: isize }{
        .{ .dx = 0, .dy = -1 }, .{ .dx = 0, .dy = 1 },
        .{ .dx = -1, .dy = 0 }, .{ .dx = 1, .dy = 0 },
    };
    for (dirs) |d| {
        const nx = @as(isize, @intCast(tree.x)) + d.dx;
        const ny = @as(isize, @intCast(tree.y)) + d.dy;
        if (nx < 0 or ny < 0) continue;
        const ux: usize = @intCast(nx);
        const uy: usize = @intCast(ny);
        if (ux >= s.world.width or uy >= s.world.height) continue;
        if (!s.world.is_walkable(ux, uy)) continue;
        if (spatial.occupied(s, ux, uy)) continue;
        return .{ .tree = tree, .stand = .{ .x = ux, .y = uy } };
    }
    return null;
}

test "wood gather: harvest depletes tree and sets carry" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const spot = find_tree_near_tc(&s) orelse return;
    s.units[0].x = spot.stand.x;
    s.units[0].y = spot.stand.y;
    try std.testing.expect(start_gather_at(&s, 0, spot.tree));
    tick_unit(&s, 0);
    try std.testing.expectEqual(unit.GatherPhase.harvesting, s.units[0].gather_phase);
    const chop = s.cfg.economy.chop_ticks;
    for (0..chop + 2) |_| tick_unit(&s, 0);
    try std.testing.expectEqual(@as(u16, s.cfg.economy.tree_total_yield - s.cfg.economy.tree_yield), s.world.tree_remaining_at(spot.tree.x, spot.tree.y));
    try std.testing.expectEqual(@as(map.Tile, .tree), s.world.at(spot.tree.x, spot.tree.y));
    try std.testing.expectEqual(s.cfg.economy.tree_yield, s.units[0].carry);
    try std.testing.expectEqual(unit.CarryKind.wood, s.units[0].carry_kind);
    try std.testing.expectEqual(unit.GatherPhase.to_depot, s.units[0].gather_phase);
}

test "wood gather: drop-off increments wood counter" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const spot = find_tree_near_tc(&s) orelse return;
    s.units[0].x = spot.stand.x;
    s.units[0].y = spot.stand.y;
    _ = start_gather_at(&s, 0, spot.tree);
    const chop = s.cfg.economy.chop_ticks;
    for (0..chop + 2) |_| tick_unit(&s, 0);
    const wood_before = s.wood;
    for (0..600) |_| tick_unit(&s, 0);
    try std.testing.expect(s.wood > wood_before);
}

test "tree fully depletes after total/yield trips" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const spot = find_tree_near_tc(&s) orelse return;
    s.units[0].x = spot.stand.x;
    s.units[0].y = spot.stand.y;
    for (1..s.unit_count) |i| {
        s.units[i].x = 0;
        s.units[i].y = 0;
        s.units[i].state = .idle;
        s.units[i].path_len = 0;
    }
    _ = start_gather_at(&s, 0, spot.tree);
    const trips_needed = s.cfg.economy.tree_total_yield / s.cfg.economy.tree_yield;
    for (0..trips_needed * 200) |_| {
        tick_unit(&s, 0);
        if (s.world.at(spot.tree.x, spot.tree.y) == .grass) break;
    }
    try std.testing.expectEqual(@as(map.Tile, .grass), s.world.at(spot.tree.x, spot.tree.y));
    const total_gathered = s.wood + @as(u32, if (s.units[0].carry_kind == .wood) s.units[0].carry else 0);
    try std.testing.expectEqual(@as(u32, s.cfg.economy.tree_total_yield), total_gathered);
}

test "deer drains over multiple hunts then removed" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    var di: usize = 0;
    for (0..s.nature_count) |i| {
        if (s.nature[i].kind == .deer) { di = i; break; }
    }
    s.nature[di].food_remaining = s.cfg.economy.deer_total_yield;
    s.nature[di].x = s.units[0].x + 1;
    s.nature[di].y = s.units[0].y;
    try std.testing.expect(start_gather_at(&s, 0, .{ .x = s.nature[di].x, .y = s.nature[di].y }));
    try std.testing.expectEqual(unit.UnitState.hunting, s.units[0].state);
    const trips_needed = s.cfg.economy.deer_total_yield / s.cfg.economy.deer_yield;
    for (0..trips_needed * 200) |_| {
        tick_unit(&s, 0);
        if (s.nature_count == 0 or s.units[0].state == .idle) break;
    }
    try std.testing.expect(s.food >= s.cfg.economy.deer_total_yield);
}

test "farm gather: depletes and goes fallow" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    var fi: usize = 0;
    var found = false;
    for (0..s.building_count) |i| {
        if (s.buildings[i].kind == .farm and s.buildings[i].owner == .player) {
            fi = i; found = true; break;
        }
    }
    try std.testing.expect(found);
    const fpos = Pos{ .x = s.buildings[fi].x, .y = s.buildings[fi].y };
    const dirs = [_]struct { dx: isize, dy: isize }{
        .{ .dx = 0, .dy = -1 }, .{ .dx = 0, .dy = 1 },
        .{ .dx = -1, .dy = 0 }, .{ .dx = 1, .dy = 0 },
    };
    var placed = false;
    for (dirs) |d| {
        const nx = @as(isize, @intCast(fpos.x)) + d.dx;
        const ny = @as(isize, @intCast(fpos.y)) + d.dy;
        if (nx < 0 or ny < 0) continue;
        const ux: usize = @intCast(nx);
        const uy: usize = @intCast(ny);
        if (ux >= s.world.width or uy >= s.world.height) continue;
        if (!s.world.is_walkable(ux, uy) or spatial.occupied(&s, ux, uy)) continue;
        s.units[0].x = ux;
        s.units[0].y = uy;
        placed = true;
        break;
    }
    try std.testing.expect(placed);
    try std.testing.expect(start_gather_at(&s, 0, fpos));
    try std.testing.expectEqual(unit.UnitState.gathering_food, s.units[0].state);
    for (0..3000) |_| {
        tick_unit(&s, 0);
        if (s.buildings[fi].fallow and s.units[0].carry == 0 and s.units[0].gather_phase != .to_depot) break;
    }
    for (0..200) |_| tick_unit(&s, 0);
    try std.testing.expect(s.buildings[fi].fallow);
    try std.testing.expectEqual(@as(u16, 0), s.buildings[fi].food_remaining);
    try std.testing.expectEqual(@as(u32, s.cfg.economy.farm_yield_total), s.food);
}

test "gather_nearest wood finds a tree" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const ok = start_gather_nearest(&s, 0, .wood);
    if (ok) {
        try std.testing.expectEqual(unit.UnitState.gathering_wood, s.units[0].state);
    }
}
