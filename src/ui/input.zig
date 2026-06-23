const std = @import("std");
const terminal = @import("../lib/terminal.zig");
const state = @import("../game/state.zig");
const unit = @import("../units/unit.zig");
const queries = @import("../game/queries.zig");
const selection = @import("../game/selection.zig");
const astar = @import("../lib/pathfinding.zig");
const training = @import("../game/training.zig");
const coords = @import("../lib/coords.zig");
const lib_spatial = @import("../lib/spatial.zig");
const config = @import("../config.zig");

const State = state.State;

pub fn moveCursor(s: *State, dx: isize, dy: isize) void {
    const max_x: isize = @intCast(s.world.width -| 1);
    const max_y: isize = @intCast(s.world.height -| 1);
    const next_x = @max(0, @min(@as(isize, @intCast(s.cursor_x)) + dx, max_x));
    const next_y = @max(0, @min(@as(isize, @intCast(s.cursor_y)) + dy, max_y));
    s.cursor_x = @intCast(next_x);
    s.cursor_y = @intCast(next_y);
}

pub fn moveSelected(s: *State) void {
    if (s.selected_count == 0) return;
    for (0..s.selected_count) |si| {
        const i = s.selected[si];
        const u = &s.units[i];
        if (u.owner != .player) continue;
        const start = u.pos();
        const goal = coords.Pos{ .x = s.cursor_x, .y = s.cursor_y };

        var blocked_buf: [256]coords.Pos = undefined;
        const blocked_count = queries.collectBlocked(s.spatialCtx(), &blocked_buf, i);
        const blocked_slice = if (blocked_count > 0) blocked_buf[0..blocked_count] else null;

        var target = goal;
        const len = astar.findPath(s.allocator, &s.world, start, goal, u.path, blocked_slice) orelse blk: {
            const nearest = astar.findNearestReachable(s.allocator, &s.world, goal, blocked_slice) orelse continue;
            target = nearest;
            break :blk astar.findPath(s.allocator, &s.world, start, nearest, u.path, blocked_slice) orelse continue;
        };
        if (len == 0) continue;
        u.path_len = len;
        u.path_idx = 0;
        u.state = .moving;
        u.dest = target;
    }
}

pub fn handle(s: *State, key: terminal.Key) void {
    if (s.help_mode) {
        if (key.isEscape() or key.isChar('?')) {
            s.help_mode = false;
        } else if (key.isCtrl('c')) {
            s.quit = true;
        }
        return;
    }
    if (s.coord_mode) {
        handleCoord(s, key);
        return;
    }
    if (s.gather_mode) {
        handleGather(s, key);
        return;
    }

    if (key.isChar('q') or key.isCtrl('c')) {
        s.quit = true;
    } else if (shiftDir(key, -1, 0)) {
        moveCursor(s, -1, 0);
        addUnitAtCursor(s);
    } else if (shiftDir(key, 1, 0)) {
        moveCursor(s, 1, 0);
        addUnitAtCursor(s);
    } else if (shiftDir(key, 0, -1)) {
        moveCursor(s, 0, -1);
        addUnitAtCursor(s);
    } else if (shiftDir(key, 0, 1)) {
        moveCursor(s, 0, 1);
        addUnitAtCursor(s);
    } else if (key.isLeft() or key.isChar('h')) {
        moveCursor(s, -1, 0);
    } else if (key.isRight() or key.isChar('l')) {
        moveCursor(s, 1, 0);
    } else if (key.isUp() or key.isChar('k')) {
        moveCursor(s, 0, -1);
    } else if (key.isDown() or key.isChar('j')) {
        moveCursor(s, 0, 1);
    } else if (key.isChar('t')) {
        trainWorker(s);
    } else if (key.isChar('y')) {
        trainSoldier(s);
    } else if (key.isChar('m')) {
        moveSelected(s);
    } else if (key.isShiftTab()) {
        selection.selectPrev(s.unitSelection());
    } else if (key.isTab()) {
        selection.selectNext(s.unitSelection());
    } else if (key.isChar('n')) {
        selection.selectNextBuilding(s.buildingSelection());
    } else if (key.isChar('N')) {
        selection.selectPrevBuilding(s.buildingSelection());
    } else if (key.isChar('g')) {
        state.gatherAtCursor(s);
    } else if (key.isChar('G')) {
        s.gather_mode = true;
    } else if (key.isChar('w')) {
        selection.selectIdleWorkers(s.unitSelection());
    } else if (key.isChar('r')) {
        _ = state.resowSelected(s);
    } else if (key.isChar('?')) {
        s.help_mode = true;
    } else if (key.isChar('c')) {
        s.coord_mode = true;
        s.coord_len = 0;
    }
}

fn shiftDir(key: terminal.Key, dx: isize, dy: isize) bool {
    if (!key.shift) return false;
    if (dx < 0 and (key.isLeft() or key.isChar('H'))) return true;
    if (dx > 0 and (key.isRight() or key.isChar('L'))) return true;
    if (dy < 0 and (key.isUp() or key.isChar('K'))) return true;
    if (dy > 0 and (key.isDown() or key.isChar('J'))) return true;
    return false;
}

