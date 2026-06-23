const std = @import("std");
const config = @import("../config.zig");
const unit = @import("../units/unit.zig");
const coords = @import("../lib/coords.zig");
const lib_spatial = @import("../lib/spatial.zig");
const game_map = @import("../game/map.zig");
const queries = @import("../game/queries.zig");
const wildlife = @import("wildlife.zig");

pub const State = enum { idle, wandering };

pub const Deer = struct {
    x: usize,
    y: usize,
    hp: u16,
    state: State = .idle,
    food_remaining: u16 = 0,
    dead: bool = false,
    rot_accum_ms: u32 = 0,
    herd_cx: usize = 0,
    herd_cy: usize = 0,
    herd_radius: usize = 5,

    pub fn pos(self: *const Deer) coords.Pos {
        return .{ .x = self.x, .y = self.y };
    }
};

pub fn glyph(cfg: *const config.Config) []const u8 {
    return cfg.glyphs.deer;
}

pub fn maxHp(cfg: *const config.Config) u16 {
    return cfg.wildlife_hp.deer;
}

pub fn maxFood(cfg: *const config.Config) u16 {
    return cfg.economy.deer_total_yield;
}

pub fn wander(n: *Deer, m: *const game_map.GameMap, ctx: queries.Ctx, tick_count: usize, idx: usize, cfg: *const config.Config) void {
    if (n.dead) return;
    if (n.state != .idle) return;
    if (tick_count % cfg.deer.wander_interval != 0) return;

    var rng = std.Random.DefaultPrng.init(tick_count * cfg.deer.seed_mult_tick + idx * cfg.deer.seed_mult_idx + @as(u64, @intCast(n.x)));
    const should_wander = rng.random().intRangeAtMost(usize, 0, 2) == 0;
    if (!should_wander) return;

    const dirs = coords.dirs4;

    var valid_moves: [4]usize = undefined;
    var valid_count: usize = 0;

    for (dirs, 0..) |d, i| {
        const next_x = @as(isize, @intCast(n.x)) + d.dx;
        const next_y = @as(isize, @intCast(n.y)) + d.dy;
        if (next_x < 0 or next_y < 0) continue;
        const unit_x: usize = @intCast(next_x);
        const unit_y: usize = @intCast(next_y);
        if (unit_x < m.width and unit_y < m.height and m.isWalkable(unit_x, unit_y)) {
            if (lib_spatial.indexOfAt((ctx).units, unit_x, unit_y) == null and
                lib_spatial.indexOfAt((ctx).buildings, unit_x, unit_y) == null and
                lib_spatial.indexOfAtExcept((ctx).wildlife, unit_x, unit_y, idx) == null) {
                const ddx = if (unit_x > n.herd_cx) unit_x - n.herd_cx else n.herd_cx - unit_x;
                const ddy = if (unit_y > n.herd_cy) unit_y - n.herd_cy else n.herd_cy - unit_y;
                if (ddx + ddy > n.herd_radius) continue;
                valid_moves[valid_count] = i;
                valid_count += 1;
            }
        }
    }

    if (valid_count > 0) {
        const move_idx = rng.random().intRangeAtMost(usize, 0, valid_count - 1);
        const d = dirs[valid_moves[move_idx]];
        const next_x = @as(isize, @intCast(n.x)) + d.dx;
        const next_y = @as(isize, @intCast(n.y)) + d.dy;
        n.x = @intCast(next_x);
        n.y = @intCast(next_y);
    }
}

test "glyph is d" {
    const cfg = config.default();
    try std.testing.expectEqualStrings("d", glyph(&cfg));
}

test "maxHp positive" {
    const cfg = config.default();
    try std.testing.expect(maxHp(&cfg) > 0);
}

test "maxFood positive" {
    const cfg = config.default();
    try std.testing.expect(maxFood(&cfg) > 0);
}

test "Deer default state is idle" {
    const n = Deer{ .x = 0, .y = 0, .hp = 25 };
    try std.testing.expectEqual(State.idle, n.state);
}

