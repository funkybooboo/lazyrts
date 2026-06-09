const vaxis = @import("vaxis");
const game = @import("game.zig");
const map = @import("map.zig");

pub fn draw(vx: *vaxis.Vaxis, state: *const game.State) void {
    const win = vx.window();
    win.clear();

    const rows: usize = @intCast(win.height);
    const cols: usize = @intCast(win.width);

    for (0..@min(rows, map.HEIGHT)) |y| {
        for (0..@min(cols, map.WIDTH)) |x| {
            const t = state.world.at(x, y);
            const selected = x == state.cursor_x and y == state.cursor_y;
            win.writeCell(@intCast(x), @intCast(y), .{
                .char = .{ .grapheme = t.glyph() },
                .style = if (selected) .{ .reverse = true } else tile_style(t),
            });
        }
    }
}

fn tile_style(t: map.Tile) vaxis.Style {
    return switch (t) {
        .grass => .{},
        .tree => .{ .fg = .{ .index = 2 } },
        .water => .{ .fg = .{ .index = 4 } },
        .town_center => .{ .fg = .{ .rgb = .{ 255, 215, 0 } }, .bold = true },
        .house => .{ .fg = .{ .index = 3 } },
        .barracks => .{ .fg = .{ .index = 1 } },
        .farm => .{ .fg = .{ .index = 10 } },
        .worker => .{ .fg = .{ .rgb = .{ 100, 180, 255 } } },
        .soldier => .{ .fg = .{ .rgb = .{ 255, 100, 100 } } },
    };
}