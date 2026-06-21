const terminal = @import("terminal.zig");
const game = @import("game.zig");
const coord = @import("coord.zig");
const spatial = @import("spatial.zig");
const unit = @import("unit.zig");
const building = @import("building.zig");
const config = @import("config.zig");
const time = @import("time.zig");
const fmt = @import("fmt.zig");

pub fn draw(canvas: terminal.Canvas, state: *const game.State) void {
    const cfg = state.cfg;
    const y0: u16 = canvas.height() - cfg.ui.drawer_height;
    const w = canvas.width();
    if (w < cfg.ui.min_drawer_width) return;

    const border: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.drawer_border } };
    const label: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.drawer_label } };
    const val: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.drawer_val } };
    const cyan: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.drawer_cyan } };
    const red: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.drawer_red } };
    const brown: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.drawer_brown } };
    const dim: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.drawer_dim } };
    const yellow: terminal.Style = .{ .fg = .{ .rgb = cfg.colors.drawer_yellow } };

    for (0..w) |x| {
        canvas.write_cell(@intCast(x), y0, "-", border);
        canvas.write_cell(@intCast(x), y0 + cfg.ui.drawer_height - 1, "-", border);
    }

    const row1: u16 = y0 + 1;
    const row2: u16 = y0 + 2;
    const row3: u16 = y0 + 3;

    var x: u16 = 1;

    x = put(canvas, x, row1, cfg.ui_text.tile_label, label);
    x = put(canvas, x, row1, state.world.at(state.cursor_x, state.cursor_y).label(cfg), val);

    var col_buf: [3]u8 = undefined;
    const col_str = coord.col_to_letters(state.cursor_x, &col_buf);
    x = put(canvas, x, row1, " ", label);
    x = put(canvas, x, row1, col_str, val);
    var row_num_buf: [8]u8 = undefined;
    const rn_len = fmt.format_uint(row_num_buf[0..], state.cursor_y + 1);
    x = put(canvas, x, row1, row_num_buf[0..rn_len], val);

    x = put(canvas, x, row1, "  Food:", label);
    var food_buf: [8]u8 = undefined;
    const flen = fmt.format_uint(food_buf[0..], state.food);
    x = put(canvas, x, row1, food_buf[0..flen], yellow);
    x = put(canvas, x, row1, " Wood:", label);
    var wood_buf: [8]u8 = undefined;
    const wlen = fmt.format_uint(wood_buf[0..], state.wood);
    x = put(canvas, x, row1, wood_buf[0..wlen], brown);

    x = 1;

    if (state.selected_count > 0) {
        const si = state.selected[0];
        if (si < state.unit_count) {
            const u = &state.units[si];
            x = put(canvas, x, row2, cfg.ui_text.sel_label, label);
            x = put(canvas, x, row2, kind_label(u.kind, cfg), val);
            x = put(canvas, x, row2, " ", label);
            x = put(canvas, x, row2, owner_label(u.owner), owner_style(u.owner, cyan, red, brown));
            var hp_buf1: [12]u8 = undefined;
            x = put(canvas, x, row2, cfg.ui_text.hp_label, label);
            x = put(canvas, x, row2, fmt_hp(&hp_buf1, u.hp, unit.max_hp(u.kind, state.cfg)), val);
            x = put(canvas, x, row2, " ", label);
            x = put(canvas, x, row2, state_label(u.state), val);
            if (state.selected_count > 1) {
                var gbuf: [8]u8 = undefined;
                const glen = fmt.format_uint(gbuf[0..], state.selected_count);
                x = put(canvas, x, row2, " x", label);
                x = put(canvas, x, row2, gbuf[0..glen], cyan);
            }
        }
    } else if (state.selected_building) |bi| {
        if (bi < state.building_count) {
            const b = &state.buildings[bi];
            x = put(canvas, x, row2, cfg.ui_text.sel_label, label);
            x = put(canvas, x, row2, b.kind.label(cfg), val);
            x = put(canvas, x, row2, " ", label);
            x = put(canvas, x, row2, owner_label(b.owner), owner_style(b.owner, cyan, red, brown));
            var hp_buf3: [12]u8 = undefined;
            x = put(canvas, x, row2, cfg.ui_text.hp_label, label);
            x = put(canvas, x, row2, fmt_hp(&hp_buf3, b.hp, building.max_hp(b.kind, state.cfg)), val);
            if (b.kind.is_depot()) x = put(canvas, x, row2, " depot", cyan);
            if (pop_contribution(b.kind, cfg) > 0) {
                var pbuf: [4]u8 = undefined;
                const plen = fmt.format_uint(pbuf[0..], pop_contribution(b.kind, cfg));
                x = put(canvas, x, row2, " Pop+", label);
                x = put(canvas, x, row2, pbuf[0..plen], cyan);
            }
            if (b.kind == .farm) {
                var fbuf: [8]u8 = undefined;
                const fblen = fmt.format_uint(fbuf[0..], b.food_remaining);
                x = put(canvas, x, row2, " Food:", label);
                x = put(canvas, x, row2, fbuf[0..fblen], yellow);
                if (b.fallow) {
                    x = put(canvas, x, row2, " fallow", red);
                    if (state.wood >= cfg.economy.resow_wood_cost) {
                        x = put(canvas, x, row2, " (R)", dim);
                    }
                }
                if (b.assigned_worker) |_| {
                    x = put(canvas, x, row2, " worker", cyan);
                } else if (!b.fallow and b.food_remaining > 0) {
                    x = put(canvas, x, row2, " free", dim);
                }
            }
            if (b.build_progress < building.BUILD_COMPLETE_PERCENT) {
                x = put(canvas, x, row2, cfg.ui_text.build_label, label);
                var bp_buf: [4]u8 = undefined;
                const bp_len = fmt.format_uint(bp_buf[0..], b.build_progress);
                x = put(canvas, x, row2, bp_buf[0..bp_len], val);
                x = put(canvas, x, row2, "%", val);
            } else {
                x = put(canvas, x, row2, " done", dim);
            }
            x = put(canvas, x, row2, " @", label);
            var cbuf: [3]u8 = undefined;
            const cstr = coord.col_to_letters(b.x, &cbuf);
            x = put(canvas, x, row2, cstr, val);
            var rbuf: [8]u8 = undefined;
            const rlen = fmt.format_uint(rbuf[0..], b.y + 1);
            x = put(canvas, x, row2, rbuf[0..rlen], val);
        }
    } else if (spatial.unit_at(state, state.cursor_x, state.cursor_y)) |ui| {
        const u = &state.units[ui];
        x = put(canvas, x, row2, kind_label(u.kind, cfg), val);
        x = put(canvas, x, row2, " ", label);
        x = put(canvas, x, row2, owner_label(u.owner), owner_style(u.owner, cyan, red, brown));
        var hp_buf2: [12]u8 = undefined;
        x = put(canvas, x, row2, cfg.ui_text.hp_label, label);
        x = put(canvas, x, row2, fmt_hp(&hp_buf2, u.hp, unit.max_hp(u.kind, state.cfg)), val);
    } else if (spatial.building_at(state, state.cursor_x, state.cursor_y)) |bi| {
        const b = &state.buildings[bi];
        x = put(canvas, x, row2, b.kind.label(cfg), val);
        x = put(canvas, x, row2, " ", label);
        x = put(canvas, x, row2, owner_label(b.owner), owner_style(b.owner, cyan, red, brown));
        var hp_buf3: [12]u8 = undefined;
        x = put(canvas, x, row2, cfg.ui_text.hp_label, label);
        x = put(canvas, x, row2, fmt_hp(&hp_buf3, b.hp, building.max_hp(b.kind, state.cfg)), val);
        if (b.build_progress < building.BUILD_COMPLETE_PERCENT) {
            x = put(canvas, x, row2, cfg.ui_text.build_label, label);
            var bp_buf: [4]u8 = undefined;
            const bp_len = fmt.format_uint(bp_buf[0..], b.build_progress);
            x = put(canvas, x, row2, bp_buf[0..bp_len], val);
            x = put(canvas, x, row2, "%", val);
        }
    }

    var rx: u16 = w -| cfg.ui.right_panel_offset;
    const secs = game.elapsed_seconds(state);
    var time_buf: [8]u8 = undefined;
    const time_str = time.format_elapsed(secs, &time_buf, cfg.ui.seconds_per_minute);
    rx = put(canvas, rx, row1, time_str, yellow);

    const pop = game.player_pop(state);
    const cap = game.player_pop_cap(state);
    const counts = game.player_unit_counts(state);
    rx = w -| cfg.ui.right_panel_offset;
    rx = put(canvas, rx, row2, cfg.ui_text.pop_label, label);
    var pop_buf: [12]u8 = undefined;
    var pp: usize = 0;
    pp += fmt.format_uint(pop_buf[pp..], pop);
    pop_buf[pp] = '/';
    pp += 1;
    pp += fmt.format_uint(pop_buf[pp..], cap);
    rx = put(canvas, rx, row2, pop_buf[0..pp], if (pop >= cap) red else val);

    rx = put(canvas, rx, row2, cfg.ui_text.w_label, label);
    var w_buf: [4]u8 = undefined;
    const wl = fmt.format_uint(w_buf[0..], counts.workers);
    rx = put(canvas, rx, row2, w_buf[0..wl], cyan);

    rx = put(canvas, rx, row2, cfg.ui_text.s_label, label);
    var s_buf: [4]u8 = undefined;
    const sl = fmt.format_uint(s_buf[0..], counts.soldiers);
    rx = put(canvas, rx, row2, s_buf[0..sl], red);

    if (state.coord_mode) {
        canvas.write_str(1, row3, cfg.ui_text.coord_help, dim);
        if (state.coord_len > 0) {
            canvas.write_str(cfg.ui.coord_input_offset, row3, state.coord_buf[0..state.coord_len], yellow);
        }
    } else if (state.gather_mode) {
        canvas.write_str(1, row3, cfg.ui_text.gather_help, dim);
    } else {
        canvas.write_str(1, row3, cfg.ui_text.main_help, dim);
    }
}