test "Deer.pos returns coordinates" {
    const n = Deer{ .x = 7, .y = 12, .hp = 25 };
    try std.testing.expectEqual(@as(usize, 7), n.pos().x);
    try std.testing.expectEqual(@as(usize, 12), n.pos().y);
}

test "wander doesn't happen when state is wandering" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    const map_size: usize = 80 * 40;
    const tiles = try allocator.alloc(game_map.Tile, map_size);
    defer allocator.free(tiles);
    for (tiles) |*t| t.* = .grass;
    const m = game_map.GameMap{
        .tiles = tiles,
        .tree_remaining = &[_]u16{},
        .width = 80,
        .height = 40,
        .player_tc_x = 12,
        .player_tc_y = 20,
        .enemy_tc_x = 68,
        .enemy_tc_y = 20,
    };
    var units = [_]unit.Unit{};
    var buildings = [_]@import("../buildings/building.zig").Building{};
    var deer_arr = [_]wildlife.Wildlife{
        .{ .deer = .{ .x = 10, .y = 10, .hp = 25, .state = .wandering } },
    };
    const ctx: queries.Ctx = .{
        .units = &units,
        .buildings = &buildings,
        .wildlife = &deer_arr,
    };
    const initial_x = deer_arr[0].deer.x;
    const initial_y = deer_arr[0].deer.y;
    wander(&deer_arr[0].deer, &m, ctx, cfg.deer.wander_interval, 0, &cfg);
    try std.testing.expectEqual(initial_x, deer_arr[0].deer.x);
    try std.testing.expectEqual(initial_y, deer_arr[0].deer.y);
}

test "wander doesn't happen on wrong tick" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    const map_size: usize = 80 * 40;
    const tiles = try allocator.alloc(game_map.Tile, map_size);
    defer allocator.free(tiles);
    for (tiles) |*t| t.* = .grass;
    const m = game_map.GameMap{
        .tiles = tiles,
        .tree_remaining = &[_]u16{},
        .width = 80,
        .height = 40,
        .player_tc_x = 12,
        .player_tc_y = 20,
        .enemy_tc_x = 68,
        .enemy_tc_y = 20,
    };
    var units = [_]unit.Unit{};
    var buildings = [_]@import("../buildings/building.zig").Building{};
    var deer_arr = [_]wildlife.Wildlife{
        .{ .deer = .{ .x = 10, .y = 10, .hp = 25, .state = .idle } },
    };
    const ctx: queries.Ctx = .{
        .units = &units,
        .buildings = &buildings,
        .wildlife = &deer_arr,
    };
    const initial_x = deer_arr[0].deer.x;
    const initial_y = deer_arr[0].deer.y;
    wander(&deer_arr[0].deer, &m, ctx, cfg.deer.wander_interval + 1, 0, &cfg);
    try std.testing.expectEqual(initial_x, deer_arr[0].deer.x);
    try std.testing.expectEqual(initial_y, deer_arr[0].deer.y);
}

test "wander attempts on correct tick" {
    const cfg = config.default();
    const allocator = std.testing.allocator;
    const map_size: usize = 80 * 40;
    const tiles = try allocator.alloc(game_map.Tile, map_size);
    defer allocator.free(tiles);
    for (tiles) |*t| t.* = .grass;
    const m = game_map.GameMap{
        .tiles = tiles,
        .tree_remaining = &[_]u16{},
        .width = 80,
        .height = 40,
        .player_tc_x = 12,
        .player_tc_y = 20,
        .enemy_tc_x = 68,
        .enemy_tc_y = 20,
    };
    var units = [_]unit.Unit{};
    var buildings = [_]@import("../buildings/building.zig").Building{};
    var deer_arr = [_]wildlife.Wildlife{
        .{ .deer = .{ .x = 10, .y = 10, .hp = 25, .state = .idle } },
    };
    const ctx: queries.Ctx = .{
        .units = &units,
        .buildings = &buildings,
        .wildlife = &deer_arr,
    };
    wander(&deer_arr[0].deer, &m, ctx, cfg.deer.wander_interval, 0, &cfg);
}
