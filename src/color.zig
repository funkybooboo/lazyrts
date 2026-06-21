const std = @import("std");
const unit = @import("unit.zig");
const building = @import("building.zig");
const nature = @import("nature.zig");
const config = @import("config.zig");

pub fn lerp(a: u8, b: u8, t: f32) u8 {
    const result = @as(f32, @floatFromInt(a)) + (@as(f32, @floatFromInt(b)) - @as(f32, @floatFromInt(a))) * t;
    const clamped = @max(0.0, @min(255.0, result));
    return @intFromFloat(clamped);
}

pub fn lerp_color(full: [3]u8, damaged: [3]u8, ratio: f32) [3]u8 {
    return .{
        lerp(full[0], damaged[0], ratio),
        lerp(full[1], damaged[1], ratio),
        lerp(full[2], damaged[2], ratio),
    };
}

pub const EntityClass = enum { unit, building };

pub fn full_hp_color(owner: unit.Owner, class: EntityClass, cfg: *const config.Config) [3]u8 {
    return switch (owner) {
        .player => switch (class) {
            .unit => cfg.colors.player_unit_full,
            .building => cfg.colors.player_building_full,
        },
        .enemy => switch (class) {
            .unit => cfg.colors.enemy_unit_full,
            .building => cfg.colors.enemy_building_full,
        },
        .neutral => cfg.colors.neutral_full,
    };
}

pub fn damaged_color(owner: unit.Owner, class: EntityClass, cfg: *const config.Config) [3]u8 {
    return switch (owner) {
        .player => switch (class) {
            .unit => cfg.colors.player_unit_damaged,
            .building => cfg.colors.player_building_damaged,
        },
        .enemy => switch (class) {
            .unit => cfg.colors.enemy_unit_damaged,
            .building => cfg.colors.enemy_building_damaged,
        },
        .neutral => cfg.colors.neutral_damaged,
    };
}

pub fn unbuilt_color(owner: unit.Owner, cfg: *const config.Config) [3]u8 {
    return switch (owner) {
        .player => cfg.colors.player_unbuilt,
        .enemy => cfg.colors.enemy_unbuilt,
        .neutral => cfg.colors.neutral_unbuilt,
    };
}

pub fn health_ratio(hp: u16, max_hp: u16) f32 {
    if (max_hp == 0) return 1.0;
    return 1.0 - @as(f32, @floatFromInt(hp)) / @as(f32, @floatFromInt(max_hp));
}

pub fn resource_ratio(remaining: u16, total: u16) f32 {
    if (total == 0) return 0.0;
    return @as(f32, @floatFromInt(remaining)) / @as(f32, @floatFromInt(total));
}

pub fn tree_tile_color(remaining: u16, total: u16, cfg: *const config.Config) [3]u8 {
    const ratio = resource_ratio(remaining, total);
    return lerp_color(cfg.colors.tile_tree_depleted, cfg.colors.tile_tree, ratio);
}

pub fn unit_color(u: *const unit.Unit, cfg: *const config.Config) [3]u8 {
    const full = full_hp_color(u.owner, .unit, cfg);
    const damaged = damaged_color(u.owner, .unit, cfg);
    const ratio = health_ratio(u.hp, unit.max_hp(u.kind, cfg));
    return lerp_color(full, damaged, ratio);
}

pub fn nature_color(n: *const nature.Nature, cfg: *const config.Config) [3]u8 {
    const full = full_hp_color(.neutral, .unit, cfg);
    const depleted = cfg.colors.nature_deer_depleted;
    const total = nature.max_food(n.kind, cfg);
    const ratio = resource_ratio(n.food_remaining, total);
    return lerp_color(depleted, full, ratio);
}

