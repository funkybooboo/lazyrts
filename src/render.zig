const std = @import("std");
const terminal = @import("terminal.zig");
const game = @import("game.zig");
const map = @import("map.zig");
const entity = @import("entity.zig");
const drawer = @import("drawer.zig");
const color = @import("color.zig");
const config = @import("config.zig");

pub fn draw(canvas: terminal.Canvas, state: *const game.State) void {
    canvas.clear();

    const cfg = state.cfg;
    const lw: u16 = cfg.ui.label_width;
    const map_w: u16 = state.world.width;
    const map_h: u16 = state.world.height;
    const header_height: u16 = game.header_height(map_w);
    const drawer_top: u16 = canvas.height() -| cfg.ui.drawer_height;

    draw_col_headers(canvas, lw, header_height, map_w, state);
    draw_row_labels(canvas, lw, header_height, map_h, state, drawer_top);

    const rows: u16 = @min(map_h, canvas.height() -| header_height -| cfg.ui.drawer_height);
    const cols: u16 = @min(map_w, canvas.width() -| lw);

    for (0..rows) |row| {
        for (0..cols) |col| {
            const unit_x: usize = @intCast(col);
            const unit_y: usize = @intCast(row);
            const is_cursor = unit_x == state.cursor_x and unit_y == state.cursor_y;
            const screen_x: u16 = @intCast(lw + col);
            const screen_y: u16 = @intCast(header_height + row);
            if (screen_y >= drawer_top) continue;

            if (game.unit_at(state, unit_x, unit_y)) |ui| {
                const u = &state.units[ui];
                const is_selected = state.selected_unit != null and state.selected_unit.? == ui;
                const s = cell_style(.unit, color.unit_color(u, cfg), is_selected, is_cursor, cfg);
                canvas.write_cell(screen_x, screen_y, u.kind.glyph(state.cfg), s);
            } else if (game.building_at(state, unit_x, unit_y)) |bi| {
                const b = &state.buildings[bi];
                const s = cell_style(.building, color.building_color(b, cfg), false, is_cursor, cfg);
                canvas.write_cell(screen_x, screen_y, b.kind.glyph(state.cfg), s);
            } else {
                const t = state.world.at(unit_x, unit_y);
                var s = tile_style(t, cfg);
                if (is_cursor) s.reverse = true;
                canvas.write_cell(screen_x, screen_y, t.glyph(state.cfg), s);
            }
        }
    }

    drawer.draw(canvas, state);
}

const CellKind = enum { unit, building };

fn cell_style(kind: CellKind, fg_rgb: [3]u8, is_selected: bool, is_cursor: bool, cfg: *const config.Config) terminal.Style {
    const bold = kind == .building or is_selected;
    if (is_selected and is_cursor) {
        return .{ .fg = .{ .rgb = fg_rgb }, .bg = .{ .rgb = cfg.colors.cursor_selected_bg }, .bold = true };
    }
    if (is_selected) {
        return .{ .fg = .{ .rgb = cfg.colors.cursor_reversed_fg }, .bg = .{ .rgb = fg_rgb }, .bold = true };
    }
    if (is_cursor) {
        return .{ .fg = .{ .rgb = cfg.colors.cursor_reversed_fg }, .bg = .{ .rgb = fg_rgb }, .bold = true };
    }
    return .{ .fg = .{ .rgb = fg_rgb }, .bold = bold };
}

fn draw_col_headers(canvas: terminal.Canvas, lw: u16, hh: u16, map_w: u16, state: *const game.State) void {
    const cfg = state.cfg;
    const dim: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.header_dim } };
    const active: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.header_active }, .bold = true };

    for (0..map_w) |col| {
        var buf: [3]u8 = undefined;
        const letters = game.col_to_letters(col, &buf);
        const is_active = col == state.cursor_x;
        const s: terminal.Style = if (is_active) active else dim;
        const col_x: u16 = @intCast(lw + col);
        for (letters, 0..) |ch, i| {
            const row_y: u16 = hh - @as(u16, @intCast(letters.len)) + @as(u16, @intCast(i));
            canvas.write_cell(col_x, row_y, &[_]u8{ch}, s);
        }
    }
}

fn draw_row_labels(canvas: terminal.Canvas, lw: u16, hh: u16, map_h: u16, state: *const game.State, max_y: u16) void {
    const cfg = state.cfg;
    const dim: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.header_dim } };
    const active: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.header_active }, .bold = true };

    for (0..map_h) |row| {
        const ly: u16 = hh + @as(u16, @intCast(row));
        if (ly >= max_y) break;

        var buf: [8]u8 = undefined;
        var n: usize = row + 1;
        var tmp: [8]u8 = undefined;
        var ti: usize = 0;
        while (n > 0) {
            tmp[ti] = '0' + @as(u8, @intCast(n % 10));
            n /= 10;
            ti += 1;
        }
        var j: usize = 0;
        while (ti > 0) {
            ti -= 1;
            buf[j] = tmp[ti];
            j += 1;
        }
        const text = buf[0..j];
        const s: terminal.Style = if (row == state.cursor_y) active else dim;
        const x_start: u16 = lw -| @as(u16, @intCast(text.len));
        canvas.write_str(x_start, ly, text, s);
    }
}

fn tile_style(t: map.Tile, cfg: *const config.Config) terminal.Style {
    return switch (t) {
        .grass => .{},
        .tree => .{ .fg = .{ .rgb = cfg.colors.tile_tree } },
        .water => .{ .fg = .{ .rgb = cfg.colors.tile_water } },
        .town_center, .house, .barracks => .{ .fg = .{ .rgb = cfg.colors.building_tile } },
    };
}
