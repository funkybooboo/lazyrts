const std = @import("std");
const map = @import("map.zig");
const unit = @import("unit.zig");
const building = @import("building.zig");
const nature = @import("nature.zig");
const pathfinding = @import("pathfinding.zig");
const config = @import("config.zig");
const time = @import("time.zig");
const coord = @import("coord.zig");
const spatial = @import("spatial.zig");
const economy = @import("economy.zig");

pub const parse_coord = coord.parse_coord;
pub const col_to_letters = coord.col_to_letters;
pub const unit_at = spatial.unit_at;
pub const building_at = spatial.building_at;
pub const nature_at = spatial.nature_at;
pub const nature_at_except = spatial.nature_at_except;
pub const occupied = spatial.occupied;
pub const start_gather_at = economy.start_gather_at;
pub const start_gather_nearest = economy.start_gather_nearest;
pub const resow_farm = economy.resow_farm;
pub const GatherKind = economy.GatherKind;

const MAX_SELECT: usize = 128;

pub fn header_height(map_w: usize) u16 {
    var buf: [3]u8 = undefined;
    const letters = col_to_letters(map_w -| 1, &buf);
    return @as(u16, @intCast(letters.len));
}

pub const State = struct {
    allocator: std.mem.Allocator,
    cursor_x: usize = 0,
    cursor_y: usize = 0,
    quit: bool = false,
    world: map.GameMap,
    units: []unit.Unit,
    unit_count: usize = 0,
    buildings: []building.Building,
    building_count: usize = 0,
    nature: []nature.Nature,
    nature_count: usize = 0,
    selected: [MAX_SELECT]usize = @splat(0),
    selected_count: usize = 0,
    selected_building: ?usize = null,
    food: u32 = 0,
    wood: u32 = 0,
    coord_mode: bool = false,
    coord_buf: [5]u8 = @splat(0),
    coord_len: usize = 0,
    gather_mode: bool = false,
    tick_count: usize = 0,
    cfg: *const config.Config,

    pub fn init(allocator: std.mem.Allocator, seed: u64, term_w: u16, term_h: u16, cfg: *const config.Config) !State {
        const term_width: usize = if (term_w < cfg.map_dims.min_term_width) cfg.map_dims.default_width else term_w;
        const term_height: usize = if (term_h < cfg.map_dims.min_term_height) cfg.map_dims.default_height else term_h;

        const map_w: u16 = if (term_width > cfg.ui.label_width) @intCast(term_width - cfg.ui.label_width) else 10;
        const header_h: u16 = header_height(map_w);
        const map_area_h = term_height -| cfg.ui.drawer_height -| header_h;
        const map_h: u16 = if (map_area_h > 0) @intCast(map_area_h) else 10;

        const world = try map.GameMap.init(allocator, seed, map_w, map_h, cfg);

        const units = try allocator.alloc(unit.Unit, cfg.entity_limits.max_units);
        errdefer allocator.free(units);
        const buildings = try allocator.alloc(building.Building, cfg.entity_limits.max_buildings);
        errdefer allocator.free(buildings);
        const nature_arr = try allocator.alloc(nature.Nature, cfg.entity_limits.max_nature);
        errdefer allocator.free(nature_arr);

        var s: State = .{
            .allocator = allocator,
            .world = world,
            .units = units,
            .buildings = buildings,
            .nature = nature_arr,
            .cfg = cfg,
        };

        for (s.units) |*u| {
            u.* = .{
                .x = 0,
                .y = 0,
                .kind = .worker,
                .owner = .player,
                .hp = 0,
                .state = .idle,
                .path = &[_]unit.Pos{},
                .path_len = 0,
                .path_idx = 0,
            };
        }

        try init_starting_buildings(&s);
        try init_starting_workers(&s);
        try allocate_unit_paths(&s);
        try place_starting_farm(&s);

        s.food = s.cfg.starting_food;
        s.wood = s.cfg.starting_wood;

        select_single(&s, 0);
        spawn_deer(&s);

        s.cursor_x = s.world.player_tc_x;
        s.cursor_y = s.world.player_tc_y;

        return s;
    }

    pub fn deinit(self: *State) void {
        for (0..self.unit_count) |i| {
            self.allocator.free(self.units[i].path);
        }
        self.allocator.free(self.units);
        self.allocator.free(self.buildings);
        self.allocator.free(self.nature);
        self.world.deinit(self.allocator);
    }
};

