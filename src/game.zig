const map = @import("map.zig");
const entity = @import("entity.zig");
const pathfinding = @import("pathfinding.zig");

pub const State = struct {
    cursor_x: usize = map.PLAYER_TC_X,
    cursor_y: usize = map.PLAYER_TC_Y,
    quit: bool = false,
    world: map.GameMap,
    units: [entity.MAX_UNITS]entity.Unit = undefined,
    unit_count: usize = 0,
    buildings: [entity.MAX_BUILDINGS]entity.Building = undefined,
    building_count: usize = 0,
    selected_unit: ?usize = null,

    pub fn init(seed: u64) State {
        var s: State = .{ .world = map.GameMap.init(seed) };

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
            .x = map.PLAYER_TC_X,
            .y = map.PLAYER_TC_Y,
            .kind = .town_center,
            .owner = .player,
            .hp = entity.BuildingKind.town_center.max_hp(),
        };
        s.buildings[1] = .{
            .x = map.ENEMY_TC_X,
            .y = map.ENEMY_TC_Y,
            .kind = .town_center,
            .owner = .enemy,
            .hp = entity.BuildingKind.town_center.max_hp(),
        };
        s.building_count = 2;

        return s;
    }
};

pub fn move_cursor(s: *State, dx: isize, dy: isize) void {
    const nx = @max(0, @min(@as(isize, @intCast(s.cursor_x)) + dx, @as(isize, @intCast(map.WIDTH - 1))));
    const ny = @max(0, @min(@as(isize, @intCast(s.cursor_y)) + dy, @as(isize, @intCast(map.HEIGHT - 1))));
    s.cursor_x = @intCast(nx);
    s.cursor_y = @intCast(ny);
}

