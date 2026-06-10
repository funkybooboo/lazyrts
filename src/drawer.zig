const term = @import("terminal.zig");
const game = @import("game.zig");
const entity = @import("entity.zig");

pub fn draw(canvas: term.Canvas, state: *const game.State) void {
    const y0: u16 = canvas.height() - game.DRAWER_HEIGHT;
    const w = canvas.width();
    if (w < 10) return;

    const border: term.Style = .{ .fg = .{ .rgb = .{ 80, 80, 80 } } };
    const label: term.Style = .{ .fg = .{ .rgb = .{ 120, 120, 120 } } };
    const val: term.Style = .{ .fg = .{ .rgb = .{ 220, 220, 220 } } };
    const cyan: term.Style = .{ .fg = .{ .rgb = .{ 0, 200, 200 } } };
    const red: term.Style = .{ .fg = .{ .rgb = .{ 210, 80, 80 } } };
    const brown: term.Style = .{ .fg = .{ .rgb = .{ 170, 130, 60 } } };
    const dim: term.Style = .{ .fg = .{ .rgb = .{ 100, 100, 80 } } };
    const yellow: term.Style = .{ .fg = .{ .rgb = .{ 255, 255, 100 } } };

    for (0..w) |x| {
        canvas.write_cell(@intCast(x), y0, "-", border);
        canvas.write_cell(@intCast(x), y0 + game.DRAWER_HEIGHT - 1, "-", border);
    }

    const row1: u16 = y0 + 1;
    const row2: u16 = y0 + 2;
    const row3: u16 = y0 + 3;

    var x: u16 = 1;

    x = put(canvas, x, row1, "Tile:", label);
    x = put(canvas, x, row1, state.world.at(state.cursor_x, state.cursor_y).label(), val);

    var col_buf: [3]u8 = undefined;
    const col_str = game.col_to_letters(state.cursor_x, &col_buf);
    x = put(canvas, x, row1, " ", label);
    x = put(canvas, x, row1, col_str, val);
    var row_num_buf: [8]u8 = undefined;
    const rn_len = fmt_u64(row_num_buf[0..], state.cursor_y + 1);
    x = put(canvas, x, row1, row_num_buf[0..rn_len], val);

    x = 1;

    if (state.selected_unit) |si| {
        if (si < state.unit_count) {
            const u = &state.units[si];
            x = put(canvas, x, row2, "Sel:", label);
            x = put(canvas, x, row2, kind_label(u.kind), val);
            x = put(canvas, x, row2, " ", label);
            x = put(canvas, x, row2, owner_label(u.owner), owner_style(u.owner, cyan, red, brown));
            var hp_buf1: [12]u8 = undefined;
            x = put(canvas, x, row2, " HP:", label);
            x = put(canvas, x, row2, fmt_hp(&hp_buf1, u.hp, u.kind.max_hp()), val);
            x = put(canvas, x, row2, " ", label);
            x = put(canvas, x, row2, state_label(u.state), val);
        }
    } else if (game.unit_at(state, state.cursor_x, state.cursor_y)) |ui| {
        const u = &state.units[ui];
        x = put(canvas, x, row2, kind_label(u.kind), val);
        x = put(canvas, x, row2, " ", label);
        x = put(canvas, x, row2, owner_label(u.owner), owner_style(u.owner, cyan, red, brown));
        var hp_buf2: [12]u8 = undefined;
        x = put(canvas, x, row2, " HP:", label);
        x = put(canvas, x, row2, fmt_hp(&hp_buf2, u.hp, u.kind.max_hp()), val);
    } else if (game.building_at(state, state.cursor_x, state.cursor_y)) |bi| {
        const b = &state.buildings[bi];
        x = put(canvas, x, row2, b.kind.label(), val);
        x = put(canvas, x, row2, " ", label);
        x = put(canvas, x, row2, owner_label(b.owner), owner_style(b.owner, cyan, red, brown));
        var hp_buf3: [12]u8 = undefined;
        x = put(canvas, x, row2, " HP:", label);
        x = put(canvas, x, row2, fmt_hp(&hp_buf3, b.hp, b.kind.max_hp()), val);
        if (b.build_progress < 100) {
            x = put(canvas, x, row2, " Build:", label);
            var bp_buf: [4]u8 = undefined;
            const bp_len = fmt_u64(bp_buf[0..], b.build_progress);
            x = put(canvas, x, row2, bp_buf[0..bp_len], val);
            x = put(canvas, x, row2, "%", val);
        }
    }

    var rx: u16 = w -| 20;
    const secs = game.elapsed_seconds(state);
    const mins = secs / 60;
    const secs_rem = secs % 60;
    var time_buf: [8]u8 = undefined;
    var tp: usize = 0;
    if (mins < 10) {
        time_buf[tp] = '0';
        tp += 1;
    }
    tp += fmt_u64(time_buf[tp..], mins);
    time_buf[tp] = ':';
    tp += 1;
    if (secs_rem < 10) {
        time_buf[tp] = '0';
        tp += 1;
    }
    tp += fmt_u64(time_buf[tp..], secs_rem);
    rx = put(canvas, rx, row1, time_buf[0..tp], yellow);

    const pop = game.player_pop(state);
    const cap = game.player_pop_cap(state);
    const counts = game.player_unit_counts(state);
    rx = w -| 20;
    rx = put(canvas, rx, row2, "Pop:", label);
    var pop_buf: [12]u8 = undefined;
    var pp: usize = 0;
    pp += fmt_u64(pop_buf[pp..], pop);
    pop_buf[pp] = '/';
    pp += 1;
    pp += fmt_u64(pop_buf[pp..], cap);
    rx = put(canvas, rx, row2, pop_buf[0..pp], if (pop >= cap) red else val);

    rx = put(canvas, rx, row2, " W:", label);
    var w_buf: [4]u8 = undefined;
    const wl = fmt_u64(w_buf[0..], counts.workers);
    rx = put(canvas, rx, row2, w_buf[0..wl], cyan);

    rx = put(canvas, rx, row2, " S:", label);
    var s_buf: [4]u8 = undefined;
    const sl = fmt_u64(s_buf[0..], counts.soldiers);
    rx = put(canvas, rx, row2, s_buf[0..sl], red);

    if (state.coord_mode) {
        canvas.write_str(1, row3, "Enter=go Esc=cancel", dim);
        if (state.coord_len > 0) {
            canvas.write_str(22, row3, state.coord_buf[0..state.coord_len], yellow);
        }
    } else {
        canvas.write_str(1, row3, "hjkl=move T=spawn M=move Tab=select G=coord Q=quit", dim);
    }
}