fn init_starting_buildings(s: *State) !void {
    const starting_buildings = [_]struct { tc_x: usize, tc_y: usize, owner: unit.Owner }{
        .{ .tc_x = s.world.player_tc_x, .tc_y = s.world.player_tc_y, .owner = .player },
        .{ .tc_x = s.world.enemy_tc_x, .tc_y = s.world.enemy_tc_y, .owner = .enemy },
    };
    for (starting_buildings, 0..) |def, i| {
        s.buildings[i] = .{
            .x = def.tc_x,
            .y = def.tc_y,
            .kind = .town_center,
            .owner = def.owner,
            .hp = building.max_hp(.town_center, s.cfg),
        };
    }
    s.building_count = starting_buildings.len;
}

fn place_starting_farm(s: *State) !void {
    const tc_x = s.world.player_tc_x;
    const tc_y = s.world.player_tc_y;
    const offsets = [_]struct { dx: isize, dy: isize }{
        .{ .dx = 3, .dy = 0 },  .{ .dx = -3, .dy = 0 },
        .{ .dx = 0, .dy = 3 },  .{ .dx = 0, .dy = -3 },
        .{ .dx = 4, .dy = 0 },  .{ .dx = -4, .dy = 0 },
        .{ .dx = 0, .dy = 4 },  .{ .dx = 0, .dy = -4 },
    };
    for (offsets) |o| {
        const fx = @as(isize, @intCast(tc_x)) + o.dx;
        const fy = @as(isize, @intCast(tc_y)) + o.dy;
        if (fx < 0 or fy < 0) continue;
        const ux: usize = @intCast(fx);
        const uy: usize = @intCast(fy);
        if (ux >= s.world.width or uy >= s.world.height) continue;
        if (!s.world.is_walkable(ux, uy)) continue;
        if (spatial.occupied(s, ux, uy)) continue;
        if (s.building_count >= s.cfg.entity_limits.max_buildings) return;
        s.buildings[s.building_count] = .{
            .x = ux,
            .y = uy,
            .kind = .farm,
            .owner = .player,
            .hp = building.max_hp(.farm, s.cfg),
            .food_remaining = s.cfg.economy.farm_yield_total,
            .fallow = false,
        };
        s.building_count += 1;
        return;
    }
}

fn init_starting_workers(s: *State) !void {
    const starting_order = [_]struct { cx: usize, cy: usize, owner: unit.Owner }{
        .{ .cx = s.world.player_tc_x, .cy = s.world.player_tc_y, .owner = .player },
        .{ .cx = s.world.player_tc_x, .cy = s.world.player_tc_y, .owner = .player },
        .{ .cx = s.world.enemy_tc_x, .cy = s.world.enemy_tc_y, .owner = .enemy },
        .{ .cx = s.world.enemy_tc_x, .cy = s.world.enemy_tc_y, .owner = .enemy },
    };
    for (starting_order, 0..) |def, i| {
        const sp = find_spawn(s, def.cx, def.cy) orelse continue;
        s.units[i] = .{
            .x = sp.x,
            .y = sp.y,
            .kind = .worker,
            .owner = def.owner,
            .hp = unit.max_hp(.worker, s.cfg),
        };
        s.unit_count = i + 1;
    }
}

fn allocate_unit_paths(s: *State) !void {
    for (0..s.unit_count) |i| {
        s.units[i].path = s.allocator.alloc(unit.Pos, s.cfg.entity_limits.max_path) catch {
            for (0..i) |j| s.allocator.free(s.units[j].path);
            s.allocator.free(s.units);
            s.allocator.free(s.buildings);
            s.allocator.free(s.nature);
            s.world.deinit(s.allocator);
            return error.OutOfMemory;
        };
    }
}

pub fn move_cursor(s: *State, dx: isize, dy: isize) void {
    const max_x: isize = @intCast(s.world.width -| 1);
    const max_y: isize = @intCast(s.world.height -| 1);
    const next_x = @max(0, @min(@as(isize, @intCast(s.cursor_x)) + dx, max_x));
    const next_y = @max(0, @min(@as(isize, @intCast(s.cursor_y)) + dy, max_y));
    s.cursor_x = @intCast(next_x);
    s.cursor_y = @intCast(next_y);
}