pub fn building_color(b: *const building.Building, cfg: *const config.Config) [3]u8 {
    const full = full_hp_color(b.owner, .building, cfg);
    const damaged = damaged_color(b.owner, .building, cfg);
    const hp_ratio = health_ratio(b.hp, building.max_hp(b.kind, cfg));
    var base: [3]u8 = undefined;
    if (b.build_progress < 100) {
        const unbuilt = unbuilt_color(b.owner, cfg);
        const build_ratio = 1.0 - @as(f32, @floatFromInt(b.build_progress)) / 100.0;
        base = lerp_color(unbuilt, full, 1.0 - build_ratio);
    } else {
        base = full;
    }
    const hp_col = lerp_color(base, damaged, hp_ratio);
    if (b.kind == .farm) {
        const total = cfg.economy.farm_yield_total;
        const ratio = resource_ratio(b.food_remaining, total);
        return lerp_color(cfg.colors.farm_food_depleted, hp_col, ratio);
    }
    return hp_col;
}

pub const TileColor = struct {
    grass: [3]u8,
    tree: [3]u8,
    water: [3]u8,
};

pub fn tile_colors(cfg: *const config.Config) TileColor {
    return .{
        .grass = cfg.colors.tile_grass,
        .tree = cfg.colors.tile_tree,
        .water = cfg.colors.tile_water,
    };
}

test "lerp at boundaries" {
    try std.testing.expectEqual(@as(u8, 100), lerp(100, 200, 0.0));
    try std.testing.expectEqual(@as(u8, 200), lerp(100, 200, 1.0));
}

test "lerp at midpoint" {
    const result = lerp(0, 100, 0.5);
    try std.testing.expectEqual(@as(u8, 50), result);
}

test "lerp clamps above 255" {
    const result = lerp(200, 100, -0.5);
    try std.testing.expectEqual(@as(u8, 250), result);
}

test "lerp_color full" {
    const result = lerp_color(.{ 100, 50, 0 }, .{ 200, 150, 100 }, 0.0);
    try std.testing.expectEqual(@as(u8, 100), result[0]);
    try std.testing.expectEqual(@as(u8, 50), result[1]);
    try std.testing.expectEqual(@as(u8, 0), result[2]);
}

test "lerp_color damaged" {
    const result = lerp_color(.{ 100, 50, 0 }, .{ 200, 150, 100 }, 1.0);
    try std.testing.expectEqual(@as(u8, 200), result[0]);
    try std.testing.expectEqual(@as(u8, 150), result[1]);
    try std.testing.expectEqual(@as(u8, 100), result[2]);
}

test "full_hp_color returns distinct per owner" {
    const cfg = config.default();
    const p = full_hp_color(.player, .unit, &cfg);
    const e = full_hp_color(.enemy, .unit, &cfg);
    const n = full_hp_color(.neutral, .unit, &cfg);
    try std.testing.expect(!std.mem.eql(u8, &p, &e));
    try std.testing.expect(!std.mem.eql(u8, &e, &n));
    try std.testing.expect(!std.mem.eql(u8, &p, &n));
}

test "damaged_color is lighter than full_hp_color" {
    const cfg = config.default();
    {
        const full = full_hp_color(.player, .unit, &cfg);
        const dmg = damaged_color(.player, .unit, &cfg);
        const full_sum = @as(u16, full[0]) + full[1] + full[2];
        const dmg_sum = @as(u16, dmg[0]) + dmg[1] + dmg[2];
        try std.testing.expect(dmg_sum > full_sum);
    }
    {
        const full = full_hp_color(.enemy, .unit, &cfg);
        const dmg = damaged_color(.enemy, .unit, &cfg);
        const full_sum = @as(u16, full[0]) + full[1] + full[2];
        const dmg_sum = @as(u16, dmg[0]) + dmg[1] + dmg[2];
        try std.testing.expect(dmg_sum > full_sum);
    }
}

test "health_ratio at full HP" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), health_ratio(100, 100), 0.01);
}

test "health_ratio at half HP" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), health_ratio(50, 100), 0.01);
}

test "health_ratio at zero max_hp" {
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), health_ratio(0, 0), 0.01);
}