fn put(canvas: terminal.Canvas, x: u16, y: u16, text: []const u8, s: terminal.Style) u16 {
    canvas.write_str(x, y, text, s);
    return x + @as(u16, @intCast(text.len));
}

fn pop_contribution(k: building.BuildingKind, cfg: *const config.Config) usize {
    return switch (k) {
        .town_center, .house => cfg.pop_per_housing,
        else => 0,
    };
}

fn owner_style(o: unit.Owner, player: terminal.Style, enemy: terminal.Style, neutral: terminal.Style) terminal.Style {
    return switch (o) {
        .player => player,
        .enemy => enemy,
        .neutral => neutral,
    };
}

fn state_label(s: unit.UnitState) []const u8 {
    return switch (s) {
        .idle => "idle",
        .moving => "moving",
        .gathering_wood => "chop",
        .gathering_food => "farm",
        .hunting => "hunt",
        .constructing => "build",
    };
}

fn fmt_hp(buf: []u8, hp: usize, max_hp: usize) []const u8 {
    var pos: usize = 0;
    pos += fmt.format_uint(buf[pos..], hp);
    buf[pos] = '/';
    pos += 1;
    pos += fmt.format_uint(buf[pos..], max_hp);
    return buf[0..pos];
}

fn kind_label(k: unit.UnitKind, cfg: *const config.Config) []const u8 {
    return switch (k) {
        .worker => cfg.labels.worker,
        .soldier => cfg.labels.soldier,
    };
}

fn owner_label(o: unit.Owner) []const u8 {
    return switch (o) {
        .player => "Player",
        .enemy => "Enemy",
        .neutral => "Neutral",
    };
}