pub fn tick(s: *State) void {
    s.tick_count += 1;

    var blocked_buf: [256]unit.Pos = undefined;

    for (0..s.unit_count) |i| {
        const u = &s.units[i];
        switch (u.state) {
            .moving => {
                if (u.path_idx < u.path_len) {
                    const next = u.path[u.path_idx];
                    var blocked = false;
                    if (unit_at(s, next.x, next.y)) |other| {
                        if (other != i) blocked = true;
                    }
                    if (building_at(s, next.x, next.y) != null) blocked = true;
                    if (nature_at(s, next.x, next.y) != null) blocked = true;

                    if (blocked) {
                        if (u.dest) |dest| {
                            const current = u.pos();
                            const blocked_count = spatial.collect_blocked(s, &blocked_buf, i);
                            const blocked_slice = if (blocked_count > 0) blocked_buf[0..blocked_count] else null;

                            if (pathfinding.find_path(s.allocator, &s.world, current, dest, u.path, blocked_slice)) |new_len| {
                                if (new_len > 0) {
                                    u.path_len = new_len;
                                    u.path_idx = 0;
                                } else {
                                    u.state = .idle;
                                }
                            } else {
                                u.state = .idle;
                            }
                        }
                        continue;
                    }
                }
                u.step();
            },
            .gathering_wood, .gathering_food, .hunting => economy.tick_unit(s, i),
            else => {},
        }
    }
    for (0..s.nature_count) |i| {
        nature.wander(&s.nature[i], s.world, s, s.tick_count, i, s.cfg);
    }
}

fn spawn_deer(s: *State) void {
    var rng = std.Random.DefaultPrng.init(s.tick_count + s.cfg.deer.spawn_seed_offset);
    const rand = rng.random();

    const tc_positions = [_]struct { x: usize, y: usize }{
        .{ .x = s.world.player_tc_x, .y = s.world.player_tc_y },
        .{ .x = s.world.enemy_tc_x, .y = s.world.enemy_tc_y },
    };

    for (tc_positions) |tc| {
        place_herd_near(s, rand, tc.x, tc.y, s.cfg.deer.herd_size, s.cfg.deer.tc_herd_offset, s.cfg.deer.herd_radius);
    }

    const herds = s.cfg.deer.scatter_herd_count;
    const herd_size = s.cfg.deer.herd_size;
    const radius = s.cfg.deer.herd_radius;
    const min_dist = s.cfg.deer.herd_min_spacing;
    var centers: [64]unit.Pos = undefined;
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
            if (dx + dy < min_dist) { too_close = true; break; }
        }
        if (too_close) continue;
        const placed = place_cluster(s, rand, cx, cy, herd_size, radius, true);
        if (placed > 0) {
            centers[center_count] = .{ .x = cx, .y = cy };
            center_count += 1;
            h += 1;
        }
    }
}

fn place_herd_near(s: *State, rand: std.Random, tc_x: usize, tc_y: usize, size: usize, offset: usize, radius: usize) void {
    const dirs = [_]struct { dx: isize, dy: isize }{
        .{ .dx = 1, .dy = 0 },  .{ .dx = -1, .dy = 0 },
        .{ .dx = 0, .dy = 1 },  .{ .dx = 0, .dy = -1 },
    };
    const d = dirs[rand.intRangeAtMost(usize, 0, dirs.len - 1)];
    const cx: isize = @as(isize, @intCast(tc_x)) + d.dx * @as(isize, @intCast(offset));
    const cy: isize = @as(isize, @intCast(tc_y)) + d.dy * @as(isize, @intCast(offset));
    if (cx < 0 or cy < 0) return;
    const ux: usize = @intCast(cx);
    const uy: usize = @intCast(cy);
    if (ux >= s.world.width or uy >= s.world.height) return;
    _ = place_cluster(s, rand, ux, uy, size, radius, false);
}

fn place_cluster(s: *State, rand: std.Random, cx: usize, cy: usize, size: usize, radius: usize, avoid_tc: bool) usize {
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
        if (!s.world.is_walkable(fx, fy) or occupied(s, fx, fy)) continue;
        if (avoid_tc and s.world.near_tc(fx, fy, s.cfg.deer.scatter_min_dist)) continue;
        if (spawn_deer_in_herd(s, fx, fy, cx, cy)) placed += 1;
    }
    return placed;
}

