const terminal = @import("terminal.zig");
const game = @import("game.zig");
const coord = @import("coord.zig");

pub fn handle(s: *game.State, key: terminal.Key) void {
    if (s.coord_mode) {
        handle_coord(s, key);
        return;
    }
    if (s.gather_mode) {
        handle_gather(s, key);
        return;
    }

    if (key.is_char('q') or key.is_ctrl('c')) {
        s.quit = true;
    } else if (shift_dir(key, -1, 0)) {
        game.move_cursor(s, -1, 0);
        add_unit_at_cursor(s);
    } else if (shift_dir(key, 1, 0)) {
        game.move_cursor(s, 1, 0);
        add_unit_at_cursor(s);
    } else if (shift_dir(key, 0, -1)) {
        game.move_cursor(s, 0, -1);
        add_unit_at_cursor(s);
    } else if (shift_dir(key, 0, 1)) {
        game.move_cursor(s, 0, 1);
        add_unit_at_cursor(s);
    } else if (key.is_left() or key.is_char('h')) {
        game.move_cursor(s, -1, 0);
    } else if (key.is_right() or key.is_char('l')) {
        game.move_cursor(s, 1, 0);
    } else if (key.is_up() or key.is_char('k')) {
        game.move_cursor(s, 0, -1);
    } else if (key.is_down() or key.is_char('j')) {
        game.move_cursor(s, 0, 1);
    } else if (key.is_char('t')) {
        _ = game.spawn_worker(s);
    } else if (key.is_char('m')) {
        game.move_selected(s);
    } else if (key.is_shift_tab()) {
        game.select_prev(s);
    } else if (key.is_tab()) {
        game.select_next(s);
    } else if (key.is_char('n')) {
        game.select_next_building(s);
    } else if (key.is_char('N')) {
        game.select_prev_building(s);
    } else if (key.is_char('g')) {
        game.gather_at_cursor(s);
    } else if (key.is_char('G')) {
        s.gather_mode = true;
    } else if (key.is_char('w')) {
        game.select_idle_workers(s);
    } else if (key.is_char('r')) {
        _ = game.resow_selected(s);
    } else if (key.is_char('c')) {
        s.coord_mode = true;
        s.coord_len = 0;
    }
}

fn shift_dir(key: terminal.Key, dx: isize, dy: isize) bool {
    if (!key.shift) return false;
    if (dx < 0 and (key.is_left() or key.is_char('H'))) return true;
    if (dx > 0 and (key.is_right() or key.is_char('L'))) return true;
    if (dy < 0 and (key.is_up() or key.is_char('K'))) return true;
    if (dy > 0 and (key.is_down() or key.is_char('J'))) return true;
    return false;
}

fn add_unit_at_cursor(s: *game.State) void {
    if (game.unit_at(s, s.cursor_x, s.cursor_y)) |ui| {
        game.select_add(s, ui);
    }
}

fn handle_gather(s: *game.State, key: terminal.Key) void {
    if (key.is_escape()) {
        s.gather_mode = false;
        return;
    }
    if (key.is_char('w') or key.is_char('W')) {
        game.gather_nearest(s, .wood);
        s.gather_mode = false;
    } else if (key.is_char('d') or key.is_char('D')) {
        game.gather_nearest(s, .deer);
        s.gather_mode = false;
    } else if (key.is_char('f') or key.is_char('F')) {
        game.gather_nearest(s, .farm);
        s.gather_mode = false;
    } else if (key.is_ctrl('c')) {
        s.quit = true;
    }
}

fn handle_coord(s: *game.State, key: terminal.Key) void {
    if (key.is_escape()) {
        s.coord_mode = false;
        s.coord_len = 0;
        return;
    }

    if (key.is_enter()) {
        if (coord.parse_coord(s.coord_buf[0..], s.coord_len)) |coord_val| {
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

    if (key.is_ctrl('c')) {
        s.quit = true;
    }
}

const std = @import("std");
const config = @import("config.zig");

test "handle: 'q' sets quit flag" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try game.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    try std.testing.expect(!s.quit);
    const key = terminal.Key{ .kind = .char, .char_val = 'q' };
    handle(&s, key);
    try std.testing.expect(s.quit);
}

test "handle: ctrl-c sets quit flag" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try game.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const key = terminal.Key{ .kind = .char, .char_val = 'c', .ctrl = true };
    handle(&s, key);
    try std.testing.expect(s.quit);
}

