const term = @import("terminal.zig");
const game = @import("game.zig");

pub fn handle(s: *game.State, key: term.Key) void {
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
    } else if (key.is_tab()) {
        game.select_next(s);
    }
}