fn spawn_deer_in_herd(s: *State, x: usize, y: usize, cx: usize, cy: usize) bool {
    if (!spawn_nature(s, .deer, x, y)) return false;
    const n = &s.nature[s.nature_count - 1];
    n.herd_cx = cx;
    n.herd_cy = cy;
    n.herd_radius = s.cfg.deer.herd_wander_radius;
    return true;
}

pub fn spawn_nature(s: *State, kind: nature.NatureKind, x: usize, y: usize) bool {
    if (s.nature_count >= s.cfg.entity_limits.max_nature) return false;
    s.nature[s.nature_count] = .{
        .x = x,
        .y = y,
        .kind = kind,
        .hp = nature.max_hp(kind, s.cfg),
        .food_remaining = nature.max_food(kind, s.cfg),
    };
    s.nature_count += 1;
    return true;
}

pub fn spawn_unit(s: *State, kind: unit.UnitKind, owner: unit.Owner, center_x: usize, center_y: usize) bool {
    if (s.unit_count >= s.cfg.entity_limits.max_units) return false;

    const spawn = find_spawn(s, center_x, center_y) orelse return false;

    const path_buf = s.allocator.alloc(unit.Pos, s.cfg.entity_limits.max_path) catch return false;
    s.units[s.unit_count] = .{
        .x = spawn.x,
        .y = spawn.y,
        .kind = kind,
        .owner = owner,
        .hp = unit.max_hp(kind, s.cfg),
        .path = path_buf,
    };
    if (owner == .player) {
        select_single(s, s.unit_count);
    }
    s.unit_count += 1;
    return true;
}

pub fn spawn_worker(s: *State) bool {
    const tc = player_tc(s) orelse return false;
    return spawn_unit(s, .worker, .player, tc.x, tc.y);
}

pub fn move_selected(s: *State) void {
    if (s.selected_count == 0) return;
    for (0..s.selected_count) |si| {
        const i = s.selected[si];
        const u = &s.units[i];
        if (u.owner != .player) continue;
        const start = u.pos();
        const goal = unit.Pos{ .x = s.cursor_x, .y = s.cursor_y };

        var blocked_buf: [256]unit.Pos = undefined;
        const blocked_count = spatial.collect_blocked(s, &blocked_buf, i);
        const blocked_slice = if (blocked_count > 0) blocked_buf[0..blocked_count] else null;

        var target = goal;
        const len = pathfinding.find_path(s.allocator, &s.world, start, goal, u.path, blocked_slice) orelse blk: {
            const nearest = pathfinding.find_nearest_reachable(s.allocator, &s.world, goal, blocked_slice) orelse continue;
            target = nearest;
            break :blk pathfinding.find_path(s.allocator, &s.world, start, nearest, u.path, blocked_slice) orelse continue;
        };
        if (len == 0) continue;
        u.path_len = len;
        u.path_idx = 0;
        u.state = .moving;
        u.dest = target;
    }
}

pub fn select_single(s: *State, idx: usize) void {
    s.selected[0] = idx;
    s.selected_count = 1;
    s.selected_building = null;
}

pub fn select_clear(s: *State) void {
    s.selected_count = 0;
    s.selected_building = null;
}

pub fn is_unit_selected(s: *const State, idx: usize) bool {
    for (0..s.selected_count) |i| {
        if (s.selected[i] == idx) return true;
    }
    return false;
}

pub fn primary_selected(s: *const State) ?usize {
    if (s.selected_count == 0) return null;
    return s.selected[0];
}

pub fn select_add(s: *State, idx: usize) void {
    if (idx >= s.unit_count) return;
    if (s.units[idx].owner != .player) return;
    if (is_unit_selected(s, idx)) return;
    if (s.selected_count >= MAX_SELECT) return;
    s.selected[s.selected_count] = idx;
    s.selected_count += 1;
    s.selected_building = null;
}

pub fn select_next(s: *State) void {
    if (s.unit_count == 0) {
        s.selected_count = 0;
        return;
    }
    const start: usize = if (primary_selected(s)) |sel|
        (sel + 1) % s.unit_count
    else
        0;
    var i: usize = start;
    while (true) {
        if (s.units[i].owner == .player) {
            select_single(s, i);
            return;
        }
        i = (i + 1) % s.unit_count;
        if (i == start) break;
    }
    s.selected_count = 0;
}

