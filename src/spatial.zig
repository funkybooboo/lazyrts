const unit = @import("unit.zig");

pub const State = @import("game.zig").State;

pub fn unit_at(s: *const State, x: usize, y: usize) ?usize {
    for (0..s.unit_count) |i| {
        if (s.units[i].x == x and s.units[i].y == y) return i;
    }
    return null;
}

pub fn building_at(s: *const State, x: usize, y: usize) ?usize {
    for (0..s.building_count) |i| {
        if (s.buildings[i].x == x and s.buildings[i].y == y) return i;
    }
    return null;
}

pub fn nature_at(s: *const State, x: usize, y: usize) ?usize {
    for (0..s.nature_count) |i| {
        if (s.nature[i].x == x and s.nature[i].y == y) return i;
    }
    return null;
}

pub fn nature_at_except(s: *const State, x: usize, y: usize, except_idx: usize) ?usize {
    for (0..s.nature_count) |i| {
        if (i == except_idx) continue;
        if (s.nature[i].x == x and s.nature[i].y == y) return i;
    }
    return null;
}

pub fn occupied(s: *const State, x: usize, y: usize) bool {
    return unit_at(s, x, y) != null or building_at(s, x, y) != null or nature_at(s, x, y) != null;
}

pub fn collect_blocked(s: *const State, out: []unit.Pos, except_unit: ?usize) usize {
    var count: usize = 0;

    for (0..s.building_count) |i| {
        if (count >= out.len) break;
        out[count] = .{ .x = s.buildings[i].x, .y = s.buildings[i].y };
        count += 1;
    }

    for (0..s.nature_count) |i| {
        if (count >= out.len) break;
        out[count] = .{ .x = s.nature[i].x, .y = s.nature[i].y };
        count += 1;
    }

    for (0..s.unit_count) |i| {
        if (except_unit) |ex| if (i == ex) continue;
        if (count >= out.len) break;
        out[count] = .{ .x = s.units[i].x, .y = s.units[i].y };
        count += 1;
    }

    return count;
}
