const term = @import("terminal.zig");
const game = @import("game.zig");
const map = @import("map.zig");
const entity = @import("entity.zig");

pub fn draw(canvas: term.Canvas, state: *const game.State) void {
    canvas.clear();

    const rows: u16 = @min(canvas.height(), @as(u16, @intCast(map.HEIGHT)));
    const cols: u16 = @min(canvas.width(), @as(u16, @intCast(map.WIDTH)));

    for (0..rows) |y| {
        for (0..cols) |x| {
            const ux: usize = @intCast(x);
            const uy: usize = @intCast(y);
            const is_cursor = ux == state.cursor_x and uy == state.cursor_y;

            if (game.unit_at(state, ux, uy)) |ui| {
                const u = &state.units[ui];
                const is_selected = state.selected_unit != null and state.selected_unit.? == ui;
                var s = unit_style(u, is_selected);
                if (is_cursor) s.reverse = true;
                canvas.write_cell(@intCast(x), @intCast(y), u.kind.glyph(), s);
            } else {
                const t = state.world.at(ux, uy);
                var s = tile_style(t);
                if (is_cursor) s.reverse = true;
                canvas.write_cell(@intCast(x), @intCast(y), t.glyph(), s);
            }
        }
    }
}

fn tile_style(t: map.Tile) term.Style {
    return switch (t) {
        .grass => .{},
        .tree => .{ .fg = .{ .index = 2 } },
        .water => .{ .fg = .{ .index = 4 } },
        .town_center => .{ .fg = .{ .rgb = .{ 255, 215, 0 } }, .bold = true },
        .house => .{ .fg = .{ .index = 3 } },
        .barracks => .{ .fg = .{ .index = 1 } },
        .farm => .{ .fg = .{ .index = 10 } },
    };
}

fn unit_style(u: *const entity.Unit, is_selected: bool) term.Style {
    const fg: term.Color = switch (u.owner) {
        .player => switch (u.kind) {
            .worker => .{ .rgb = .{ 100, 180, 255 } },
            .soldier => .{ .rgb = .{ 255, 100, 100 } },
        },
        .enemy => switch (u.kind) {
            .worker => .{ .rgb = .{ 255, 165, 0 } },
            .soldier => .{ .rgb = .{ 255, 50, 50 } },
        },
    };
    return .{ .fg = fg, .bold = is_selected };
}
