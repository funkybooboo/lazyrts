const std = @import("std");
const map = @import("map.zig");
const entity = @import("entity.zig");
const pathfinding = @import("pathfinding.zig");

pub const DRAWER_HEIGHT: u16 = 5;
pub const LABEL_WIDTH: u16 = 3;

pub fn headerHeight(map_w: usize) u16 {
    var buf: [3]u8 = undefined;
    const letters = col_to_letters(map_w -| 1, &buf);
    return @intCast(letters.len);
}

pub const State = struct {
    cursor_x: usize = 0,
    cursor_y: usize = 0,
    quit: bool = false,
    world: map.GameMap,
    units: [entity.MAX_UNITS]entity.Unit = undefined,
    unit_count: usize = 0,
    buildings: [entity.MAX_BUILDINGS]entity.Building = undefined,
    building_count: usize = 0,
    selected_unit: ?usize = null,
    coord_mode: bool = false,
    coord_buf: [5]u8 = @splat(0),
    coord_len: usize = 0,
    tick_count: usize = 0,

    pub fn init(seed: u64, term_w: u16, term_h: u16) State {
        const tw: usize = if (term_w < 20) 80 else term_w;
        const th: usize = if (term_h < 15) 40 else term_h;

        const map_w: u16 = if (tw > LABEL_WIDTH) @intCast(tw - LABEL_WIDTH) else 10;
        const hh: u16 = headerHeight(map_w);
        const map_area_h = th -| DRAWER_HEIGHT -| hh;
        const map_h: u16 = if (map_area_h > 0) @intCast(map_area_h) else 10;

        var s: State = .{
            .world = map.GameMap.init(seed, map_w, map_h),
        };

        for (&s.units) |*u| u.* = .{
            .x = 0,
            .y = 0,
            .kind = .worker,
            .owner = .player,
            .hp = 0,
            .state = .idle,
            .path_len = 0,
            .path_idx = 0,
        };

        s.buildings[0] = .{
            .x = s.world.player_tc_x,
            .y = s.world.player_tc_y,
            .kind = .town_center,
            .owner = .player,
            .hp = entity.BuildingKind.town_center.max_hp(),
        };
        s.buildings[1] = .{
            .x = s.world.enemy_tc_x,
            .y = s.world.enemy_tc_y,
            .kind = .town_center,
            .owner = .enemy,
            .hp = entity.BuildingKind.town_center.max_hp(),
        };
        s.building_count = 2;

        const p_spawn = find_spawn(&s.world, s.world.player_tc_x, s.world.player_tc_y);
        const e_spawn = find_spawn(&s.world, s.world.enemy_tc_x, s.world.enemy_tc_y);

        s.units[0] = .{ .x = p_spawn.x, .y = p_spawn.y, .kind = .worker, .owner = .player, .hp = entity.UnitKind.worker.max_hp() };
        s.units[1] = .{ .x = p_spawn.x, .y = p_spawn.y, .kind = .worker, .owner = .player, .hp = entity.UnitKind.worker.max_hp() };
        s.units[2] = .{ .x = e_spawn.x, .y = e_spawn.y, .kind = .worker, .owner = .enemy, .hp = entity.UnitKind.worker.max_hp() };
        s.units[3] = .{ .x = e_spawn.x, .y = e_spawn.y, .kind = .worker, .owner = .enemy, .hp = entity.UnitKind.worker.max_hp() };
        s.unit_count = 4;
        s.selected_unit = 0;

        spawn_deer(&s);

        s.cursor_x = s.world.player_tc_x;
        s.cursor_y = s.world.player_tc_y;

        return s;
    }
};

pub fn move_cursor(s: *State, dx: isize, dy: isize) void {
    const max_x: isize = @intCast(s.world.width -| 1);
    const max_y: isize = @intCast(s.world.height -| 1);
    const nx = @max(0, @min(@as(isize, @intCast(s.cursor_x)) + dx, max_x));
    const ny = @max(0, @min(@as(isize, @intCast(s.cursor_y)) + dy, max_y));
    s.cursor_x = @intCast(nx);
    s.cursor_y = @intCast(ny);
}

pub fn tick(s: *State) void {
    s.tick_count += 1;
    var rng = std.Random.DefaultPrng.init(s.tick_count);
    for (0..s.unit_count) |i| {
        const u = &s.units[i];
        if (u.owner == .neutral and u.state == .idle) {
            if (s.tick_count % 15 == 0 and rng.random().intRangeAtMost(usize, 0, 2) == 0) {
                wander_deer(s, i);
            }
        }
        u.step();
    }
}