test "handle: 'h' moves cursor left" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try game.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.cursor_x = 10;
    const key = terminal.Key{ .kind = .char, .char_val = 'h' };
    handle(&s, key);
    try std.testing.expectEqual(@as(usize, 9), s.cursor_x);
}

test "handle: left arrow moves cursor left" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try game.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.cursor_x = 10;
    const key = terminal.Key{ .kind = .left };
    handle(&s, key);
    try std.testing.expectEqual(@as(usize, 9), s.cursor_x);
}

test "handle: 'l' moves cursor right" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try game.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.cursor_x = 10;
    const key = terminal.Key{ .kind = .char, .char_val = 'l' };
    handle(&s, key);
    try std.testing.expectEqual(@as(usize, 11), s.cursor_x);
}

test "handle: 'k' moves cursor up" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try game.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.cursor_y = 10;
    const key = terminal.Key{ .kind = .char, .char_val = 'k' };
    handle(&s, key);
    try std.testing.expectEqual(@as(usize, 9), s.cursor_y);
}

test "handle: 'j' moves cursor down" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try game.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.cursor_y = 10;
    const key = terminal.Key{ .kind = .char, .char_val = 'j' };
    handle(&s, key);
    try std.testing.expectEqual(@as(usize, 11), s.cursor_y);
}

test "handle: 't' spawns worker" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try game.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const initial_count = s.unit_count;
    const key = terminal.Key{ .kind = .char, .char_val = 't' };
    handle(&s, key);
    try std.testing.expectEqual(initial_count + 1, s.unit_count);
}

test "handle: tab cycles selection forward" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try game.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    if (s.unit_count < 2) return;
    const initial = game.primary_selected(&s) orelse return;
    const key = terminal.Key{ .kind = .tab };
    handle(&s, key);
    const after = game.primary_selected(&s) orelse return;
    try std.testing.expect(initial != after);
}

test "handle: 'c' enters coord mode" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try game.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    try std.testing.expect(!s.coord_mode);
    const key = terminal.Key{ .kind = .char, .char_val = 'c' };
    handle(&s, key);
    try std.testing.expect(s.coord_mode);
}

test "handle: coord mode builds coordinate and moves cursor" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try game.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    
    // Enter coord mode
    s.coord_mode = true;
    s.coord_len = 0;
    
    // Type "a5"
    handle(&s, .{ .kind = .char, .char_val = 'a' });
    handle(&s, .{ .kind = .char, .char_val = '5' });
    
    // Press enter
    handle(&s, .{ .kind = .enter });
    
    try std.testing.expect(!s.coord_mode);
    try std.testing.expectEqual(@as(usize, 0), s.cursor_x);
    try std.testing.expectEqual(@as(usize, 4), s.cursor_y);
}

test "handle: coord mode escape cancels" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try game.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    
    s.coord_mode = true;
    s.coord_len = 0;
    handle(&s, .{ .kind = .char, .char_val = 'a' });
    
    // Press escape
    handle(&s, .{ .kind = .escape });
    
    try std.testing.expect(!s.coord_mode);
    try std.testing.expectEqual(@as(usize, 0), s.coord_len);
}

test "handle: coord mode lowercase converts to uppercase" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try game.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    
    s.coord_mode = true;
    s.coord_len = 0;
    
    // Type lowercase 'z'
    handle(&s, .{ .kind = .char, .char_val = 'z' });
    
    try std.testing.expectEqual(@as(u8, 'Z'), s.coord_buf[0]);
    try std.testing.expectEqual(@as(usize, 1), s.coord_len);
}