pub fn select_prev(s: *State) void {
    if (s.unit_count == 0) {
        s.selected_count = 0;
        return;
    }
    const start: usize = if (primary_selected(s)) |sel|
        if (sel == 0) s.unit_count - 1 else sel - 1
    else
        s.unit_count - 1;
    var i: usize = start;
    while (true) {
        if (s.units[i].owner == .player) {
            select_single(s, i);
            return;
        }
        i = if (i == 0) s.unit_count - 1 else i - 1;
        if (i == start) break;
    }
    s.selected_count = 0;
}

pub fn select_idle_workers(s: *State) void {
    s.selected_count = 0;
    s.selected_building = null;
    for (0..s.unit_count) |i| {
        if (s.selected_count >= MAX_SELECT) break;
        const u = &s.units[i];
        if (u.owner != .player or u.kind != .worker) continue;
        if (u.state != .idle) continue;
        s.selected[s.selected_count] = i;
        s.selected_count += 1;
    }
}

pub fn select_all_workers(s: *State) void {
    s.selected_count = 0;
    s.selected_building = null;
    for (0..s.unit_count) |i| {
        if (s.selected_count >= MAX_SELECT) break;
        const u = &s.units[i];
        if (u.owner != .player or u.kind != .worker) continue;
        s.selected[s.selected_count] = i;
        s.selected_count += 1;
    }
}

pub fn select_next_building(s: *State) void {
    if (s.building_count == 0) {
        s.selected_building = null;
        return;
    }
    const start: usize = if (s.selected_building) |sel|
        (sel + 1) % s.building_count
    else
        0;
    var i: usize = start;
    while (true) {
        if (s.buildings[i].owner == .player) {
            s.selected_building = i;
            s.selected_count = 0;
            return;
        }
        i = (i + 1) % s.building_count;
        if (i == start) break;
    }
    s.selected_building = null;
}

pub fn select_prev_building(s: *State) void {
    if (s.building_count == 0) {
        s.selected_building = null;
        return;
    }
    const start: usize = if (s.selected_building) |sel|
        if (sel == 0) s.building_count - 1 else sel - 1
    else
        s.building_count - 1;
    var i: usize = start;
    while (true) {
        if (s.buildings[i].owner == .player) {
            s.selected_building = i;
            s.selected_count = 0;
            return;
        }
        i = if (i == 0) s.building_count - 1 else i - 1;
        if (i == start) break;
    }
    s.selected_building = null;
}

pub fn gather_at_cursor(s: *State) void {
    const target = unit.Pos{ .x = s.cursor_x, .y = s.cursor_y };
    if (s.selected_count == 0) return;
    for (0..s.selected_count) |si| {
        const i = s.selected[si];
        _ = economy.start_gather_at(s, i, target);
    }
}

pub fn gather_nearest(s: *State, kind: economy.GatherKind) void {
    if (s.selected_count == 0) return;
    for (0..s.selected_count) |si| {
        const i = s.selected[si];
        _ = economy.start_gather_nearest(s, i, kind);
    }
}

pub fn resow_selected(s: *State) bool {
    if (s.selected_building) |bi| {
        return economy.resow_farm(s, bi);
    }
    const bi = spatial.building_at(s, s.cursor_x, s.cursor_y) orelse return false;
    return economy.resow_farm(s, bi);
}

pub fn player_tc(s: *const State) ?unit.Pos {
    for (0..s.building_count) |i| {
        if (s.buildings[i].kind == .town_center and s.buildings[i].owner == .player) {
            return .{ .x = s.buildings[i].x, .y = s.buildings[i].y };
        }
    }
    return null;
}

pub fn player_pop(s: *const State) usize {
    var count: usize = 0;
    for (0..s.unit_count) |i| {
        if (s.units[i].owner == .player) count += 1;
    }
    return count;
}

pub fn player_pop_cap(s: *const State) usize {
    var cap: usize = 0;
    for (0..s.building_count) |i| {
        if (s.buildings[i].owner == .player and s.buildings[i].is_complete()) {
            cap += switch (s.buildings[i].kind) {
                .town_center, .house => s.cfg.pop_per_housing,
                else => 0,
            };
        }
    }
    return cap;
}

