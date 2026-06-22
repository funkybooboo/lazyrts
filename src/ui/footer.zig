const terminal = @import("../lib/terminal.zig");
const state_mod = @import("../game/state.zig");
const coords = @import("../lib/coords.zig");
const lib_spatial = @import("../lib/spatial.zig");
const queries = @import("../game/queries.zig");
const unit = @import("../units/unit.zig");
const building = @import("../buildings/building.zig");
const config = @import("../config.zig");
const fmt = @import("../lib/fmt.zig");

pub fn draw(canvas: terminal.Canvas, state: *const state_mod.State) void {
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
        canvas.writeCell(@intCast(x), y0, "-", border);
        canvas.writeCell(@intCast(x), y0 + cfg.ui.drawer_height - 1, "-", border);
    }

    const row1: u16 = y0 + 1;
    const row2: u16 = y0 + 2;
    const row3: u16 = y0 + 3;

    var x: u16 = 1;

    x = put(canvas, x, row1, cfg.ui_text.tile_label, label);
    x = put(canvas, x, row1, state.world.at(state.cursor_x, state.cursor_y).label(cfg), val);

    var col_buf: [3]u8 = undefined;
    const col_str = coords.colToLetters(state.cursor_x, &col_buf);
    x = put(canvas, x, row1, " ", label);
    x = put(canvas, x, row1, col_str, val);
    var row_num_buf: [8]u8 = undefined;
    const rn_len = fmt.formatUint(row_num_buf[0..], state.cursor_y + 1);
    x = put(canvas, x, row1, row_num_buf[0..rn_len], val);

    x = put(canvas, x, row1, "  Food:", label);
    var food_buf: [8]u8 = undefined;
    const flen = fmt.formatUint(food_buf[0..], state.food);
    x = put(canvas, x, row1, food_buf[0..flen], yellow);
    x = put(canvas, x, row1, " Wood:", label);
    var wood_buf: [8]u8 = undefined;
    const wlen = fmt.formatUint(wood_buf[0..], state.wood);
    x = put(canvas, x, row1, wood_buf[0..wlen], brown);

    x = 1;

    if (state.selected_count > 0) {
        const si = state.selected[0];
        if (si < state.unit_count) {
            const u = &state.units[si];
            x = put(canvas, x, row2, cfg.ui_text.sel_label, label);
            x = put(canvas, x, row2, kindLabel(u.kind(), cfg), val);
            x = put(canvas, x, row2, " ", label);
            x = put(canvas, x, row2, ownerLabel(u.owner), ownerStyle(u.owner, cyan, red, brown));
            var hp_buf1: [12]u8 = undefined;
            x = put(canvas, x, row2, cfg.ui_text.hp_label, label);
            x = put(canvas, x, row2, fmtHp(&hp_buf1, u.hp, u.maxHp(state.cfg)), val);
            x = put(canvas, x, row2, " ", label);
            x = put(canvas, x, row2, stateLabel(u.state), val);
            if (state.selected_count > 1) {
                var gbuf: [8]u8 = undefined;
                const glen = fmt.formatUint(gbuf[0..], state.selected_count);
                x = put(canvas, x, row2, " x", label);
                x = put(canvas, x, row2, gbuf[0..glen], cyan);
            }
        }
    } else if (state.selected_building) |bi| {
        if (bi < state.building_count) {
            const b = &state.buildings[bi];
            x = put(canvas, x, row2, cfg.ui_text.sel_label, label);
            x = put(canvas, x, row2, b.label(cfg), val);
            x = put(canvas, x, row2, " ", label);
            x = put(canvas, x, row2, ownerLabel(b.owner), ownerStyle(b.owner, cyan, red, brown));
            var hp_buf3: [12]u8 = undefined;
            x = put(canvas, x, row2, cfg.ui_text.hp_label, label);
            x = put(canvas, x, row2, fmtHp(&hp_buf3, b.hp, b.maxHp(state.cfg)), val);
            if (b.isDropoff()) x = put(canvas, x, row2, " dropoff", cyan);
            if (b.popHousing(cfg) > 0) {
                var pbuf: [4]u8 = undefined;
                const plen = fmt.formatUint(pbuf[0..], b.popHousing(cfg));
                x = put(canvas, x, row2, " Pop+", label);
                x = put(canvas, x, row2, pbuf[0..plen], cyan);
            }
            if (b.kind() == .farm) {
                const f = &b.variant.farm;
                var fbuf: [8]u8 = undefined;
                const fblen = fmt.formatUint(fbuf[0..], f.food_remaining);
                x = put(canvas, x, row2, " Food:", label);
                x = put(canvas, x, row2, fbuf[0..fblen], yellow);
                if (f.fallow) {
                    x = put(canvas, x, row2, " fallow", red);
                    if (state.wood >= cfg.economy.resow_wood_cost) {
                        x = put(canvas, x, row2, " (R)", dim);
                    }
                }
                if (f.assigned_worker) |_| {
                    x = put(canvas, x, row2, " worker", cyan);
                } else if (!f.fallow and f.food_remaining > 0) {
                    x = put(canvas, x, row2, " free", dim);
                }
            }
            if (b.build_progress < building.BUILD_COMPLETE_PERCENT) {
                x = put(canvas, x, row2, cfg.ui_text.build_label, label);
                var bp_buf: [4]u8 = undefined;
                const bp_len = fmt.formatUint(bp_buf[0..], b.build_progress);
                x = put(canvas, x, row2, bp_buf[0..bp_len], val);
                x = put(canvas, x, row2, "%", val);
            } else {
                x = put(canvas, x, row2, " done", dim);
            }
            x = put(canvas, x, row2, " @", label);
            var cbuf: [3]u8 = undefined;
            const cstr = coords.colToLetters(b.x, &cbuf);
            x = put(canvas, x, row2, cstr, val);
            var rbuf: [8]u8 = undefined;
            const rlen = fmt.formatUint(rbuf[0..], b.y + 1);
            x = put(canvas, x, row2, rbuf[0..rlen], val);
        }
    } else if (lib_spatial.indexOfAt((state.spatialCtx()).units, state.cursor_x, state.cursor_y)) |ui| {
        const u = &state.units[ui];
        x = put(canvas, x, row2, kindLabel(u.kind(), cfg), val);
        x = put(canvas, x, row2, " ", label);
        x = put(canvas, x, row2, ownerLabel(u.owner), ownerStyle(u.owner, cyan, red, brown));
        var hp_buf2: [12]u8 = undefined;
        x = put(canvas, x, row2, cfg.ui_text.hp_label, label);
        x = put(canvas, x, row2, fmtHp(&hp_buf2, u.hp, u.maxHp(state.cfg)), val);
    } else if (lib_spatial.indexOfAt((state.spatialCtx()).buildings, state.cursor_x, state.cursor_y)) |bi| {
        const b = &state.buildings[bi];
        x = put(canvas, x, row2, b.label(cfg), val);
        x = put(canvas, x, row2, " ", label);
        x = put(canvas, x, row2, ownerLabel(b.owner), ownerStyle(b.owner, cyan, red, brown));
        var hp_buf3: [12]u8 = undefined;
        x = put(canvas, x, row2, cfg.ui_text.hp_label, label);
        x = put(canvas, x, row2, fmtHp(&hp_buf3, b.hp, b.maxHp(state.cfg)), val);
        if (b.build_progress < building.BUILD_COMPLETE_PERCENT) {
            x = put(canvas, x, row2, cfg.ui_text.build_label, label);
            var bp_buf: [4]u8 = undefined;
            const bp_len = fmt.formatUint(bp_buf[0..], b.build_progress);
            x = put(canvas, x, row2, bp_buf[0..bp_len], val);
            x = put(canvas, x, row2, "%", val);
        }
    }

    var rx: u16 = w -| cfg.ui.right_panel_offset;
    const secs = state_mod.elapsedSeconds(state);
    var time_buf: [8]u8 = undefined;
    const time_str = fmt.formatElapsed(secs, &time_buf, cfg.ui.seconds_per_minute);
    rx = put(canvas, rx, row1, time_str, yellow);

    const pop = state_mod.playerPop(state);
    const cap = state_mod.playerPopCap(state);
    const counts = state_mod.playerUnitCounts(state);
    rx = w -| cfg.ui.right_panel_offset;
    rx = put(canvas, rx, row2, cfg.ui_text.pop_label, label);
    var pop_buf: [12]u8 = undefined;
    var pp: usize = 0;
    pp += fmt.formatUint(pop_buf[pp..], pop);
    pop_buf[pp] = '/';
    pp += 1;
    pp += fmt.formatUint(pop_buf[pp..], cap);
    rx = put(canvas, rx, row2, pop_buf[0..pp], if (pop >= cap) red else val);

    rx = put(canvas, rx, row2, cfg.ui_text.w_label, label);
    var w_buf: [4]u8 = undefined;
    const wl = fmt.formatUint(w_buf[0..], counts.workers);
    rx = put(canvas, rx, row2, w_buf[0..wl], cyan);

    rx = put(canvas, rx, row2, cfg.ui_text.s_label, label);
    var s_buf: [4]u8 = undefined;
    const sl = fmt.formatUint(s_buf[0..], counts.soldiers);
    rx = put(canvas, rx, row2, s_buf[0..sl], red);

    if (state.coord_mode) {
        canvas.writeStr(1, row3, cfg.ui_text.coord_help, dim);
        if (state.coord_len > 0) {
            canvas.writeStr(cfg.ui.coord_input_offset, row3, state.coord_buf[0..state.coord_len], yellow);
        }
    } else if (state.help_mode) {
        canvas.writeStr(1, row3, "?=close", dim);
    } else {
        canvas.writeStr(1, row3, "?=help", dim);
    }
}

