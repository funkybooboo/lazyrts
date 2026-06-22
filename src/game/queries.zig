const std = @import("std");
const unit = @import("../units/unit.zig");
const coords = @import("../lib/coords.zig");
const lib_spatial = @import("../lib/spatial.zig");
const building = @import("../buildings/building.zig");
const wildlife = @import("../resources/wildlife.zig");

pub const Ctx = struct {
    units: []const unit.Unit,
    buildings: []const building.Building,
    wildlife: []const wildlife.Wildlife,
};

pub fn occupied(ctx: Ctx, x: usize, y: usize) bool {
    return lib_spatial.indexOfAt(ctx.units, x, y) != null or
        lib_spatial.indexOfAt(ctx.buildings, x, y) != null or
        lib_spatial.indexOfAt(ctx.wildlife, x, y) != null;
}

pub fn collectBlocked(ctx: Ctx, out: []coords.Pos, except_unit: ?usize) usize {
    var count: usize = 0;

    count += lib_spatial.collectPositions(ctx.buildings, out[count..]);
    count += lib_spatial.collectPositions(ctx.wildlife, out[count..]);

    for (ctx.units, 0..) |u, i| {
        if (except_unit) |ex| if (i == ex) continue;
        if (count >= out.len) break;
        out[count] = .{ .x = u.x, .y = u.y };
        count += 1;
    }

    return count;
}

test "unitAt finds unit at position" {
    var units = [_]unit.Unit{
        .{ .x = 5, .y = 10, .variant = .worker, .owner = .player, .hp = 100, .state = .idle, .path = &[_]coords.Pos{}, .path_len = 0, .path_idx = 0 },
        .{ .x = 15, .y = 20, .variant = .worker, .owner = .player, .hp = 100, .state = .idle, .path = &[_]coords.Pos{}, .path_len = 0, .path_idx = 0 },
    };
    const ctx: Ctx = .{
        .units = &units,
        .buildings = &[_]building.Building{},
        .wildlife = &[_]wildlife.Wildlife{},
    };
    try std.testing.expectEqual(@as(?usize, 0), lib_spatial.indexOfAt(ctx.units, 5, 10));
    try std.testing.expectEqual(@as(?usize, 1), lib_spatial.indexOfAt(ctx.units, 15, 20));
    try std.testing.expect(lib_spatial.indexOfAt(ctx.units, 0, 0) == null);
}

test "buildingAt finds building at position" {
    var buildings = [_]building.Building{
        .{ .x = 10, .y = 10, .variant = .town_center, .owner = .player, .hp = 1000, .build_progress = 100 },
        .{ .x = 50, .y = 50, .variant = .house, .owner = .player, .hp = 100, .build_progress = 100 },
    };
    const ctx: Ctx = .{
        .units = &[_]unit.Unit{},
        .buildings = &buildings,
        .wildlife = &[_]wildlife.Wildlife{},
    };
    try std.testing.expectEqual(@as(?usize, 0), lib_spatial.indexOfAt(ctx.buildings, 10, 10));
    try std.testing.expectEqual(@as(?usize, 1), lib_spatial.indexOfAt(ctx.buildings, 50, 50));
    try std.testing.expect(lib_spatial.indexOfAt(ctx.buildings, 0, 0) == null);
}

test "wildlifeAt finds wildlife at position" {
    var wildlife_arr = [_]wildlife.Wildlife{
        .{ .deer = .{ .x = 3, .y = 7, .hp = 50 } },
        .{ .deer = .{ .x = 25, .y = 30, .hp = 50 } },
    };
    const ctx: Ctx = .{
        .units = &[_]unit.Unit{},
        .buildings = &[_]building.Building{},
        .wildlife = &wildlife_arr,
    };
    try std.testing.expectEqual(@as(?usize, 0), lib_spatial.indexOfAt(ctx.wildlife, 3, 7));
    try std.testing.expectEqual(@as(?usize, 1), lib_spatial.indexOfAt(ctx.wildlife, 25, 30));
    try std.testing.expect(lib_spatial.indexOfAt(ctx.wildlife, 0, 0) == null);
}

test "wildlifeAtExcept skips specified index" {
    var wildlife_arr = [_]wildlife.Wildlife{
        .{ .deer = .{ .x = 5, .y = 5, .hp = 50 } },
        .{ .deer = .{ .x = 5, .y = 5, .hp = 50 } },
    };
    const ctx: Ctx = .{
        .units = &[_]unit.Unit{},
        .buildings = &[_]building.Building{},
        .wildlife = &wildlife_arr,
    };
    try std.testing.expectEqual(@as(?usize, 0), lib_spatial.indexOfAt(ctx.wildlife, 5, 5));
    try std.testing.expectEqual(@as(?usize, 1), lib_spatial.indexOfAtExcept(ctx.wildlife, 5, 5, 0));
    try std.testing.expectEqual(@as(?usize, 0), lib_spatial.indexOfAtExcept(ctx.wildlife, 5, 5, 1));
}

test "occupied returns true when entity present" {
    var units = [_]unit.Unit{
        .{ .x = 10, .y = 10, .variant = .worker, .owner = .player, .hp = 100, .state = .idle, .path = &[_]coords.Pos{}, .path_len = 0, .path_idx = 0 },
    };
    var buildings = [_]building.Building{
        .{ .x = 20, .y = 20, .variant = .house, .owner = .player, .hp = 100, .build_progress = 100 },
    };
    var wildlife_arr = [_]wildlife.Wildlife{
        .{ .deer = .{ .x = 30, .y = 30, .hp = 50 } },
    };
    const ctx: Ctx = .{
        .units = &units,
        .buildings = &buildings,
        .wildlife = &wildlife_arr,
    };
    try std.testing.expect(occupied(ctx, 10, 10));
    try std.testing.expect(occupied(ctx, 20, 20));
    try std.testing.expect(occupied(ctx, 30, 30));
    try std.testing.expect(!occupied(ctx, 0, 0));
}

test "collectBlocked includes all entities except specified unit" {
    var units = [_]unit.Unit{
        .{ .x = 5, .y = 5, .variant = .worker, .owner = .player, .hp = 100, .state = .idle, .path = &[_]coords.Pos{}, .path_len = 0, .path_idx = 0 },
        .{ .x = 10, .y = 10, .variant = .worker, .owner = .player, .hp = 100, .state = .idle, .path = &[_]coords.Pos{}, .path_len = 0, .path_idx = 0 },
    };
    var buildings = [_]building.Building{
        .{ .x = 15, .y = 15, .variant = .house, .owner = .player, .hp = 100, .build_progress = 100 },
    };
    var wildlife_arr = [_]wildlife.Wildlife{
        .{ .deer = .{ .x = 20, .y = 20, .hp = 50 } },
    };
    const ctx: Ctx = .{
        .units = &units,
        .buildings = &buildings,
        .wildlife = &wildlife_arr,
    };
    var out: [10]coords.Pos = undefined;
    const count = collectBlocked(ctx, &out, 0);
    try std.testing.expectEqual(@as(usize, 3), count);

    const count_all = collectBlocked(ctx, &out, null);
    try std.testing.expectEqual(@as(usize, 4), count_all);
}