pub fn player_unit_counts(s: *const State) struct { workers: usize, soldiers: usize } {
    var worker_count: usize = 0;
    var soldier_count: usize = 0;
    for (0..s.unit_count) |i| {
        if (s.units[i].owner == .player) {
            switch (s.units[i].kind) {
                .worker => worker_count += 1,
                .soldier => soldier_count += 1,
            }
        }
    }
    return .{ .workers = worker_count, .soldiers = soldier_count };
}

pub fn elapsed_seconds(s: *const State) usize {
    return time.ticks_to_seconds(s.tick_count, s.cfg.tick_rate);
}

fn find_spawn(s: *const State, center_x: usize, center_y: usize) ?unit.Pos {
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
        if (!s.world.is_walkable(ux, uy)) continue;
        if (occupied(s, ux, uy)) continue;
        return .{ .x = ux, .y = uy };
    }
    return null;
}

test "move_cursor clamps to bounds" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 1, 80, 45, &cfg);
    defer s.deinit();
    s.cursor_x = 0;
    s.cursor_y = 0;
    move_cursor(&s, -1, 0);
    try std.testing.expectEqual(@as(usize, 0), s.cursor_x);

    s.cursor_x = s.world.width - 1;
    move_cursor(&s, 1, 0);
    try std.testing.expectEqual(s.world.width - 1, s.cursor_x);

    s.cursor_y = 0;
    move_cursor(&s, 0, -1);
    try std.testing.expectEqual(@as(usize, 0), s.cursor_y);

    s.cursor_y = s.world.height - 1;
    move_cursor(&s, 0, 1);
    try std.testing.expectEqual(s.world.height - 1, s.cursor_y);
}

test "init places both TCs as buildings" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    const s = try State.init(allocator, 42, 80, 45, &cfg);
    defer {
        var mut_s = s;
        mut_s.deinit();
    }
    try std.testing.expectEqual(@as(usize, 2), s.building_count - count_player_farms(&s));
    try std.testing.expectEqual(building.BuildingKind.town_center, s.buildings[0].kind);
    try std.testing.expectEqual(unit.Owner.player, s.buildings[0].owner);
    try std.testing.expectEqual(building.BuildingKind.town_center, s.buildings[1].kind);
    try std.testing.expectEqual(unit.Owner.enemy, s.buildings[1].owner);
}

fn count_player_farms(s: *const State) usize {
    var n: usize = 0;
    for (0..s.building_count) |i| {
        if (s.buildings[i].kind == .farm and s.buildings[i].owner == .player) n += 1;
    }
    return n;
}

test "init spawns starting workers" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    const s = try State.init(allocator, 42, 80, 45, &cfg);
    defer {
        var mut_s = s;
        mut_s.deinit();
    }
    var player_workers: usize = 0;
    var enemy_workers: usize = 0;
    for (0..s.unit_count) |i| {
        if (s.units[i].owner == .player and s.units[i].kind == .worker) player_workers += 1;
        if (s.units[i].owner == .enemy and s.units[i].kind == .worker) enemy_workers += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), player_workers);
    try std.testing.expectEqual(@as(usize, 2), enemy_workers);
}

test "init spawns deer" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    const s = try State.init(allocator, 42, 80, 45, &cfg);
    defer {
        var mut_s = s;
        mut_s.deinit();
    }
    try std.testing.expect(s.nature_count > 0);
}

test "init buildings start complete" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    const s = try State.init(allocator, 42, 80, 45, &cfg);
    defer {
        var mut_s = s;
        mut_s.deinit();
    }
    for (0..s.building_count) |i| {
        try std.testing.expect(s.buildings[i].is_complete());
    }
}

test "spawn_worker adds unit and selects it" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const before = s.unit_count;
    try std.testing.expect(spawn_worker(&s));
    try std.testing.expectEqual(before + 1, s.unit_count);
    try std.testing.expectEqual(unit.UnitKind.worker, s.units[s.unit_count - 1].kind);
    try std.testing.expectEqual(unit.Owner.player, s.units[s.unit_count - 1].owner);
}

test "select_add builds multiselect" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    var player_idxs: [8]usize = undefined;
    var pn: usize = 0;
    for (0..s.unit_count) |i| {
        if (s.units[i].owner == .player and pn < 8) {
            player_idxs[pn] = i;
            pn += 1;
        }
    }
    try std.testing.expect(pn >= 2);
    select_single(&s, player_idxs[0]);
    select_add(&s, player_idxs[1]);
    try std.testing.expectEqual(@as(usize, 2), s.selected_count);
    try std.testing.expect(is_unit_selected(&s, player_idxs[1]));
}