pub fn trainWorker(s: *State) void {
    if (s.selected_building) |bi| {
        if (bi < s.building_count) {
            const b = &s.buildings[bi];
            if (b.kind() == .town_center and b.owner == .player and b.isComplete()) {
                _ = training.enqueue(s, bi, .worker);
                return;
            }
        }
    }
    for (0..s.building_count) |i| {
        const b = &s.buildings[i];
        if (b.kind() == .town_center and b.owner == .player and b.isComplete()) {
            _ = training.enqueue(s, i, .worker);
            return;
        }
    }
}

pub fn trainSoldier(s: *State) void {
    if (s.selected_building) |bi| {
        if (bi < s.building_count) {
            const b = &s.buildings[bi];
            if (b.kind() == .barracks and b.owner == .player and b.isComplete()) {
                _ = training.enqueue(s, bi, .soldier);
                return;
            }
        }
    }
    for (0..s.building_count) |i| {
        const b = &s.buildings[i];
        if (b.kind() == .barracks and b.owner == .player and b.isComplete()) {
            _ = training.enqueue(s, i, .soldier);
            return;
        }
    }
}

fn addUnitAtCursor(s: *State) void {
    if (lib_spatial.indexOfAt((s.spatialCtx()).units, s.cursor_x, s.cursor_y)) |ui| {
        selection.selectAdd(s.unitSelection(), ui);
    }
}

fn handleGather(s: *State, key: terminal.Key) void {
    if (key.isEscape()) {
        s.gather_mode = false;
        return;
    }
    if (key.isChar('w') or key.isChar('W')) {
        state.gatherNearest(s, .wood);
        s.gather_mode = false;
    } else if (key.isChar('d') or key.isChar('D')) {
        state.gatherNearest(s, .deer);
        s.gather_mode = false;
    } else if (key.isChar('f') or key.isChar('F')) {
        state.gatherNearest(s, .farm);
        s.gather_mode = false;
    } else if (key.isCtrl('c')) {
        s.quit = true;
    }
}

fn handleCoord(s: *State, key: terminal.Key) void {
    if (key.isEscape()) {
        s.coord_mode = false;
        s.coord_len = 0;
        return;
    }

    if (key.isEnter()) {
        if (coords.parseCoord(s.coord_buf[0..], s.coord_len)) |coord_val| {
            if (coord_val.x < s.world.width and coord_val.y < s.world.height) {
                s.cursor_x = coord_val.x;
                s.cursor_y = coord_val.y;
            }
        }
        s.coord_mode = false;
        s.coord_len = 0;
        return;
    }

    if (key.kind == .char and !key.ctrl and s.coord_len < s.coord_buf.len) {
        const ch = key.char_val;
        if (ch >= 'A' and ch <= 'Z') {
            s.coord_buf[s.coord_len] = ch;
            s.coord_len += 1;
        } else if (ch >= '0' and ch <= '9' and s.coord_len > 0) {
            s.coord_buf[s.coord_len] = ch;
            s.coord_len += 1;
        } else if (ch >= 'a' and ch <= 'z') {
            s.coord_buf[s.coord_len] = ch - 32;
            s.coord_len += 1;
        }
    }

    if (key.isCtrl('c')) {
        s.quit = true;
    }
}

test "handle: 'q' sets quit flag" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    try std.testing.expect(!s.quit);
    const key = terminal.Key{ .kind = .char, .char_val = 'q' };
    handle(&s, key);
    try std.testing.expect(s.quit);
}

test "handle: ctrl-c sets quit flag" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const key = terminal.Key{ .kind = .char, .char_val = 'c', .ctrl = true };
    handle(&s, key);
    try std.testing.expect(s.quit);
}

test "handle: 'h' moves cursor left" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.cursor_x = 10;
    const key = terminal.Key{ .kind = .char, .char_val = 'h' };
    handle(&s, key);
    try std.testing.expectEqual(@as(usize, 9), s.cursor_x);
}

test "handle: left arrow moves cursor left" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.cursor_x = 10;
    const key = terminal.Key{ .kind = .left };
    handle(&s, key);
    try std.testing.expectEqual(@as(usize, 9), s.cursor_x);
}

test "handle: 'l' moves cursor right" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.cursor_x = 10;
    const key = terminal.Key{ .kind = .char, .char_val = 'l' };
    handle(&s, key);
    try std.testing.expectEqual(@as(usize, 11), s.cursor_x);
}

test "handle: 'k' moves cursor up" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.cursor_y = 10;
    const key = terminal.Key{ .kind = .char, .char_val = 'k' };
    handle(&s, key);
    try std.testing.expectEqual(@as(usize, 9), s.cursor_y);
}

test "handle: 'j' moves cursor down" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.cursor_y = 10;
    const key = terminal.Key{ .kind = .char, .char_val = 'j' };
    handle(&s, key);
    try std.testing.expectEqual(@as(usize, 11), s.cursor_y);
}

