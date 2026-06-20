const std = @import("std");
const term = @import("terminal.zig");
const game = @import("game.zig");
const map = @import("map.zig");
const entity = @import("entity.zig");
const drawer = @import("drawer.zig");
const color = @import("color.zig");

const HEADER_DIM = .{ 140, 140, 140 };
const HEADER_ACTIVE = .{ 255, 255, 255 };
const CURSOR_SELECTED_BG = .{ 40, 40, 40 };
const CURSOR_REVERSED_FG = .{ 20, 20, 20 };
const BUILDING_TILE_COLOR = .{ 200, 200, 200 };

pub fn draw(canvas: term.Canvas, state: *const game.State) void {
    canvas.clear();

    const lw: u16 = game.LABEL_WIDTH;
    const map_w: u16 = state.world.width;
    const map_h: u16 = state.world.height;
    const hh: u16 = game.headerHeight(map_w);
    const drawer_top: u16 = canvas.height() -| game.DRAWER_HEIGHT;

    draw_col_headers(canvas, lw, hh, map_w, state);
    draw_row_labels(canvas, lw, hh, map_h, state, drawer_top);

    const rows: u16 = @min(map_h, canvas.height() -| hh -| game.DRAWER_HEIGHT);
    const cols: u16 = @min(map_w, canvas.width() -| lw);

    for (0..rows) |row| {
        for (0..cols) |col| {
            const ux: usize = @intCast(col);
            const uy: usize = @intCast(row);
            const is_cursor = ux == state.cursor_x and uy == state.cursor_y;
            const sx: u16 = @intCast(lw + col);
            const sy: u16 = @intCast(hh + row);
            if (sy >= drawer_top) continue;

            if (game.unit_at(state, ux, uy)) |ui| {
                const u = &state.units[ui];
                const is_selected = state.selected_unit != null and state.selected_unit.? == ui;
                const s = cell_style(.unit, color.unit_color(u), is_selected, is_cursor);
                canvas.write_cell(sx, sy, u.kind.glyph(), s);
            } else if (game.building_at(state, ux, uy)) |bi| {
                const b = &state.buildings[bi];
                const s = cell_style(.building, color.building_color(b), false, is_cursor);
                canvas.write_cell(sx, sy, b.kind.glyph(), s);
            } else {
                const t = state.world.at(ux, uy);
                var s = tile_style(t);
                if (is_cursor) s.reverse = true;
                canvas.write_cell(sx, sy, t.glyph(), s);
            }
        }
    }

    drawer.draw(canvas, state);
}

const CellKind = enum { unit, building };

fn cell_style(kind: CellKind, fg_rgb: [3]u8, is_selected: bool, is_cursor: bool) term.Style {
    const bold = kind == .building or is_selected;
    if (is_selected and is_cursor) {
        return .{ .fg = .{ .rgb = fg_rgb }, .bg = .{ .rgb = CURSOR_SELECTED_BG }, .bold = true };
    }
    if (is_selected) {
        return .{ .fg = .{ .rgb = CURSOR_REVERSED_FG }, .bg = .{ .rgb = fg_rgb }, .bold = true };
    }
    if (is_cursor) {
        return .{ .fg = .{ .rgb = CURSOR_REVERSED_FG }, .bg = .{ .rgb = fg_rgb }, .bold = true };
    }
    return .{ .fg = .{ .rgb = fg_rgb }, .bold = bold };
}

fn draw_col_headers(canvas: term.Canvas, lw: u16, hh: u16, map_w: u16, state: *const game.State) void {
    const dim: term.Style = .{ .fg = .{ .rgb = HEADER_DIM } };
    const active: term.Style = .{ .fg = .{ .rgb = HEADER_ACTIVE }, .bold = true };

    for (0..map_w) |col| {
        var buf: [3]u8 = undefined;
        const letters = game.col_to_letters(col, &buf);
        const is_active = col == state.cursor_x;
        const s: term.Style = if (is_active) active else dim;
        const col_x: u16 = @intCast(lw + col);
        for (letters, 0..) |ch, i| {
            const row_y: u16 = hh - @as(u16, @intCast(letters.len)) + @as(u16, @intCast(i));
            canvas.write_cell(col_x, row_y, &[_]u8{ch}, s);
        }
    }
}

fn draw_row_labels(canvas: term.Canvas, lw: u16, hh: u16, map_h: u16, state: *const game.State, max_y: u16) void {
    const dim: term.Style = .{ .fg = .{ .rgb = HEADER_DIM } };
    const active: term.Style = .{ .fg = .{ .rgb = HEADER_ACTIVE }, .bold = true };

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
        const s: term.Style = if (row == state.cursor_y) active else dim;
        const x_start: u16 = lw -| @as(u16, @intCast(text.len));
        canvas.write_str(x_start, ly, text, s);
    }
}

fn tile_style(t: map.Tile) term.Style {
    return switch (t) {
        .grass => .{},
        .tree => .{ .fg = .{ .rgb = color.tile_colors.tree } },
        .water => .{ .fg = .{ .rgb = color.tile_colors.water } },
        .town_center, .house, .barracks => .{ .fg = .{ .rgb = BUILDING_TILE_COLOR } },
    };
}