fn put(canvas: terminal.Canvas, x: u16, y: u16, text: []const u8, s: terminal.Style) u16 {
    canvas.writeStr(x, y, text, s);
    return x + @as(u16, @intCast(text.len));
}

fn ownerStyle(o: unit.Owner, player: terminal.Style, enemy: terminal.Style, neutral: terminal.Style) terminal.Style {
    return switch (o) {
        .player => player,
        .enemy => enemy,
        .neutral => neutral,
    };
}

fn stateLabel(s: unit.UnitActivity) []const u8 {
    return switch (s) {
        .idle => "idle",
        .moving => "moving",
        .gathering_wood => "chop",
        .gathering_food => "farm",
        .hunting => "hunt",
        .constructing => "build",
    };
}

fn fmtHp(buf: []u8, hp: usize, maxHp: usize) []const u8 {
    var pos: usize = 0;
    pos += fmt.formatUint(buf[pos..], hp);
    buf[pos] = '/';
    pos += 1;
    pos += fmt.formatUint(buf[pos..], maxHp);
    return buf[0..pos];
}

fn kindLabel(k: unit.UnitKind, cfg: *const config.Config) []const u8 {
    return switch (k) {
        .worker => cfg.labels.worker,
        .soldier => cfg.labels.soldier,
    };
}

fn ownerLabel(o: unit.Owner) []const u8 {
    return switch (o) {
        .player => "Player",
        .enemy => "Enemy",
        .neutral => "Neutral",
    };
}
