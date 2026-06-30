const terminal = @import("../lib/terminal.zig");
const state_mod = @import("../game/state.zig");
const map = @import("../game/map.zig");
const color = @import("color.zig");
const header = @import("header.zig");
const footer = @import("footer.zig");
const coords = @import("../lib/coords.zig");
const config = @import("../config.zig");
const queries = @import("../game/queries.zig");
const selection = @import("../game/selection.zig");
const perf = @import("../game/perf.zig");
const fmt = @import("../lib/fmt.zig");

pub fn draw(canvas: terminal.Canvas, state: *const state_mod.State) void {
    canvas.clear();

    const cfg = state.cfg;
    const lw: u16 = cfg.ui.label_width;
    const map_w: u16 = state.world.width;
    const map_h: u16 = state.world.height;
    const headerHeight: u16 = coords.headerHeight(map_w);
    const drawer_top: u16 = canvas.height() -| cfg.ui.drawer_height;

    header.drawColHeaders(canvas, lw, headerHeight, map_w, state);
    header.drawRowLabels(canvas, lw, headerHeight, map_h, state, drawer_top);

    const rows: u16 = @min(map_h, canvas.height() -| headerHeight -| cfg.ui.drawer_height);
    const cols: u16 = @min(map_w, canvas.width() -| lw);

    const ctx = state.spatialCtx();
    for (0..rows) |row| {
        for (0..cols) |col| {
            const unit_x: usize = @intCast(col);
            const unit_y: usize = @intCast(row);
            const is_cursor = unit_x == state.cursor_x and unit_y == state.cursor_y;
            const screen_x: u16 = @intCast(lw + col);
            const screen_y: u16 = @intCast(headerHeight + row);
            if (screen_y >= drawer_top) continue;

            if (ctx.unitAt(unit_x, unit_y)) |ui| {
                const u = &state.units[ui];
                const is_selected = selection.viewHasSelected(state.selectView(), ui);
                const s = cellStyle(.unit, color.unitColor(u, cfg), is_selected, is_cursor, cfg);
                canvas.writeCell(screen_x, screen_y, u.glyph(state.cfg), s);
            } else if (ctx.buildingAt(unit_x, unit_y)) |bi| {
                const b = &state.buildings[bi];
                const is_selected = selection.viewHasBuildingSelected(state.buildingView(), bi);
                const s = cellStyle(.building, color.buildingColor(b, cfg), is_selected, is_cursor, cfg);
                canvas.writeCell(screen_x, screen_y, b.glyph(state.cfg), s);
            } else if (ctx.wildlifeAt(unit_x, unit_y)) |ni| {
                const n = &state.wildlife[ni];
                const s = cellStyle(.unit, color.wildlifeColor(n, cfg), false, is_cursor, cfg);
                canvas.writeCell(screen_x, screen_y, n.glyph(state.cfg), s);
            } else {
                const t = state.world.at(unit_x, unit_y);
                var s = tileStyle(t, unit_x, unit_y, state, cfg);
                if (is_cursor) s.reverse = true;
                canvas.writeCell(screen_x, screen_y, t.glyph(state.cfg), s);
            }
        }
    }

    footer.draw(canvas, state);

    if (state.perf.enabled) drawPerf(canvas, state, cfg);
    if (state.help_mode) drawHelp(canvas, cfg);
}

const CellKind = enum { unit, building };