fn put(canvas: term.Canvas, x: u16, y: u16, text: []const u8, s: term.Style) u16 {
    canvas.write_str(x, y, text, s);
    return x + @as(u16, @intCast(text.len));
}

fn owner_style(o: entity.Owner, player: term.Style, enemy: term.Style, neutral: term.Style) term.Style {
    return switch (o) {
        .player => player,
        .enemy => enemy,
        .neutral => neutral,
    };
}

fn state_label(s: entity.UnitState) []const u8 {
    return switch (s) {
        .idle => "idle",
        .moving => "moving",
    };
}

fn fmt_hp(buf: []u8, hp: usize, max_hp: usize) []const u8 {
    var pos: usize = 0;
    pos += fmt_u64(buf[pos..], hp);
    buf[pos] = '/';
    pos += 1;
    pos += fmt_u64(buf[pos..], max_hp);
    return buf[0..pos];
}

fn fmt_u64(buf: []u8, val: u64) usize {
    if (val == 0) {
        if (buf.len > 0) buf[0] = '0';
        return 1;
    }
    var tmp: [20]u8 = undefined;
    var n = val;
    var i: usize = 0;
    while (n > 0) {
        tmp[i] = '0' + @as(u8, @intCast(n % 10));
        n /= 10;
        i += 1;
    }
    var j: usize = 0;
    while (i > 0) {
        i -= 1;
        if (j < buf.len) buf[j] = tmp[i];
        j += 1;
    }
    return j;
}

fn kind_label(k: entity.UnitKind) []const u8 {
    return switch (k) {
        .worker => "Worker",
        .soldier => "Soldier",
        .deer => "Deer",
    };
}

fn owner_label(o: entity.Owner) []const u8 {
    return switch (o) {
        .player => "Player",
        .enemy => "Enemy",
        .neutral => "Neutral",
    };
}