test "unit_color at full HP equals full_hp_color" {
    const cfg = config.default();
    const u = unit.Unit{ .x = 0, .y = 0, .kind = .worker, .owner = .player, .hp = 50 };
    const result = unit_color(&u, &cfg);
    const expected = full_hp_color(.player, .unit, &cfg);
    try std.testing.expectEqual(expected[0], result[0]);
    try std.testing.expectEqual(expected[1], result[1]);
    try std.testing.expectEqual(expected[2], result[2]);
}

test "building_color fully built at full HP" {
    const cfg = config.default();
    const b = building.Building{ .x = 0, .y = 0, .kind = .town_center, .owner = .player, .hp = 500, .build_progress = 100 };
    const result = building_color(&b, &cfg);
    const expected = full_hp_color(.player, .building, &cfg);
    try std.testing.expectEqual(expected[0], result[0]);
    try std.testing.expectEqual(expected[1], result[1]);
    try std.testing.expectEqual(expected[2], result[2]);
}

test "building_color under construction" {
    const cfg = config.default();
    const b = building.Building{ .x = 0, .y = 0, .kind = .house, .owner = .player, .hp = 200, .build_progress = 50 };
    const result = building_color(&b, &cfg);
    const unbuilt = unbuilt_color(.player, &cfg);
    const full = full_hp_color(.player, .building, &cfg);
    for (0..3) |i| {
        try std.testing.expect(result[i] >= @min(unbuilt[i], full[i]));
        try std.testing.expect(result[i] <= @max(unbuilt[i], full[i]));
    }
}

test "building_color at zero build progress is near unbuilt" {
    const cfg = config.default();
    const b = building.Building{ .x = 0, .y = 0, .kind = .house, .owner = .player, .hp = 200, .build_progress = 0 };
    const result = building_color(&b, &cfg);
    const unbuilt = unbuilt_color(.player, &cfg);
    const full = full_hp_color(.player, .building, &cfg);
    for (0..3) |i| {
        try std.testing.expect(result[i] >= @min(unbuilt[i], full[i]));
        try std.testing.expect(result[i] <= @max(unbuilt[i], full[i]));
    }
}

test "player color distinct from terrain" {
    const cfg = config.default();
    const p = full_hp_color(.player, .unit, &cfg);
    const tc = tile_colors(&cfg);
    try std.testing.expect(!std.mem.eql(u8, &p, &tc.tree));
    try std.testing.expect(!std.mem.eql(u8, &p, &tc.water));
}

test "enemy color distinct from neutral" {
    const cfg = config.default();
    const e = full_hp_color(.enemy, .unit, &cfg);
    const n = full_hp_color(.neutral, .unit, &cfg);
    try std.testing.expect(!std.mem.eql(u8, &e, &n));
}

test "building_color damaged is lighter than full" {
    const cfg = config.default();
    const b_full = building.Building{ .x = 0, .y = 0, .kind = .town_center, .owner = .player, .hp = 500, .build_progress = 100 };
    const b_dmg = building.Building{ .x = 0, .y = 0, .kind = .town_center, .owner = .player, .hp = 50, .build_progress = 100 };
    const full = building_color(&b_full, &cfg);
    const dmg = building_color(&b_dmg, &cfg);
    const full_sum = @as(u16, full[0]) + full[1] + full[2];
    const dmg_sum = @as(u16, dmg[0]) + dmg[1] + dmg[2];
    try std.testing.expect(dmg_sum > full_sum);
}

test "enemy unit color distinct from terrain" {
    const cfg = config.default();
    const e = full_hp_color(.enemy, .unit, &cfg);
    const tc = tile_colors(&cfg);
    try std.testing.expect(!std.mem.eql(u8, &e, &tc.tree));
}

test "neutral color distinct from enemy" {
    const cfg = config.default();
    const n = full_hp_color(.neutral, .unit, &cfg);
    const e = full_hp_color(.enemy, .unit, &cfg);
    try std.testing.expect(!std.mem.eql(u8, &n, &e));
}