test "handle: 't' enqueues worker" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const initial_queue_count = s.training_queue_count;
    const key = terminal.Key{ .kind = .char, .char_val = 't' };
    handle(&s, key);
    try std.testing.expectEqual(initial_queue_count + 1, s.training_queue_count);
}

test "handle: tab cycles selection forward" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    if (s.unit_count < 2) return;
    const initial = selection.primarySelected(s.unitSelection()) orelse return;
    const key = terminal.Key{ .kind = .tab };
    handle(&s, key);
    const after = selection.primarySelected(s.unitSelection()) orelse return;
    try std.testing.expect(initial != after);
}

test "handle: 'c' enters coord mode" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    try std.testing.expect(!s.coord_mode);
    const key = terminal.Key{ .kind = .char, .char_val = 'c' };
    handle(&s, key);
    try std.testing.expect(s.coord_mode);
}

test "handle: '?' opens help mode" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    try std.testing.expect(!s.help_mode);
    handle(&s, .{ .kind = .char, .char_val = '?' });
    try std.testing.expect(s.help_mode);
}

test "handle: help mode escape closes" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.help_mode = true;
    handle(&s, .{ .kind = .escape });
    try std.testing.expect(!s.help_mode);
}

test "handle: help mode '?' closes" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.help_mode = true;
    handle(&s, .{ .kind = .char, .char_val = '?' });
    try std.testing.expect(!s.help_mode);
}

test "handle: help mode swallows movement keys" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.help_mode = true;
    s.cursor_x = 10;
    handle(&s, .{ .kind = .char, .char_val = 'h' });
    try std.testing.expectEqual(@as(usize, 10), s.cursor_x);
    try std.testing.expect(s.help_mode);
}

test "handle: coord mode builds coordinate and moves cursor" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();

    s.coord_mode = true;
    s.coord_len = 0;

    handle(&s, .{ .kind = .char, .char_val = 'a' });
    handle(&s, .{ .kind = .char, .char_val = '5' });

    handle(&s, .{ .kind = .enter });

    try std.testing.expect(!s.coord_mode);
    try std.testing.expectEqual(@as(usize, 0), s.cursor_x);
    try std.testing.expectEqual(@as(usize, 4), s.cursor_y);
}

test "handle: coord mode escape cancels" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();

    s.coord_mode = true;
    s.coord_len = 0;
    handle(&s, .{ .kind = .char, .char_val = 'a' });

    handle(&s, .{ .kind = .escape });

    try std.testing.expect(!s.coord_mode);
    try std.testing.expectEqual(@as(usize, 0), s.coord_len);
}

test "handle: coord mode lowercase converts to uppercase" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();

    s.coord_mode = true;
    s.coord_len = 0;

    handle(&s, .{ .kind = .char, .char_val = 'z' });

    try std.testing.expectEqual(@as(u8, 'Z'), s.coord_buf[0]);
    try std.testing.expectEqual(@as(usize, 1), s.coord_len);
}

test "moveCursor clamps to bounds" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 1, 80, 45, &cfg);
    defer s.deinit();
    s.cursor_x = 0;
    s.cursor_y = 0;
    moveCursor(&s, -1, 0);
    try std.testing.expectEqual(@as(usize, 0), s.cursor_x);

    s.cursor_x = s.world.width - 1;
    moveCursor(&s, 1, 0);
    try std.testing.expectEqual(s.world.width - 1, s.cursor_x);

    s.cursor_y = 0;
    moveCursor(&s, 0, -1);
    try std.testing.expectEqual(@as(usize, 0), s.cursor_y);

    s.cursor_y = s.world.height - 1;
    moveCursor(&s, 0, 1);
    try std.testing.expectEqual(s.world.height - 1, s.cursor_y);
}

test "moveCursor normal movement" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.cursor_x = 10;
    s.cursor_y = 10;
    moveCursor(&s, 5, -3);
    try std.testing.expectEqual(@as(usize, 15), s.cursor_x);
    try std.testing.expectEqual(@as(usize, 7), s.cursor_y);
}

test "moveSelected sets unit on path" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.units[0].x = s.world.player_tc_x + 1;
    s.units[0].y = s.world.player_tc_y;
    selection.selectSingle(s.unitSelection(), 0);
    s.cursor_x = s.world.player_tc_x + 4;
    s.cursor_y = s.world.player_tc_y;
    for (s.world.player_tc_x + 1..s.world.player_tc_x + 5) |x| {
        s.world.set(x, s.world.player_tc_y, .grass);
    }
    moveSelected(&s);
    try std.testing.expectEqual(unit.UnitActivity.moving, s.units[0].state);
}

test "moveSelected with no selection does nothing" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    selection.selectClear(s.unitSelection());
    moveSelected(&s);
}

test "moveSelected ignores enemy unit" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const enemy_idx = blk: {
        for (0..s.unit_count) |i| {
            if (s.units[i].owner == .enemy) break :blk i;
        }
        break :blk @as(usize, 0);
    };
    selection.selectSingle(s.unitSelection(), enemy_idx);
    s.cursor_x = 10;
    s.cursor_y = 10;
    moveSelected(&s);
    try std.testing.expectEqual(unit.UnitActivity.idle, s.units[enemy_idx].state);
}
