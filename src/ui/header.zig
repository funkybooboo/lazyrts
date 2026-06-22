const terminal = @import("../lib/terminal.zig");
const state_mod = @import("../game/state.zig");
const config = @import("../config.zig");
const coords = @import("../lib/coords.zig");
const fmt = @import("../lib/fmt.zig");

pub fn drawColHeaders(canvas: terminal.Canvas, lw: u16, hh: u16, map_w: u16, state: *const state_mod.State) void {
    const cfg = state.cfg;
    const dim: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.header_dim } };
    const active: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.header_active }, .bold = true };

    for (0..map_w) |col| {
        var buf: [3]u8 = undefined;
        const letters = coords.colToLetters(col, &buf);
        const is_active = col == state.cursor_x;
        const s: terminal.Style = if (is_active) active else dim;
        const col_x: u16 = @intCast(lw + col);
        for (letters, 0..) |ch, i| {
            const row_y: u16 = hh - @as(u16, @intCast(letters.len)) + @as(u16, @intCast(i));
            canvas.writeCell(col_x, row_y, &[_]u8{ch}, s);
        }
    }
}

pub fn drawRowLabels(canvas: terminal.Canvas, lw: u16, hh: u16, map_h: u16, state: *const state_mod.State, max_y: u16) void {
    const cfg = state.cfg;
    const dim: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.header_dim } };
    const active: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.header_active }, .bold = true };

    for (0..map_h) |row| {
        const ly: u16 = hh + @as(u16, @intCast(row));
        if (ly >= max_y) break;

        var buf: [8]u8 = undefined;
        const text_len = fmt.formatUint(&buf, row + 1);
        const text = buf[0..text_len];
        const s: terminal.Style = if (row == state.cursor_y) active else dim;
        const x_start: u16 = lw -| @as(u16, @intCast(text.len));
        canvas.writeStr(x_start, ly, text, s);
    }
}
