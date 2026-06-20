const std = @import("std");
const unit = @import("unit.zig");
const building = @import("building.zig");
const nature = @import("nature.zig");

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

test "unit_at finds unit at position" {
    const allocator = std.testing.allocator;
    var units = [_]unit.Unit{
        .{ .x = 5, .y = 10, .kind = .worker, .owner = .player, .hp = 100, .state = .idle, .path = &[_]unit.Pos{}, .path_len = 0, .path_idx = 0 },
        .{ .x = 15, .y = 20, .kind = .worker, .owner = .player, .hp = 100, .state = .idle, .path = &[_]unit.Pos{}, .path_len = 0, .path_idx = 0 },
    };
    var s: State = .{
        .allocator = allocator,
        .world = undefined,
        .units = &units,
        .unit_count = 2,
        .buildings = &[_]building.Building{},
        .building_count = 0,
        .nature = &[_]nature.Nature{},
        .nature_count = 0,
        .cfg = undefined,
    };
    try std.testing.expectEqual(@as(?usize, 0), unit_at(&s, 5, 10));
    try std.testing.expectEqual(@as(?usize, 1), unit_at(&s, 15, 20));
    try std.testing.expect(unit_at(&s, 0, 0) == null);
}

test "building_at finds building at position" {
    const allocator = std.testing.allocator;
    var buildings = [_]building.Building{
        .{ .x = 10, .y = 10, .kind = .town_center, .owner = .player, .hp = 1000, .build_progress = 100 },
        .{ .x = 50, .y = 50, .kind = .house, .owner = .player, .hp = 100, .build_progress = 100 },
    };
    var s: State = .{
        .allocator = allocator,
        .world = undefined,
        .units = &[_]unit.Unit{},
        .unit_count = 0,
        .buildings = &buildings,
        .building_count = 2,
        .nature = &[_]nature.Nature{},
        .nature_count = 0,
        .cfg = undefined,
    };
    try std.testing.expectEqual(@as(?usize, 0), building_at(&s, 10, 10));
    try std.testing.expectEqual(@as(?usize, 1), building_at(&s, 50, 50));
    try std.testing.expect(building_at(&s, 0, 0) == null);
}

test "nature_at finds nature at position" {
    const allocator = std.testing.allocator;
    var nature_arr = [_]nature.Nature{
        .{ .x = 3, .y = 7, .kind = .deer, .hp = 50 },
        .{ .x = 25, .y = 30, .kind = .deer, .hp = 50 },
    };
    var s: State = .{
        .allocator = allocator,
        .world = undefined,
        .units = &[_]unit.Unit{},
        .unit_count = 0,
        .buildings = &[_]building.Building{},
        .building_count = 0,
        .nature = &nature_arr,
        .nature_count = 2,
        .cfg = undefined,
    };
    try std.testing.expectEqual(@as(?usize, 0), nature_at(&s, 3, 7));
    try std.testing.expectEqual(@as(?usize, 1), nature_at(&s, 25, 30));
    try std.testing.expect(nature_at(&s, 0, 0) == null);
}

test "nature_at_except skips specified index" {
    const allocator = std.testing.allocator;
    var nature_arr = [_]nature.Nature{
        .{ .x = 5, .y = 5, .kind = .deer, .hp = 50 },
        .{ .x = 5, .y = 5, .kind = .deer, .hp = 50 },
    };
    var s: State = .{
        .allocator = allocator,
        .world = undefined,
        .units = &[_]unit.Unit{},
        .unit_count = 0,
        .buildings = &[_]building.Building{},
        .building_count = 0,
        .nature = &nature_arr,
        .nature_count = 2,
        .cfg = undefined,
    };
    try std.testing.expectEqual(@as(?usize, 0), nature_at(&s, 5, 5));
    try std.testing.expectEqual(@as(?usize, 1), nature_at_except(&s, 5, 5, 0));
    try std.testing.expectEqual(@as(?usize, 0), nature_at_except(&s, 5, 5, 1));
}

test "occupied returns true when entity present" {
    const allocator = std.testing.allocator;
    var units = [_]unit.Unit{
        .{ .x = 10, .y = 10, .kind = .worker, .owner = .player, .hp = 100, .state = .idle, .path = &[_]unit.Pos{}, .path_len = 0, .path_idx = 0 },
    };
    var buildings = [_]building.Building{
        .{ .x = 20, .y = 20, .kind = .house, .owner = .player, .hp = 100, .build_progress = 100 },
    };
    var nature_arr = [_]nature.Nature{
        .{ .x = 30, .y = 30, .kind = .deer, .hp = 50 },
    };
    var s: State = .{
        .allocator = allocator,
        .world = undefined,
        .units = &units,
        .unit_count = 1,
        .buildings = &buildings,
        .building_count = 1,
        .nature = &nature_arr,
        .nature_count = 1,
        .cfg = undefined,
    };
    try std.testing.expect(occupied(&s, 10, 10));
    try std.testing.expect(occupied(&s, 20, 20));
    try std.testing.expect(occupied(&s, 30, 30));
    try std.testing.expect(!occupied(&s, 0, 0));
}

test "collect_blocked includes all entities except specified unit" {
    const allocator = std.testing.allocator;
    var units = [_]unit.Unit{
        .{ .x = 5, .y = 5, .kind = .worker, .owner = .player, .hp = 100, .state = .idle, .path = &[_]unit.Pos{}, .path_len = 0, .path_idx = 0 },
        .{ .x = 10, .y = 10, .kind = .worker, .owner = .player, .hp = 100, .state = .idle, .path = &[_]unit.Pos{}, .path_len = 0, .path_idx = 0 },
    };
    var buildings = [_]building.Building{
        .{ .x = 15, .y = 15, .kind = .house, .owner = .player, .hp = 100, .build_progress = 100 },
    };
    var nature_arr = [_]nature.Nature{
        .{ .x = 20, .y = 20, .kind = .deer, .hp = 50 },
    };
    var s: State = .{
        .allocator = allocator,
        .world = undefined,
        .units = &units,
        .unit_count = 2,
        .buildings = &buildings,
        .building_count = 1,
        .nature = &nature_arr,
        .nature_count = 1,
        .cfg = undefined,
    };
    var out: [10]unit.Pos = undefined;
    const count = collect_blocked(&s, &out, 0);
    try std.testing.expectEqual(@as(usize, 3), count);
    
    const count_all = collect_blocked(&s, &out, null);
    try std.testing.expectEqual(@as(usize, 4), count_all);
}
