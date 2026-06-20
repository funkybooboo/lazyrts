const terminal = @import("terminal.zig");
const game = @import("game.zig");
const coord = @import("coord.zig");

pub fn handle(s: *game.State, key: terminal.Key) void {
    if (s.coord_mode) {
        handle_coord(s, key);
        return;
    }

    if (key.is_char('q') or key.is_ctrl('c')) {
        s.quit = true;
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
    } else if (key.is_char('c')) {
        s.coord_mode = true;
        s.coord_len = 0;
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