fn cellStyle(kind: CellKind, fg_rgb: [3]u8, is_selected: bool, is_cursor: bool, cfg: *const config.Config) terminal.Style {
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

fn tileStyle(t: map.Tile, x: usize, y: usize, state: *const state_mod.State, cfg: *const config.Config) terminal.Style {
    return switch (t) {
        .grass => .{},
        .tree => .{ .fg = .{ .rgb = color.treeTileColor(state.world.treeRemainingAt(x, y), cfg.economy.tree_total_yield, cfg) } },
        .water => .{ .fg = .{ .rgb = cfg.colors.tile_water } },
        .town_center, .house, .barracks => .{ .fg = .{ .rgb = cfg.colors.building_tile } },
    };
}

const help_entries = [_]struct { key: []const u8, desc: []const u8 }{
    .{ .key = "h j k l / arrows", .desc = "move cursor" },
    .{ .key = "Q / Ctrl-C", .desc = "quit" },
    .{ .key = "T", .desc = "train worker (TC)" },
    .{ .key = "Y", .desc = "train soldier (barracks)" },
    .{ .key = "M", .desc = "move selected unit to cursor" },
    .{ .key = "Tab / Shift+Tab", .desc = "cycle player units" },
    .{ .key = "n / N", .desc = "cycle player buildings" },
    .{ .key = "G", .desc = "gather at cursor" },
    .{ .key = "Shift+G", .desc = "gather menu (w=wood, d=deer, f=farm)" },
    .{ .key = "c", .desc = "coordinate jump (type A1, Enter)" },
    .{ .key = "w", .desc = "select idle workers" },
    .{ .key = "r", .desc = "resow fallow farm (60 wood)" },
    .{ .key = "Shift+dir", .desc = "add unit to selection" },
    .{ .key = "?", .desc = "toggle this help" },
};

fn drawHelp(canvas: terminal.Canvas, cfg: *const config.Config) void {
    const label: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.header_active }, .bold = true };
    const body: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.help_body } };
    const dim: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.header_dim } };

    var max_key: usize = 0;
    var max_desc: usize = 0;
    for (help_entries) |e| {
        if (e.key.len > max_key) max_key = e.key.len;
        if (e.desc.len > max_desc) max_desc = e.desc.len;
    }

    const title = " lazyrts -- help ";
    const inner_w: usize = max_key + 2 + max_desc + 2;
    const box_w: usize = @max(title.len, inner_w) + 4;
    const box_h: usize = help_entries.len + 4;

    const cw: usize = @intCast(canvas.width());
    const ch: usize = @intCast(canvas.height());
    if (box_w + 2 > cw or box_h + 2 > ch) return;
    const ox: usize = (cw - box_w) / 2;
    const oy: usize = (ch - box_h) / 2;

    const fill_bg = cfg.colors.help_bg;
    const border_fg: [3]u8 = cfg.colors.help_border;

    for (0..box_h) |y| {
        for (0..box_w) |x| {
            canvas.writeCell(@intCast(ox + x), @intCast(oy + y), " ", .{ .bg = .{ .rgb = fill_bg } });
        }
    }

    const tl = "+"; const tr = "+"; const bl = "+"; const br = "+";
    const horiz = "-"; const vert = "|";
    const bstyle: terminal.Style = .{ .fg = .{ .rgb = border_fg }, .bg = .{ .rgb = fill_bg }, .bold = true };

    canvas.writeStr(@intCast(ox), @intCast(oy), tl, bstyle);
    for (0..box_w - 2) |x| canvas.writeStr(@intCast(ox + 1 + x), @intCast(oy), horiz, bstyle);
    canvas.writeStr(@intCast(ox + box_w - 1), @intCast(oy), tr, bstyle);

    const title_x = ox + (box_w - title.len) / 2;
    canvas.writeStr(@intCast(title_x), @intCast(oy), title, label);

    for (0..box_h - 2) |y| {
        canvas.writeStr(@intCast(ox), @intCast(oy + 1 + y), vert, bstyle);
        canvas.writeStr(@intCast(ox + box_w - 1), @intCast(oy + 1 + y), vert, bstyle);
    }

    canvas.writeStr(@intCast(ox), @intCast(oy + box_h - 1), bl, bstyle);
    for (0..box_w - 2) |x| canvas.writeStr(@intCast(ox + 1 + x), @intCast(oy + box_h - 1), horiz, bstyle);
    canvas.writeStr(@intCast(ox + box_w - 1), @intCast(oy + box_h - 1), br, bstyle);

    const sep_y = oy + 2;
    canvas.writeStr(@intCast(ox + 1), @intCast(sep_y), horiz, bstyle);
    for (0..box_w - 4) |x| canvas.writeStr(@intCast(ox + 2 + x), @intCast(sep_y), horiz, bstyle);
    canvas.writeStr(@intCast(ox + box_w - 2), @intCast(sep_y), horiz, bstyle);

    for (help_entries, 0..) |e, i| {
        const ly: usize = oy + 3 + i;
        canvas.writeStr(@intCast(ox + 2), @intCast(ly), e.key, label);
        const desc_x: usize = ox + 2 + max_key + 2;
        canvas.writeStr(@intCast(desc_x), @intCast(ly), e.desc, body);
    }

    const foot_y: usize = oy + box_h - 1;
    const foot = " press ? or Esc to close ";
    const foot_x: usize = ox + (box_w - foot.len) / 2;
    canvas.writeStr(@intCast(foot_x), @intCast(foot_y), foot, dim);
}