test "resource_ratio at full" {
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), resource_ratio(100, 100), 0.01);
}

test "resource_ratio at half" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), resource_ratio(50, 100), 0.01);
}

test "resource_ratio at zero total" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), resource_ratio(0, 0), 0.01);
}

test "tree_tile_color full equals tile_tree" {
    const cfg = config.default();
    const c = tree_tile_color(100, 100, &cfg);
    try std.testing.expectEqual(cfg.colors.tile_tree[0], c[0]);
}

test "tree_tile_color depleted equals depleted color" {
    const cfg = config.default();
    const c = tree_tile_color(0, 100, &cfg);
    try std.testing.expectEqual(cfg.colors.tile_tree_depleted[0], c[0]);
}

test "tree_tile_color gets lighter as depleted" {
    const cfg = config.default();
    const full = tree_tile_color(100, 100, &cfg);
    const half = tree_tile_color(50, 100, &cfg);
    const empty = tree_tile_color(0, 100, &cfg);
    const full_sum = @as(u16, full[0]) + full[1] + full[2];
    const half_sum = @as(u16, half[0]) + half[1] + half[2];
    const empty_sum = @as(u16, empty[0]) + empty[1] + empty[2];
    try std.testing.expect(half_sum > full_sum);
    try std.testing.expect(empty_sum > half_sum);
}

test "nature_color gets lighter as food depletes" {
    const cfg = config.default();
    var n_full = nature.Nature{ .x = 0, .y = 0, .kind = .deer, .hp = 25, .food_remaining = 100 };
    var n_empty = nature.Nature{ .x = 0, .y = 0, .kind = .deer, .hp = 25, .food_remaining = 0 };
    const full = nature_color(&n_full, &cfg);
    const empty = nature_color(&n_empty, &cfg);
    const full_sum = @as(u16, full[0]) + full[1] + full[2];
    const empty_sum = @as(u16, empty[0]) + empty[1] + empty[2];
    try std.testing.expect(empty_sum > full_sum);
}

test "farm building_color gets lighter as food depletes" {
    const cfg = config.default();
    const b_full = building.Building{ .x = 0, .y = 0, .kind = .farm, .owner = .player, .hp = 100, .build_progress = 100, .food_remaining = 250 };
    const b_empty = building.Building{ .x = 0, .y = 0, .kind = .farm, .owner = .player, .hp = 100, .build_progress = 100, .food_remaining = 0, .fallow = true };
    const full = building_color(&b_full, &cfg);
    const empty = building_color(&b_empty, &cfg);
    const full_sum = @as(u16, full[0]) + full[1] + full[2];
    const empty_sum = @as(u16, empty[0]) + empty[1] + empty[2];
    try std.testing.expect(empty_sum > full_sum);
}

test "unit_color enemy at full HP" {
    const cfg = config.default();
    const u = unit.Unit{ .x = 0, .y = 0, .kind = .soldier, .owner = .enemy, .hp = 100 };
    const c = unit_color(&u, &cfg);
    const expected = full_hp_color(.enemy, .unit, &cfg);
    try std.testing.expectEqual(expected[0], c[0]);
    try std.testing.expectEqual(expected[1], c[1]);
    try std.testing.expectEqual(expected[2], c[2]);
}

test "building_color under construction is lighter than complete" {
    const cfg = config.default();
    const b_full = building.Building{ .x = 0, .y = 0, .kind = .house, .owner = .player, .hp = 200, .build_progress = 100 };
    const b_half = building.Building{ .x = 0, .y = 0, .kind = .house, .owner = .player, .hp = 200, .build_progress = 50 };
    const full = building_color(&b_full, &cfg);
    const half = building_color(&b_half, &cfg);
    const full_sum = @as(u16, full[0]) + full[1] + full[2];
    const half_sum = @as(u16, half[0]) + half[1] + half[2];
    try std.testing.expect(half_sum > full_sum);
}