fn wander_deer(s: *State, idx: usize) void {
    var rng = std.Random.DefaultPrng.init(s.tick_count * 31 + idx * 17 + @as(u64, @intCast(s.units[idx].x)));
    const dirs = [_]struct { dx: isize, dy: isize }{
        .{ .dx = 0, .dy = -1 }, .{ .dx = 0, .dy = 1 },
        .{ .dx = -1, .dy = 0 }, .{ .dx = 1, .dy = 0 },
    };
    const d = rng.random().intRangeAtMost(usize, 0, 3);
    const nx = @as(isize, @intCast(s.units[idx].x)) + dirs[d].dx;
    const ny = @as(isize, @intCast(s.units[idx].y)) + dirs[d].dy;
    if (nx >= 0 and ny >= 0) {
        const ux: usize = @intCast(nx);
        const uy: usize = @intCast(ny);
        if (ux < s.world.width and uy < s.world.height and s.world.is_walkable(ux, uy)) {
            if (unit_at(s, ux, uy) == null) {
                s.units[idx].x = ux;
                s.units[idx].y = uy;
            }
        }
    }
}

fn spawn_deer(s: *State) void {
    const total = s.world.deer_count();
    const near_each = total * 15 / 100;
    const scattered = total - near_each * 2;

    var rng = std.Random.DefaultPrng.init(s.tick_count + 999);

    var i: usize = 0;
    while (i < near_each) {
        defer i += 1;
        const ox = rng.random().intRangeAtMost(usize, 0, 12);
        const oy = rng.random().intRangeAtMost(usize, 0, 12);
        const ex: isize = @as(isize, @intCast(s.world.player_tc_x)) + @as(isize, @intCast(ox)) - 6;
        const ey: isize = @as(isize, @intCast(s.world.player_tc_y)) + @as(isize, @intCast(oy)) - 6;
        if (ex >= 0 and ey >= 0) {
            const ux: usize = @intCast(ex);
            const uy: usize = @intCast(ey);
            if (ux < s.world.width and uy < s.world.height and s.world.is_walkable(ux, uy) and unit_at(s, ux, uy) == null) {
                _ = spawn_unit(s, .deer, .neutral, ux, uy);
            }
        }
    }

    i = 0;
    while (i < near_each) {
        defer i += 1;
        const ox = rng.random().intRangeAtMost(usize, 0, 12);
        const oy = rng.random().intRangeAtMost(usize, 0, 12);
        const ex: isize = @as(isize, @intCast(s.world.enemy_tc_x)) + @as(isize, @intCast(ox)) - 6;
        const ey: isize = @as(isize, @intCast(s.world.enemy_tc_y)) + @as(isize, @intCast(oy)) - 6;
        if (ex >= 0 and ey >= 0) {
            const ux: usize = @intCast(ex);
            const uy: usize = @intCast(ey);
            if (ux < s.world.width and uy < s.world.height and s.world.is_walkable(ux, uy) and unit_at(s, ux, uy) == null) {
                _ = spawn_unit(s, .deer, .neutral, ux, uy);
            }
        }
    }

    i = 0;
    while (i < scattered) {
        defer i += 1;
        const x = rng.random().intRangeAtMost(usize, 0, s.world.width -| 1);
        const y = rng.random().intRangeAtMost(usize, 0, s.world.height -| 1);
        if (s.world.is_walkable(x, y) and unit_at(s, x, y) == null and !s.world.near_tc(x, y, 2)) {
            _ = spawn_unit(s, .deer, .neutral, x, y);
        }
    }
}

pub fn spawn_unit(s: *State, kind: entity.UnitKind, owner: entity.Owner, cx: usize, cy: usize) bool {
    if (s.unit_count >= entity.MAX_UNITS) return false;

    const spawn = find_spawn(&s.world, cx, cy);

    s.units[s.unit_count] = .{
        .x = spawn.x,
        .y = spawn.y,
        .kind = kind,
        .owner = owner,
        .hp = kind.max_hp(),
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
    const goal = entity.Pos{ .x = s.cursor_x, .y = s.cursor_y };

    const len = pathfinding.find_path(&s.world, start, goal, u.path[0..]) orelse return;
    if (len == 0) return;
    u.path_len = len;
    u.path_idx = 0;
    u.state = .moving;
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

pub fn player_tc(s: *const State) ?entity.Pos {
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
                .town_center => 5,
                .house => 5,
                else => 0,
            };
        }
    }
    return cap;
}

pub fn player_unit_counts(s: *const State) struct { workers: usize, soldiers: usize } {
    var w: usize = 0;
    var sol: usize = 0;
    for (0..s.unit_count) |i| {
        if (s.units[i].owner == .player) {
            switch (s.units[i].kind) {
                .worker => w += 1,
                .soldier => sol += 1,
                else => {},
            }
        }
    }
    return .{ .workers = w, .soldiers = sol };
}