test "select_idle_workers selects only idle workers" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.units[0].state = .moving;
    select_idle_workers(&s);
    for (0..s.selected_count) |i| {
        try std.testing.expectEqual(unit.UnitState.idle, s.units[s.selected[i]].state);
        try std.testing.expectEqual(unit.UnitKind.worker, s.units[s.selected[i]].kind);
    }
}

test "select_next_building cycles player buildings" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    select_next_building(&s);
    const b = s.selected_building.?;
    try std.testing.expectEqual(unit.Owner.player, s.buildings[b].owner);
}

test "is_unit_selected and primary_selected" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    select_clear(&s);
    try std.testing.expect(primary_selected(&s) == null);
    select_single(&s, 0);
    try std.testing.expectEqual(@as(?usize, 0), primary_selected(&s));
    try std.testing.expect(is_unit_selected(&s, 0));
    try std.testing.expect(!is_unit_selected(&s, 1));
}

test "tick moves unit along path" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.units[0].x = 5;
    s.units[0].y = 5;
    s.units[0].path[0] = .{ .x = 6, .y = 5 };
    s.units[0].path[1] = .{ .x = 7, .y = 5 };
    s.units[0].path_len = 2;
    s.units[0].path_idx = 0;
    s.units[0].state = .moving;

    tick(&s);
    try std.testing.expectEqual(@as(usize, 6), s.units[0].x);
    try std.testing.expectEqual(unit.UnitState.moving, s.units[0].state);

    tick(&s);
    try std.testing.expectEqual(@as(usize, 7), s.units[0].x);
    try std.testing.expectEqual(unit.UnitState.idle, s.units[0].state);
}

test "select_next cycles through player units" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const first = primary_selected(&s).?;
    select_next(&s);
    const second = primary_selected(&s).?;
    try std.testing.expect(first != second);
}

test "unit_at finds unit at position" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    const s = try State.init(allocator, 42, 80, 45, &cfg);
    defer {
        var mut_s = s;
        mut_s.deinit();
    }
    const ux = s.units[0].x;
    const uy = s.units[0].y;
    try std.testing.expect(unit_at(&s, ux, uy) != null);
}

test "unit_at returns null for empty position" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    const s = try State.init(allocator, 42, 80, 45, &cfg);
    defer {
        var mut_s = s;
        mut_s.deinit();
    }
    try std.testing.expect(unit_at(&s, 0, 0) == null or !s.world.is_walkable(0, 0));
}

test "player_tc returns player town center position" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const tc = player_tc(&s).?;
    try std.testing.expectEqual(@as(usize, s.world.player_tc_x), tc.x);
    try std.testing.expectEqual(@as(usize, s.world.player_tc_y), tc.y);
}

test "building_at finds buildings at TC positions" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    const s = try State.init(allocator, 42, 80, 45, &cfg);
    defer {
        var mut_s = s;
        mut_s.deinit();
    }
    try std.testing.expect(building_at(&s, s.world.player_tc_x, s.world.player_tc_y) != null);
    try std.testing.expect(building_at(&s, s.world.enemy_tc_x, s.world.enemy_tc_y) != null);
}

test "building_at returns null for empty position" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    const s = try State.init(allocator, 42, 80, 45, &cfg);
    defer {
        var mut_s = s;
        mut_s.deinit();
    }
    try std.testing.expect(building_at(&s, 0, 0) == null);
}

test "player_pop counts player units" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    try std.testing.expectEqual(@as(usize, 2), player_pop(&s));
}

test "player_pop_cap counts from buildings" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    try std.testing.expectEqual(@as(usize, 5), player_pop_cap(&s));
}

test "player_pop_cap ignores incomplete buildings" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.buildings[0].build_progress = 50;
    try std.testing.expectEqual(@as(usize, 0), player_pop_cap(&s));
}

test "move_selected sets unit on path" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.units[0].x = s.world.player_tc_x + 1;
    s.units[0].y = s.world.player_tc_y;
    select_single(&s, 0);
    s.cursor_x = s.world.player_tc_x + 4;
    s.cursor_y = s.world.player_tc_y;
    for (s.world.player_tc_x + 1..s.world.player_tc_x + 5) |x| {
        s.world.set(x, s.world.player_tc_y, .grass);
    }
    move_selected(&s);
    try std.testing.expectEqual(unit.UnitState.moving, s.units[0].state);
}

