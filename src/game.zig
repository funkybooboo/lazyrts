const std = @import("std");
const map = @import("map.zig");
const unit = @import("unit.zig");
const building = @import("building.zig");
const nature = @import("nature.zig");
const pathfinding = @import("pathfinding.zig");
const config = @import("config.zig");
const time = @import("time.zig");

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
    selected_unit: ?usize = null,
    coord_mode: bool = false,
    coord_buf: [5]u8 = @splat(0),
    coord_len: usize = 0,
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
                .hp = building.max_hp(.town_center, cfg),
            };
        }
        s.building_count = starting_buildings.len;

        // Place starting workers one at a time so find_spawn sees already-placed units
        const starting_order = [_]struct { cx: usize, cy: usize, owner: unit.Owner }{
            .{ .cx = s.world.player_tc_x, .cy = s.world.player_tc_y, .owner = .player },
            .{ .cx = s.world.player_tc_x, .cy = s.world.player_tc_y, .owner = .player },
            .{ .cx = s.world.enemy_tc_x, .cy = s.world.enemy_tc_y, .owner = .enemy },
            .{ .cx = s.world.enemy_tc_x, .cy = s.world.enemy_tc_y, .owner = .enemy },
        };
        for (starting_order, 0..) |def, i| {
            const sp = find_spawn(&s, def.cx, def.cy) orelse continue;
            s.units[i] = .{
                .x = sp.x,
                .y = sp.y,
                .kind = .worker,
                .owner = def.owner,
                .hp = unit.max_hp(.worker, cfg),
            };
            s.unit_count = i + 1;
        }

        for (0..s.unit_count) |i| {
            s.units[i].path = allocator.alloc(unit.Pos, cfg.entity_limits.max_path) catch {
                for (0..i) |j| allocator.free(s.units[j].path);
                s.allocator.free(s.units);
                s.allocator.free(s.buildings);
                s.allocator.free(s.nature);
                s.world.deinit(s.allocator);
                return error.OutOfMemory;
            };
        }
        s.selected_unit = 0;

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
    
    // Collect blocked positions for pathfinding
    var blocked_positions: [256]unit.Pos = undefined;
    var blocked_count: usize = 0;
    
    // Add buildings to blocked list
    for (0..s.building_count) |i| {
        if (blocked_count < blocked_positions.len) {
            blocked_positions[blocked_count] = .{ .x = s.buildings[i].x, .y = s.buildings[i].y };
            blocked_count += 1;
        }
    }
    
    // Add nature to blocked list
    for (0..s.nature_count) |i| {
        if (blocked_count < blocked_positions.len) {
            blocked_positions[blocked_count] = .{ .x = s.nature[i].x, .y = s.nature[i].y };
            blocked_count += 1;
        }
    }
    
    for (0..s.unit_count) |i| {
        const u = &s.units[i];
        if (u.state == .moving) {
            if (u.path_idx < u.path_len) {
                const next = u.path[u.path_idx];
                // Check if blocked by any entity
                var blocked = false;
                if (unit_at(s, next.x, next.y)) |other| {
                    if (other != i) blocked = true;
                }
                if (building_at(s, next.x, next.y) != null) blocked = true;
                if (nature_at(s, next.x, next.y) != null) blocked = true;
                
                if (blocked) {
                    // Recalculate path around obstacle
                    if (u.dest) |dest| {
                        const current = u.pos();
                        
                        // Add other units to blocked list (except self)
                        var dynamic_blocked: [256]unit.Pos = undefined;
                        var dynamic_count: usize = 0;
                        
                        // Copy static blocked positions
                        for (0..blocked_count) |j| {
                            if (dynamic_count < dynamic_blocked.len) {
                                dynamic_blocked[dynamic_count] = blocked_positions[j];
                                dynamic_count += 1;
                            }
                        }
                        
                        // Add other units
                        for (0..s.unit_count) |j| {
                            if (j != i and dynamic_count < dynamic_blocked.len) {
                                if (dynamic_count < dynamic_blocked.len) {
                                    dynamic_blocked[dynamic_count] = .{ .x = s.units[j].x, .y = s.units[j].y };
                                    dynamic_count += 1;
                                }
                            }
                        }
                        
                        const blocked_slice = if (dynamic_count > 0) dynamic_blocked[0..dynamic_count] else null;
                        
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
        }
        u.step();
    }
    for (0..s.nature_count) |i| {
        nature.wander(&s.nature[i], s.world, s, s.tick_count, i, s.cfg);
    }
}

fn spawn_deer(s: *State) void {
    const total = s.world.deer_count(s.cfg);
    const near_each = @max(s.cfg.deer.min_near_tc, total * s.cfg.deer.near_tc_percent / 100);
    const scattered = total -| near_each * 2;

    var rng = std.Random.DefaultPrng.init(s.tick_count + s.cfg.deer.spawn_seed_offset);

    const tc_positions = [_]struct { x: usize, y: usize }{
        .{ .x = s.world.player_tc_x, .y = s.world.player_tc_y },
        .{ .x = s.world.enemy_tc_x, .y = s.world.enemy_tc_y },
    };

    for (tc_positions) |tc| {
        var j: usize = 0;
        while (j < near_each) : (j += 1) {
            const offset_x = rng.random().intRangeAtMost(usize, 0, s.cfg.deer.spawn_spread);
            const offset_y = rng.random().intRangeAtMost(usize, 0, s.cfg.deer.spawn_spread);
            const end_x: isize = @as(isize, @intCast(tc.x)) + @as(isize, @intCast(offset_x)) - @as(isize, @intCast(s.cfg.deer.spawn_offset));
            const end_y: isize = @as(isize, @intCast(tc.y)) + @as(isize, @intCast(offset_y)) - @as(isize, @intCast(s.cfg.deer.spawn_offset));
            if (end_x >= 0 and end_y >= 0) {
                const unit_x: usize = @intCast(end_x);
                const unit_y: usize = @intCast(end_y);
                if (unit_x < s.world.width and unit_y < s.world.height and s.world.is_walkable(unit_x, unit_y) and !occupied(s, unit_x, unit_y)) {
                    _ = spawn_nature(s, .deer, unit_x, unit_y);
                }
            }
        }
    }

    var i: usize = 0;
    while (i < scattered) {
        defer i += 1;
        const x = rng.random().intRangeAtMost(usize, 0, s.world.width -| 1);
        const y = rng.random().intRangeAtMost(usize, 0, s.world.height -| 1);
        if (s.world.is_walkable(x, y) and !occupied(s, x, y) and !s.world.near_tc(x, y, s.cfg.deer.scatter_min_dist)) {
            _ = spawn_nature(s, .deer, x, y);
        }
    }
}

pub fn spawn_nature(s: *State, kind: nature.NatureKind, x: usize, y: usize) bool {
    if (s.nature_count >= s.cfg.entity_limits.max_nature) return false;
    s.nature[s.nature_count] = .{
        .x = x,
        .y = y,
        .kind = kind,
        .hp = nature.max_hp(kind, s.cfg),
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
        s.selected_unit = s.unit_count;
    }
    s.unit_count += 1;
    return true;
}

pub fn spawn_worker(s: *State) bool {
    const tc = player_tc(s) orelse return false;
    return spawn_unit(s, .worker, .player, tc.x, tc.y);
}

pub fn move_selected(s: *State) void {
    const si = s.selected_unit orelse return;
    const u = &s.units[si];
    if (u.owner != .player) return;

    const start = u.pos();
    const goal = unit.Pos{ .x = s.cursor_x, .y = s.cursor_y };

    // Collect blocked positions for pathfinding
    var blocked_positions: [256]unit.Pos = undefined;
    var blocked_count: usize = 0;

    // Add buildings to blocked list
    for (0..s.building_count) |i| {
        if (blocked_count < blocked_positions.len) {
            blocked_positions[blocked_count] = .{ .x = s.buildings[i].x, .y = s.buildings[i].y };
            blocked_count += 1;
        }
    }

    // Add nature to blocked list
    for (0..s.nature_count) |i| {
        if (blocked_count < blocked_positions.len) {
            blocked_positions[blocked_count] = .{ .x = s.nature[i].x, .y = s.nature[i].y };
            blocked_count += 1;
        }
    }

    // Add other units to blocked list (excluding self)
    for (0..s.unit_count) |i| {
        if (i != si and blocked_count < blocked_positions.len) {
            blocked_positions[blocked_count] = .{ .x = s.units[i].x, .y = s.units[i].y };
            blocked_count += 1;
        }
    }

    const blocked_slice = if (blocked_count > 0) blocked_positions[0..blocked_count] else null;

    const len = pathfinding.find_path(s.allocator, &s.world, start, goal, u.path, blocked_slice) orelse return;
    if (len == 0) return;
    u.path_len = len;
    u.path_idx = 0;
    u.state = .moving;
    u.dest = goal;
}

pub fn select_next(s: *State) void {
    if (s.unit_count == 0) {
        s.selected_unit = null;
        return;
    }
    const start: usize = if (s.selected_unit) |sel|
        (sel + 1) % s.unit_count
    else
        0;
    var i: usize = start;
    while (true) {
        if (s.units[i].owner == .player) {
            s.selected_unit = i;
            return;
        }
        i = (i + 1) % s.unit_count;
        if (i == start) break;
    }
    s.selected_unit = null;
}

pub fn unit_at(s: *const State, x: usize, y: usize) ?usize {
    for (0..s.unit_count) |i| {
        if (s.units[i].x == x and s.units[i].y == y) return i;
    }
    return null;
}

pub fn building_at(s: *const State, x: usize, y: usize) ?usize {
    for (0..s.building_count) |i| {
        if (s.buildings[i].x == x and s.buildings[i].y == y) return i;
    }
    return null;
}

pub fn nature_at(s: *const State, x: usize, y: usize) ?usize {
    for (0..s.nature_count) |i| {
        if (s.nature[i].x == x and s.nature[i].y == y) return i;
    }
    return null;
}

pub fn nature_at_except(s: *const State, x: usize, y: usize, except_idx: usize) ?usize {
    for (0..s.nature_count) |i| {
        if (i == except_idx) continue;
        if (s.nature[i].x == x and s.nature[i].y == y) return i;
    }
    return null;
}

pub fn occupied(s: *const State, x: usize, y: usize) bool {
    return unit_at(s, x, y) != null or building_at(s, x, y) != null or nature_at(s, x, y) != null;
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

pub fn parse_coord(buf: []const u8, len: usize) ?struct { x: usize, y: usize } {
    if (len == 0) return null;
    var col: usize = 0;
    var i: usize = 0;
    while (i < len and buf[i] >= 'A' and buf[i] <= 'Z') : (i += 1) {
        col = col * 26 + (@as(usize, buf[i] - 'A') + 1);
    }
    if (i == 0) return null;
    col -= 1;

    var row: usize = 0;
    while (i < len and buf[i] >= '0' and buf[i] <= '9') : (i += 1) {
        row = row * 10 + (@as(usize, buf[i] - '0'));
    }
    if (row == 0) return null;
    row -= 1;

    return .{ .x = col, .y = row };
}

pub fn col_to_letters(col: usize, buf: *[3]u8) []const u8 {
    var n = col + 1;
    var i: usize = 0;
    while (n > 0 and i < 3) {
        n -= 1;
        buf[i] = 'A' + @as(u8, @intCast(n % 26));
        n /= 26;
        i += 1;
    }
    std.mem.reverse(u8, buf[0..i]);
    return buf[0..i];
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
    try std.testing.expectEqual(@as(usize, 2), s.building_count);
    try std.testing.expectEqual(building.BuildingKind.town_center, s.buildings[0].kind);
    try std.testing.expectEqual(unit.Owner.player, s.buildings[0].owner);
    try std.testing.expectEqual(building.BuildingKind.town_center, s.buildings[1].kind);
    try std.testing.expectEqual(unit.Owner.enemy, s.buildings[1].owner);
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
    const first = s.selected_unit.?;
    select_next(&s);
    const second = s.selected_unit.?;
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

test "parse_coord basic" {
    const r = parse_coord("A5", 2).?;
    try std.testing.expectEqual(@as(usize, 0), r.x);
    try std.testing.expectEqual(@as(usize, 4), r.y);
}

test "parse_coord Z26" {
    const r = parse_coord("Z26", 3).?;
    try std.testing.expectEqual(@as(usize, 25), r.x);
    try std.testing.expectEqual(@as(usize, 25), r.y);
}

test "parse_coord AA1" {
    const r = parse_coord("AA1", 3).?;
    try std.testing.expectEqual(@as(usize, 26), r.x);
    try std.testing.expectEqual(@as(usize, 0), r.y);
}

test "parse_coord invalid" {
    try std.testing.expect(parse_coord("5", 1) == null);
    try std.testing.expect(parse_coord("", 0) == null);
    try std.testing.expect(parse_coord("A", 1) == null);
}

test "col_to_letters roundtrip" {
    var buf: [3]u8 = undefined;
    try std.testing.expectEqualStrings("A", col_to_letters(0, &buf));
    try std.testing.expectEqualStrings("Z", col_to_letters(25, &buf));
    try std.testing.expectEqualStrings("AA", col_to_letters(26, &buf));
    try std.testing.expectEqualStrings("AB", col_to_letters(27, &buf));
    try std.testing.expectEqualStrings("AZ", col_to_letters(51, &buf));
    try std.testing.expectEqualStrings("BA", col_to_letters(52, &buf));
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
    s.selected_unit = 0;
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
    s.selected_unit = null;
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
    s.selected_unit = enemy_idx;
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
    if (s.selected_unit) |bi| {
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
    s.selected_unit = null;
    select_next(&s);
    try std.testing.expect(s.selected_unit == null);
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
    const before = s.selected_unit.?;
    _ = spawn_unit(&s, .worker, .enemy, s.world.enemy_tc_x, s.world.enemy_tc_y);
    try std.testing.expectEqual(before, s.selected_unit.?);
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

test "parse_coord B3" {
    const r = parse_coord("B3", 2).?;
    try std.testing.expectEqual(@as(usize, 1), r.x);
    try std.testing.expectEqual(@as(usize, 2), r.y);
}

test "parse_coord multi-letter" {
    const r = parse_coord("AB5", 3).?;
    try std.testing.expectEqual(@as(usize, 27), r.x);
    try std.testing.expectEqual(@as(usize, 4), r.y);
}

test "parse_coord no digits returns null" {
    try std.testing.expect(parse_coord("A", 1) == null);
}

test "col_to_letters produces valid column letters" {
    var buf: [3]u8 = undefined;
    try std.testing.expectEqualStrings("A", col_to_letters(0, &buf));
    try std.testing.expectEqualStrings("Z", col_to_letters(25, &buf));
    try std.testing.expectEqualStrings("AA", col_to_letters(26, &buf));
    for (0..30) |col| {
        const letters = col_to_letters(col, &buf);
        try std.testing.expect(letters.len > 0);
        for (letters) |ch| {
            try std.testing.expect(ch >= 'A' and ch <= 'Z');
        }
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
    
    // Check all units have unique positions
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
    
    // Place unit 0 at (10,10), unit 1 at (11,10)
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
    
    // Unit 0 should not have moved
    try std.testing.expectEqual(@as(usize, 10), s.units[0].x);
    try std.testing.expectEqual(@as(usize, 10), s.units[0].y);
    try std.testing.expectEqual(unit.UnitState.moving, s.units[0].state);
}