fn drawPerf(canvas: terminal.Canvas, state: *const state_mod.State, cfg: *const config.Config) void {
    const label: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.header_active }, .bold = true };
    const val: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.drawer_val } };
    const dim: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.drawer_dim } };
    const border: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.help_border }, .bg = .{ .rgb = cfg.colors.help_bg } };
    const fill_bg = cfg.colors.help_bg;

    const title = " perf ";
    const box_w: usize = 30;
    const box_h: usize = 9;
    const cw: usize = @intCast(canvas.width());
    const ch: usize = @intCast(canvas.height());
    if (box_w + 2 > cw or box_h + 2 > ch) return;
    const ox: usize = 1;
    const oy: usize = 1;

    for (0..box_h) |y| {
        for (0..box_w) |x| {
            canvas.writeCell(@intCast(ox + x), @intCast(oy + y), " ", .{ .bg = .{ .rgb = fill_bg } });
        }
    }
    canvas.writeStr(@intCast(ox), @intCast(oy), "+", border);
    for (0..box_w - 2) |x| canvas.writeStr(@intCast(ox + 1 + x), @intCast(oy), "-", border);
    canvas.writeStr(@intCast(ox + box_w - 1), @intCast(oy), "+", border);
    for (0..box_h - 2) |y| {
        canvas.writeStr(@intCast(ox), @intCast(oy + 1 + y), "|", border);
        canvas.writeStr(@intCast(ox + box_w - 1), @intCast(oy + 1 + y), "|", border);
    }
    canvas.writeStr(@intCast(ox), @intCast(oy + box_h - 1), "+", border);
    for (0..box_w - 2) |x| canvas.writeStr(@intCast(ox + 1 + x), @intCast(oy + box_h - 1), "-", border);
    canvas.writeStr(@intCast(ox + box_w - 1), @intCast(oy + box_h - 1), "+", border);
    const title_x = ox + (box_w - title.len) / 2;
    canvas.writeStr(@intCast(title_x), @intCast(oy), title, label);

    var us_buf: [12]u8 = undefined;
    var row: usize = oy + 2;
    const stages = [_]perf.Stage{ .units, .wildlife, .training };
    for (stages) |s| {
        const sl = perf.stageLabel[@intFromEnum(s)];
        canvas.writeStr(@intCast(ox + 2), @intCast(row), sl, label);
        const avg = state.perf.avgTick(s);
        const mx = state.perf.maxTick(s);
        var pos: usize = 0;
        pos += fmt.formatUint(us_buf[pos..], avg / 1000);
        us_buf[pos] = 'u'; pos += 1;
        us_buf[pos] = 's'; pos += 1;
        canvas.writeStr(@intCast(ox + 12), @intCast(row), us_buf[0..pos], val);
        pos = 0;
        us_buf[pos] = 'm'; pos += 1;
        us_buf[pos] = 'x'; pos += 1;
        pos += fmt.formatUint(us_buf[pos..], mx / 1000);
        us_buf[pos] = 'u'; pos += 1;
        us_buf[pos] = 's'; pos += 1;
        canvas.writeStr(@intCast(ox + 20), @intCast(row), us_buf[0..pos], dim);
        row += 1;
    }

    canvas.writeStr(@intCast(ox + 2), @intCast(row), "render", label);
    var pos: usize = 0;
    pos += fmt.formatUint(us_buf[pos..], state.perf.avgRender() / 1000);
    us_buf[pos] = 'u'; pos += 1;
    us_buf[pos] = 's'; pos += 1;
    canvas.writeStr(@intCast(ox + 12), @intCast(row), us_buf[0..pos], val);
    pos = 0;
    us_buf[pos] = 'm'; pos += 1;
    us_buf[pos] = 'x'; pos += 1;
    pos += fmt.formatUint(us_buf[pos..], state.perf.maxRender() / 1000);
    us_buf[pos] = 'u'; pos += 1;
    us_buf[pos] = 's'; pos += 1;
    canvas.writeStr(@intCast(ox + 20), @intCast(row), us_buf[0..pos], dim);
    row += 1;

    canvas.writeStr(@intCast(ox + 2), @intCast(row), "pf/tick", label);
    pos = fmt.formatUint(us_buf[0..], state.perf.avgPathfind());
    canvas.writeStr(@intCast(ox + 12), @intCast(row), us_buf[0..pos], val);
    canvas.writeStr(@intCast(ox + 20), @intCast(row), "` off", dim);
}