pub fn tick(s: *State) void {
    for (0..s.unit_count) |i| {
        s.units[i].step();
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

fn find_spawn(world: *const map.GameMap, cx: usize, cy: usize) entity.Pos {
    const offsets = [_]struct { dx: isize, dy: isize }{
        .{ .dx = 1, .dy = 0 },
        .{ .dx = -1, .dy = 0 },
        .{ .dx = 0, .dy = 1 },
        .{ .dx = 0, .dy = -1 },
        .{ .dx = 1, .dy = 1 },
        .{ .dx = -1, .dy = -1 },
        .{ .dx = 1, .dy = -1 },
        .{ .dx = -1, .dy = 1 },
    };
    for (offsets) |o| {
        const nx: isize = @as(isize, @intCast(cx)) + o.dx;
        const ny: isize = @as(isize, @intCast(cy)) + o.dy;
        if (nx < 0 or ny < 0) continue;
        const ux: usize = @intCast(nx);
        const uy: usize = @intCast(ny);
        if (ux >= map.WIDTH or uy >= map.HEIGHT) continue;
        if (world.is_walkable(ux, uy)) return .{ .x = ux, .y = uy };
    }
    return .{ .x = cx, .y = cy };
}

const std = @import("std");

test "move_cursor clamps to bounds" {
    var s = State.init(1);
    s.cursor_x = 0;
    s.cursor_y = 0;
    move_cursor(&s, -1, 0);
    try std.testing.expectEqual(@as(usize, 0), s.cursor_x);

    s.cursor_x = map.WIDTH - 1;
    move_cursor(&s, 1, 0);
    try std.testing.expectEqual(map.WIDTH - 1, s.cursor_x);

    s.cursor_y = 0;
    move_cursor(&s, 0, -1);
    try std.testing.expectEqual(@as(usize, 0), s.cursor_y);

    s.cursor_y = map.HEIGHT - 1;
    move_cursor(&s, 0, 1);
    try std.testing.expectEqual(map.HEIGHT - 1, s.cursor_y);
}

test "move_cursor moves normally" {
    var s = State.init(1);
    s.cursor_x = 10;
    s.cursor_y = 10;
    move_cursor(&s, 5, -3);
    try std.testing.expectEqual(@as(usize, 15), s.cursor_x);
    try std.testing.expectEqual(@as(usize, 7), s.cursor_y);
}

test "init sets cursor at TC" {
    const s = State.init(42);
    try std.testing.expectEqual(map.PLAYER_TC_X, s.cursor_x);
    try std.testing.expectEqual(map.PLAYER_TC_Y, s.cursor_y);
}

test "init registers both TCs as buildings" {
    const s = State.init(42);
    try std.testing.expectEqual(@as(usize, 2), s.building_count);
    try std.testing.expectEqual(entity.BuildingKind.town_center, s.buildings[0].kind);
    try std.testing.expectEqual(entity.Owner.player, s.buildings[0].owner);
    try std.testing.expectEqual(map.PLAYER_TC_X, s.buildings[0].x);
    try std.testing.expectEqual(entity.BuildingKind.town_center, s.buildings[1].kind);
    try std.testing.expectEqual(entity.Owner.enemy, s.buildings[1].owner);
    try std.testing.expectEqual(map.ENEMY_TC_X, s.buildings[1].x);
}

test "init TCs have full HP" {
    const s = State.init(42);
    try std.testing.expectEqual(entity.BuildingKind.town_center.max_hp(), s.buildings[0].hp);
    try std.testing.expectEqual(entity.BuildingKind.town_center.max_hp(), s.buildings[1].hp);
}

test "spawn_worker adds unit and selects it" {
    var s = State.init(42);
    try std.testing.expect(spawn_worker(&s));
    try std.testing.expectEqual(@as(usize, 1), s.unit_count);
    try std.testing.expectEqual(@as(usize, 0), s.selected_unit.?);
    try std.testing.expectEqual(entity.UnitKind.worker, s.units[0].kind);
    try std.testing.expectEqual(entity.Owner.player, s.units[0].owner);
}

test "spawn_unit sets HP from kind" {
    var s = State.init(42);
    try std.testing.expect(spawn_worker(&s));
    try std.testing.expectEqual(entity.UnitKind.worker.max_hp(), s.units[0].hp);
}

test "tick moves unit along path" {
    var s = State.init(42);
    try std.testing.expect(spawn_worker(&s));
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
    try std.testing.expectEqual(@as(usize, 0), s.units[0].path_len);
}

test "select_next cycles through player units" {
    var s = State.init(42);
    s.units[0] = .{ .x = 3, .y = 3, .kind = .worker, .owner = .player, .hp = 50 };
    s.units[1] = .{ .x = 4, .y = 4, .kind = .worker, .owner = .player, .hp = 50 };
    s.unit_count = 2;

    select_next(&s);
    try std.testing.expectEqual(@as(usize, 0), s.selected_unit.?);
    select_next(&s);
    try std.testing.expectEqual(@as(usize, 1), s.selected_unit.?);
    select_next(&s);
    try std.testing.expectEqual(@as(usize, 0), s.selected_unit.?);
}

test "unit_at finds unit at position" {
    var s = State.init(42);
    s.units[0] = .{ .x = 5, .y = 5, .kind = .worker, .owner = .player, .hp = 50 };
    s.unit_count = 1;
    try std.testing.expectEqual(@as(usize, 0), unit_at(&s, 5, 5).?);
    try std.testing.expect(unit_at(&s, 6, 6) == null);
}

test "Unit.pos returns current position" {
    const u = entity.Unit{ .x = 7, .y = 12, .kind = .worker, .owner = .player, .hp = 50 };
    const p = u.pos();
    try std.testing.expectEqual(@as(usize, 7), p.x);
    try std.testing.expectEqual(@as(usize, 12), p.y);
}

test "spawn_worker lands on walkable tile" {
    var s = State.init(42);
    try std.testing.expect(spawn_worker(&s));
    try std.testing.expect(s.world.is_walkable(s.units[0].x, s.units[0].y));
}

test "spawn_unit returns false at capacity" {
    var s = State.init(42);
    s.unit_count = entity.MAX_UNITS;
    try std.testing.expect(!spawn_unit(&s, .worker, .player, map.PLAYER_TC_X, map.PLAYER_TC_Y));
}

test "tick does not move idle unit" {
    var s = State.init(42);
    try std.testing.expect(spawn_worker(&s));
    s.units[0].x = 5;
    s.units[0].y = 5;
    s.units[0].state = .idle;
    tick(&s);
    try std.testing.expectEqual(@as(usize, 5), s.units[0].x);
    try std.testing.expectEqual(@as(usize, 5), s.units[0].y);
}

test "move_selected sets unit on path" {
    var s = State.init(42);
    try std.testing.expect(spawn_worker(&s));
    s.units[0].x = map.PLAYER_TC_X + 1;
    s.units[0].y = map.PLAYER_TC_Y;
    s.cursor_x = map.PLAYER_TC_X + 4;
    s.cursor_y = map.PLAYER_TC_Y;
    move_selected(&s);
    try std.testing.expectEqual(entity.UnitState.moving, s.units[0].state);
    try std.testing.expect(s.units[0].path_len > 0);
}

test "move_selected with no selection does nothing" {
    var s = State.init(42);
    try std.testing.expect(spawn_worker(&s));
    s.selected_unit = null;
    s.units[0].state = .idle;
    move_selected(&s);
    try std.testing.expectEqual(entity.UnitState.idle, s.units[0].state);
}

test "move_selected ignores enemy unit" {
    var s = State.init(42);
    s.units[0] = .{ .x = 5, .y = 5, .kind = .worker, .owner = .enemy, .hp = 50 };
    s.unit_count = 1;
    s.selected_unit = 0;
    s.cursor_x = 10;
    s.cursor_y = 5;
    move_selected(&s);
    try std.testing.expectEqual(entity.UnitState.idle, s.units[0].state);
}

test "move_selected to unreachable tile does nothing" {
    var s = State.init(42);
    try std.testing.expect(spawn_worker(&s));
    s.units[0].x = 5;
    s.units[0].y = 5;
    s.cursor_x = 0;
    s.cursor_y = 0;
    s.world.tiles[0][0] = .water;
    move_selected(&s);
    try std.testing.expectEqual(entity.UnitState.idle, s.units[0].state);
    try std.testing.expectEqual(@as(usize, 0), s.units[0].path_len);
}

test "select_next skips enemy units" {
    var s = State.init(42);
    s.units[0] = .{ .x = 3, .y = 3, .kind = .worker, .owner = .enemy, .hp = 50 };
    s.units[1] = .{ .x = 4, .y = 4, .kind = .worker, .owner = .player, .hp = 50 };
    s.unit_count = 2;
    select_next(&s);
    try std.testing.expectEqual(@as(usize, 1), s.selected_unit.?);
}

test "select_next with no player units sets null" {
    var s = State.init(42);
    s.units[0] = .{ .x = 3, .y = 3, .kind = .worker, .owner = .enemy, .hp = 50 };
    s.unit_count = 1;
    select_next(&s);
    try std.testing.expect(s.selected_unit == null);
}

test "select_next with empty unit list" {
    var s = State.init(42);
    s.unit_count = 0;
    select_next(&s);
    try std.testing.expect(s.selected_unit == null);
}

test "player_tc returns player town center position" {
    const s = State.init(42);
    const tc = player_tc(&s).?;
    try std.testing.expectEqual(map.PLAYER_TC_X, tc.x);
    try std.testing.expectEqual(map.PLAYER_TC_Y, tc.y);
}

test "building_at finds building at position" {
    var s = State.init(42);
    try std.testing.expectEqual(@as(usize, 0), building_at(&s, map.PLAYER_TC_X, map.PLAYER_TC_Y).?);
    try std.testing.expectEqual(@as(usize, 1), building_at(&s, map.ENEMY_TC_X, map.ENEMY_TC_Y).?);
    try std.testing.expect(building_at(&s, 0, 0) == null);
}

test "spawn_unit with enemy owner does not set selection" {
    var s = State.init(42);
    try std.testing.expect(spawn_unit(&s, .worker, .enemy, map.ENEMY_TC_X, map.ENEMY_TC_Y));
    try std.testing.expect(s.selected_unit == null);
    try std.testing.expectEqual(entity.Owner.enemy, s.units[0].owner);
}

test "UnitKind.max_hp returns different values" {
    try std.testing.expect(entity.UnitKind.soldier.max_hp() > entity.UnitKind.worker.max_hp());
}

test "BuildingKind.max_hp returns different values" {
    try std.testing.expect(entity.BuildingKind.town_center.max_hp() > entity.BuildingKind.farm.max_hp());
}