pub fn elapsed_seconds(s: *const State) usize {
    return s.tick_count / 10;
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

fn find_spawn(world: *const map.GameMap, cx: usize, cy: usize) entity.Pos {
    const offsets = [_]struct { dx: isize, dy: isize }{
        .{ .dx = 1, .dy = 0 },  .{ .dx = -1, .dy = 0 },
        .{ .dx = 0, .dy = 1 },  .{ .dx = 0, .dy = -1 },
        .{ .dx = 1, .dy = 1 },  .{ .dx = -1, .dy = -1 },
        .{ .dx = 1, .dy = -1 }, .{ .dx = -1, .dy = 1 },
    };
    for (offsets) |o| {
        const nx: isize = @as(isize, @intCast(cx)) + o.dx;
        const ny: isize = @as(isize, @intCast(cy)) + o.dy;
        if (nx < 0 or ny < 0) continue;
        const ux: usize = @intCast(nx);
        const uy: usize = @intCast(ny);
        if (ux >= world.width or uy >= world.height) continue;
        if (world.is_walkable(ux, uy)) return .{ .x = ux, .y = uy };
    }
    return .{ .x = cx, .y = cy };
}

test "move_cursor clamps to bounds" {
    var s = State.init(1, 80, 45);
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
    const s = State.init(42, 80, 45);
    try std.testing.expectEqual(@as(usize, 2), s.building_count);
    try std.testing.expectEqual(entity.BuildingKind.town_center, s.buildings[0].kind);
    try std.testing.expectEqual(entity.Owner.player, s.buildings[0].owner);
    try std.testing.expectEqual(entity.BuildingKind.town_center, s.buildings[1].kind);
    try std.testing.expectEqual(entity.Owner.enemy, s.buildings[1].owner);
}

test "init spawns starting workers" {
    const s = State.init(42, 80, 45);
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
    const s = State.init(42, 80, 45);
    var deer: usize = 0;
    for (0..s.unit_count) |i| {
        if (s.units[i].owner == .neutral) deer += 1;
    }
    try std.testing.expect(deer > 0);
}

test "init buildings start complete" {
    const s = State.init(42, 80, 45);
    for (0..s.building_count) |i| {
        try std.testing.expect(s.buildings[i].is_complete());
    }
}

test "spawn_worker adds unit and selects it" {
    var s = State.init(42, 80, 45);
    const before = s.unit_count;
    try std.testing.expect(spawn_worker(&s));
    try std.testing.expectEqual(before + 1, s.unit_count);
    try std.testing.expectEqual(entity.UnitKind.worker, s.units[s.unit_count - 1].kind);
    try std.testing.expectEqual(entity.Owner.player, s.units[s.unit_count - 1].owner);
}

test "tick moves unit along path" {
    var s = State.init(42, 80, 45);
    s.units[0].x = 5;
    s.units[0].y = 5;
    s.units[0].path[0] = .{ .x = 6, .y = 5 };
    s.units[0].path[1] = .{ .x = 7, .y = 5 };
    s.units[0].path_len = 2;
    s.units[0].path_idx = 0;
    s.units[0].state = .moving;

    tick(&s);
    try std.testing.expectEqual(@as(usize, 6), s.units[0].x);
    try std.testing.expectEqual(entity.UnitState.moving, s.units[0].state);

    tick(&s);
    try std.testing.expectEqual(@as(usize, 7), s.units[0].x);
    try std.testing.expectEqual(entity.UnitState.idle, s.units[0].state);
}

test "select_next cycles through player units" {
    var s = State.init(42, 80, 45);
    const first = s.selected_unit.?;
    select_next(&s);
    const second = s.selected_unit.?;
    try std.testing.expect(first != second);
}

test "unit_at finds unit at position" {
    var s = State.init(42, 80, 45);
    const ux = s.units[0].x;
    const uy = s.units[0].y;
    try std.testing.expect(unit_at(&s, ux, uy) != null);
}

test "unit_at returns null for empty position" {
    var s = State.init(42, 80, 45);
    try std.testing.expect(unit_at(&s, 0, 0) == null or !s.world.is_walkable(0, 0));
}

test "player_tc returns player town center position" {
    var s = State.init(42, 80, 45);
    const tc = player_tc(&s).?;
    try std.testing.expectEqual(@as(usize, s.world.player_tc_x), tc.x);
    try std.testing.expectEqual(@as(usize, s.world.player_tc_y), tc.y);
}

test "building_at finds buildings at TC positions" {
    var s = State.init(42, 80, 45);
    try std.testing.expect(building_at(&s, s.world.player_tc_x, s.world.player_tc_y) != null);
    try std.testing.expect(building_at(&s, s.world.enemy_tc_x, s.world.enemy_tc_y) != null);
}

test "building_at returns null for empty position" {
    var s = State.init(42, 80, 45);
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
    var s = State.init(42, 80, 45);
    try std.testing.expectEqual(@as(usize, 2), player_pop(&s));
}

test "player_pop_cap counts from buildings" {
    var s = State.init(42, 80, 45);
    try std.testing.expectEqual(@as(usize, 5), player_pop_cap(&s));
}

test "player_pop_cap ignores incomplete buildings" {
    var s = State.init(42, 80, 45);
    s.buildings[0].build_progress = 50;
    try std.testing.expectEqual(@as(usize, 0), player_pop_cap(&s));
}

test "move_selected sets unit on path" {
    var s = State.init(42, 80, 45);
    s.units[0].x = s.world.player_tc_x + 1;
    s.units[0].y = s.world.player_tc_y;
    s.selected_unit = 0;
    s.cursor_x = s.world.player_tc_x + 4;
    s.cursor_y = s.world.player_tc_y;
    for (s.world.player_tc_x + 1..s.world.player_tc_x + 5) |x| {
        s.world.set(x, s.world.player_tc_y, .grass);
    }
    move_selected(&s);
    try std.testing.expectEqual(entity.UnitState.moving, s.units[0].state);
}

test "move_selected with no selection does nothing" {
    var s = State.init(42, 80, 45);
    s.selected_unit = null;
    move_selected(&s);
}

test "move_selected ignores enemy unit" {
    var s = State.init(42, 80, 45);
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
    try std.testing.expectEqual(entity.UnitState.idle, s.units[enemy_idx].state);
}

test "spawn_unit returns false at capacity" {
    var s = State.init(42, 80, 45);
    s.unit_count = entity.MAX_UNITS;
    try std.testing.expect(!spawn_unit(&s, .worker, .player, s.world.player_tc_x, s.world.player_tc_y));
}

test "elapsed_seconds" {
    var s = State.init(42, 80, 45);
    try std.testing.expectEqual(@as(usize, 0), elapsed_seconds(&s));
    for (0..10) |_| tick(&s);
    try std.testing.expectEqual(@as(usize, 1), elapsed_seconds(&s));
    for (0..50) |_| tick(&s);
    try std.testing.expectEqual(@as(usize, 6), elapsed_seconds(&s));
}

test "select_next skips neutral and enemy units" {
    const s = State.init(42, 80, 45);
    if (s.selected_unit) |bi| {
        try std.testing.expect(s.units[bi].owner == .player);
    }
}

test "move_cursor normal movement" {
    var s = State.init(42, 80, 45);
    s.cursor_x = 10;
    s.cursor_y = 10;
    move_cursor(&s, 5, -3);
    try std.testing.expectEqual(@as(usize, 15), s.cursor_x);
    try std.testing.expectEqual(@as(usize, 7), s.cursor_y);
}

test "select_next with only enemy units sets null" {
    var s = State.init(42, 80, 45);
    for (0..s.unit_count) |i| {
        s.units[i].owner = .enemy;
    }
    s.selected_unit = null;
    select_next(&s);
    try std.testing.expect(s.selected_unit == null);
}

test "player_tc returns null with no player TC" {
    var s = State.init(42, 80, 45);
    s.buildings[0].owner = .enemy;
    s.buildings[1].owner = .enemy;
    try std.testing.expect(player_tc(&s) == null);
}

test "spawn_unit with enemy owner does not set selection" {
    var s = State.init(42, 80, 45);
    const before = s.selected_unit.?;
    _ = spawn_unit(&s, .worker, .enemy, s.world.enemy_tc_x, s.world.enemy_tc_y);
    try std.testing.expectEqual(before, s.selected_unit.?);
}

test "deer wander over many ticks" {
    var s = State.init(42, 80, 45);
    var deer_idx: ?usize = null;
    for (0..s.unit_count) |i| {
        if (s.units[i].owner == .neutral) {
            deer_idx = i;
            break;
        }
    }
    if (deer_idx) |di| {
        const start_x = s.units[di].x;
        const start_y = s.units[di].y;
        for (0..200) |_| tick(&s);
        const moved = s.units[di].x != start_x or s.units[di].y != start_y;
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
    const s = State.init(42, 120, 50);
    try std.testing.expect(s.world.width > 0);
    try std.testing.expect(s.world.height > 0);
    try std.testing.expect(s.world.width < 120);
    try std.testing.expect(s.world.height < 50);
}