test "move_selected with no selection does nothing" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    select_clear(&s);
    move_selected(&s);
}

test "move_selected ignores enemy unit" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const enemy_idx = blk: {
        for (0..s.unit_count) |i| {
            if (s.units[i].owner == .enemy) break :blk i;
        }
        break :blk @as(usize, 0);
    };
    select_single(&s, enemy_idx);
    s.cursor_x = 10;
    s.cursor_y = 10;
    move_selected(&s);
    try std.testing.expectEqual(unit.UnitState.idle, s.units[enemy_idx].state);
}

test "spawn_unit returns false at capacity" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.unit_count = s.cfg.entity_limits.max_units;
    try std.testing.expect(!spawn_unit(&s, .worker, .player, s.world.player_tc_x, s.world.player_tc_y));
}

test "elapsed_seconds" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    try std.testing.expectEqual(@as(usize, 0), elapsed_seconds(&s));
    for (0..10) |_| tick(&s);
    try std.testing.expectEqual(@as(usize, 1), elapsed_seconds(&s));
    for (0..50) |_| tick(&s);
    try std.testing.expectEqual(@as(usize, 6), elapsed_seconds(&s));
}

test "select_next skips enemy units" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    const s = try State.init(allocator, 42, 80, 45, &cfg);
    defer {
        var mut_s = s;
        mut_s.deinit();
    }
    if (primary_selected(&s)) |bi| {
        try std.testing.expect(s.units[bi].owner == .player);
    }
}

test "move_cursor normal movement" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.cursor_x = 10;
    s.cursor_y = 10;
    move_cursor(&s, 5, -3);
    try std.testing.expectEqual(@as(usize, 15), s.cursor_x);
    try std.testing.expectEqual(@as(usize, 7), s.cursor_y);
}

test "select_next with only enemy units sets null" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    for (0..s.unit_count) |i| {
        s.units[i].owner = .enemy;
    }
    select_clear(&s);
    select_next(&s);
    try std.testing.expect(primary_selected(&s) == null);
}

test "player_tc returns null with no player TC" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.buildings[0].owner = .enemy;
    s.buildings[1].owner = .enemy;
    try std.testing.expect(player_tc(&s) == null);
}

test "spawn_unit with enemy owner does not set selection" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const before = primary_selected(&s).?;
    _ = spawn_unit(&s, .worker, .enemy, s.world.enemy_tc_x, s.world.enemy_tc_y);
    try std.testing.expectEqual(before, primary_selected(&s).?);
}

test "nature wander over many ticks" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    if (s.nature_count > 0) {
        const start_x = s.nature[0].x;
        const start_y = s.nature[0].y;
        for (0..200) |_| tick(&s);
        const moved = s.nature[0].x != start_x or s.nature[0].y != start_y;
        try std.testing.expect(moved);
    }
}

test "map dimensions account for labels and drawer" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    const s = try State.init(allocator, 42, 120, 50, &cfg);
    defer {
        var mut_s = s;
        mut_s.deinit();
    }
    try std.testing.expect(s.world.width > 0);
    try std.testing.expect(s.world.height > 0);
    try std.testing.expect(s.world.width < 120);
    try std.testing.expect(s.world.height < 50);
}

test "units cannot occupy same tile" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    
    for (0..s.unit_count) |i| {
        for (i + 1..s.unit_count) |j| {
            const same = s.units[i].x == s.units[j].x and s.units[i].y == s.units[j].y;
            try std.testing.expect(!same);
        }
    }
}

test "tick blocks movement into occupied tile" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    
    s.units[0].x = 10;
    s.units[0].y = 10;
    s.units[0].state = .moving;
    s.units[0].path[0] = .{ .x = 11, .y = 10 };
    s.units[0].path_len = 1;
    s.units[0].path_idx = 0;
    
    s.units[1].x = 11;
    s.units[1].y = 10;
    s.units[1].state = .idle;
    s.units[1].path_len = 0;
    
    tick(&s);
    
    try std.testing.expectEqual(@as(usize, 10), s.units[0].x);
    try std.testing.expectEqual(@as(usize, 10), s.units[0].y);
    try std.testing.expectEqual(unit.UnitState.moving, s.units[0].state);
}
