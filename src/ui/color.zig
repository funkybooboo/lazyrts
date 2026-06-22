const std = @import("std");
const unit = @import("../units/unit.zig");
const building = @import("../buildings/building.zig");
const wildlife = @import("../resources/wildlife.zig");
const config = @import("../config.zig");
const blend = @import("../lib/color.zig");

pub const lerp = blend.lerp;
pub const lerpColor = blend.lerpColor;

pub const EntityClass = enum { unit, building };

pub fn fullHpColor(owner: unit.Owner, class: EntityClass, cfg: *const config.Config) [3]u8 {
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

pub fn damagedColor(owner: unit.Owner, class: EntityClass, cfg: *const config.Config) [3]u8 {
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

pub fn unbuiltColor(owner: unit.Owner, cfg: *const config.Config) [3]u8 {
    return switch (owner) {
        .player => cfg.colors.player_unbuilt,
        .enemy => cfg.colors.enemy_unbuilt,
        .neutral => cfg.colors.neutral_unbuilt,
    };
}

pub fn healthRatio(hp: u16, maxHp: u16) f32 {
    return blend.healthRatio(hp, maxHp);
}

pub fn resourceRatio(remaining: u16, total: u16) f32 {
    return blend.resourceRatio(remaining, total);
}

pub fn treeTileColor(remaining: u16, total: u16, cfg: *const config.Config) [3]u8 {
    const ratio = resourceRatio(remaining, total);
    return lerpColor(cfg.colors.tile_tree_depleted, cfg.colors.tile_tree, ratio);
}

pub fn unitColor(u: *const unit.Unit, cfg: *const config.Config) [3]u8 {
    const full = fullHpColor(u.owner, .unit, cfg);
    const damaged = damagedColor(u.owner, .unit, cfg);
    const ratio = healthRatio(u.hp, u.maxHp(cfg));
    return lerpColor(full, damaged, ratio);
}

pub fn wildlifeColor(n: *const wildlife.Wildlife, cfg: *const config.Config) [3]u8 {
    const full = fullHpColor(.neutral, .unit, cfg);
    const depleted = cfg.colors.wildlife_deer_depleted;
    const total = n.maxFood(cfg);
    const ratio = resourceRatio(n.foodRemaining(), total);
    return lerpColor(depleted, full, ratio);
}

pub fn buildingColor(b: *const building.Building, cfg: *const config.Config) [3]u8 {
    const full = fullHpColor(b.owner, .building, cfg);
    const damaged = damagedColor(b.owner, .building, cfg);
    const hp_ratio = healthRatio(b.hp, b.maxHp(cfg));
    var base: [3]u8 = undefined;
    if (b.build_progress < 100) {
        const unbuilt = unbuiltColor(b.owner, cfg);
        const build_ratio = 1.0 - @as(f32, @floatFromInt(b.build_progress)) / 100.0;
        base = lerpColor(unbuilt, full, 1.0 - build_ratio);
    } else {
        base = full;
    }
    const hp_col = lerpColor(base, damaged, hp_ratio);
    if (b.kind() == .farm) {
        const total = cfg.economy.farm_yield_total;
        const ratio = resourceRatio(b.variant.farm.food_remaining, total);
        return lerpColor(cfg.colors.farm_food_depleted, hp_col, ratio);
    }
    return hp_col;
}

pub const TileColor = struct {
    grass: [3]u8,
    tree: [3]u8,
    water: [3]u8,
};

pub fn tileColors(cfg: *const config.Config) TileColor {
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

test "lerpColor full" {
    const result = lerpColor(.{ 100, 50, 0 }, .{ 200, 150, 100 }, 0.0);
    try std.testing.expectEqual(@as(u8, 100), result[0]);
    try std.testing.expectEqual(@as(u8, 50), result[1]);
    try std.testing.expectEqual(@as(u8, 0), result[2]);
}

test "lerpColor damaged" {
    const result = lerpColor(.{ 100, 50, 0 }, .{ 200, 150, 100 }, 1.0);
    try std.testing.expectEqual(@as(u8, 200), result[0]);
    try std.testing.expectEqual(@as(u8, 150), result[1]);
    try std.testing.expectEqual(@as(u8, 100), result[2]);
}

test "fullHpColor returns distinct per owner" {
    const cfg = config.default();
    const p = fullHpColor(.player, .unit, &cfg);
    const e = fullHpColor(.enemy, .unit, &cfg);
    const n = fullHpColor(.neutral, .unit, &cfg);
    try std.testing.expect(!std.mem.eql(u8, &p, &e));
    try std.testing.expect(!std.mem.eql(u8, &e, &n));
    try std.testing.expect(!std.mem.eql(u8, &p, &n));
}

test "damagedColor is lighter than fullHpColor" {
    const cfg = config.default();
    {
        const full = fullHpColor(.player, .unit, &cfg);
        const dmg = damagedColor(.player, .unit, &cfg);
        const full_sum = @as(u16, full[0]) + full[1] + full[2];
        const dmg_sum = @as(u16, dmg[0]) + dmg[1] + dmg[2];
        try std.testing.expect(dmg_sum > full_sum);
    }
    {
        const full = fullHpColor(.enemy, .unit, &cfg);
        const dmg = damagedColor(.enemy, .unit, &cfg);
        const full_sum = @as(u16, full[0]) + full[1] + full[2];
        const dmg_sum = @as(u16, dmg[0]) + dmg[1] + dmg[2];
        try std.testing.expect(dmg_sum > full_sum);
    }
}

test "healthRatio at full HP" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), healthRatio(100, 100), 0.01);
}

test "healthRatio at half HP" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), healthRatio(50, 100), 0.01);
}

test "healthRatio at zero maxHp" {
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), healthRatio(0, 0), 0.01);
}

test "unitColor at full HP equals fullHpColor" {
    const cfg = config.default();
    const u = unit.Unit{ .x = 0, .y = 0, .variant = .worker, .owner = .player, .hp = 50 };
    const result = unitColor(&u, &cfg);
    const expected = fullHpColor(.player, .unit, &cfg);
    try std.testing.expectEqual(expected[0], result[0]);
    try std.testing.expectEqual(expected[1], result[1]);
    try std.testing.expectEqual(expected[2], result[2]);
}

test "buildingColor fully built at full HP" {
    const cfg = config.default();
    const b = building.Building{ .x = 0, .y = 0, .variant = .town_center, .owner = .player, .hp = 500, .build_progress = 100 };
    const result = buildingColor(&b, &cfg);
    const expected = fullHpColor(.player, .building, &cfg);
    try std.testing.expectEqual(expected[0], result[0]);
    try std.testing.expectEqual(expected[1], result[1]);
    try std.testing.expectEqual(expected[2], result[2]);
}

test "buildingColor under construction" {
    const cfg = config.default();
    const b = building.Building{ .x = 0, .y = 0, .variant = .house, .owner = .player, .hp = 200, .build_progress = 50 };
    const result = buildingColor(&b, &cfg);
    const unbuilt = unbuiltColor(.player, &cfg);
    const full = fullHpColor(.player, .building, &cfg);
    for (0..3) |i| {
        try std.testing.expect(result[i] >= @min(unbuilt[i], full[i]));
        try std.testing.expect(result[i] <= @max(unbuilt[i], full[i]));
    }
}

test "buildingColor at zero build progress is near unbuilt" {
    const cfg = config.default();
    const b = building.Building{ .x = 0, .y = 0, .variant = .house, .owner = .player, .hp = 200, .build_progress = 0 };
    const result = buildingColor(&b, &cfg);
    const unbuilt = unbuiltColor(.player, &cfg);
    const full = fullHpColor(.player, .building, &cfg);
    for (0..3) |i| {
        try std.testing.expect(result[i] >= @min(unbuilt[i], full[i]));
        try std.testing.expect(result[i] <= @max(unbuilt[i], full[i]));
    }
}

test "player color distinct from terrain" {
    const cfg = config.default();
    const p = fullHpColor(.player, .unit, &cfg);
    const tc = tileColors(&cfg);
    try std.testing.expect(!std.mem.eql(u8, &p, &tc.tree));
    try std.testing.expect(!std.mem.eql(u8, &p, &tc.water));
}

test "enemy color distinct from neutral" {
    const cfg = config.default();
    const e = fullHpColor(.enemy, .unit, &cfg);
    const n = fullHpColor(.neutral, .unit, &cfg);
    try std.testing.expect(!std.mem.eql(u8, &e, &n));
}

test "buildingColor damaged is lighter than full" {
    const cfg = config.default();
    const b_full = building.Building{ .x = 0, .y = 0, .variant = .town_center, .owner = .player, .hp = 500, .build_progress = 100 };
    const b_dmg = building.Building{ .x = 0, .y = 0, .variant = .town_center, .owner = .player, .hp = 50, .build_progress = 100 };
    const full = buildingColor(&b_full, &cfg);
    const dmg = buildingColor(&b_dmg, &cfg);
    const full_sum = @as(u16, full[0]) + full[1] + full[2];
    const dmg_sum = @as(u16, dmg[0]) + dmg[1] + dmg[2];
    try std.testing.expect(dmg_sum > full_sum);
}

test "enemy unit color distinct from terrain" {
    const cfg = config.default();
    const e = fullHpColor(.enemy, .unit, &cfg);
    const tc = tileColors(&cfg);
    try std.testing.expect(!std.mem.eql(u8, &e, &tc.tree));
}

test "neutral color distinct from enemy" {
    const cfg = config.default();
    const n = fullHpColor(.neutral, .unit, &cfg);
    const e = fullHpColor(.enemy, .unit, &cfg);
    try std.testing.expect(!std.mem.eql(u8, &n, &e));
}

test "resourceRatio at full" {
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), resourceRatio(100, 100), 0.01);
}

test "resourceRatio at half" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), resourceRatio(50, 100), 0.01);
}

test "resourceRatio at zero total" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), resourceRatio(0, 0), 0.01);
}

test "treeTileColor full equals tile_tree" {
    const cfg = config.default();
    const c = treeTileColor(100, 100, &cfg);
    try std.testing.expectEqual(cfg.colors.tile_tree[0], c[0]);
}

test "treeTileColor depleted equals depleted color" {
    const cfg = config.default();
    const c = treeTileColor(0, 100, &cfg);
    try std.testing.expectEqual(cfg.colors.tile_tree_depleted[0], c[0]);
}

test "treeTileColor gets lighter as depleted" {
    const cfg = config.default();
    const full = treeTileColor(100, 100, &cfg);
    const half = treeTileColor(50, 100, &cfg);
    const empty = treeTileColor(0, 100, &cfg);
    const full_sum = @as(u16, full[0]) + full[1] + full[2];
    const half_sum = @as(u16, half[0]) + half[1] + half[2];
    const empty_sum = @as(u16, empty[0]) + empty[1] + empty[2];
    try std.testing.expect(half_sum > full_sum);
    try std.testing.expect(empty_sum > half_sum);
}

test "wildlifeColor gets lighter as food depletes" {
    const cfg = config.default();
    var n_full = wildlife.Wildlife{ .deer = .{ .x = 0, .y = 0, .hp = 25, .food_remaining = 100 } };
    var n_empty = wildlife.Wildlife{ .deer = .{ .x = 0, .y = 0, .hp = 25, .food_remaining = 0 } };
    const full = wildlifeColor(&n_full, &cfg);
    const empty = wildlifeColor(&n_empty, &cfg);
    const full_sum = @as(u16, full[0]) + full[1] + full[2];
    const empty_sum = @as(u16, empty[0]) + empty[1] + empty[2];
    try std.testing.expect(empty_sum > full_sum);
}

test "farm buildingColor gets lighter as food depletes" {
    const cfg = config.default();
    const b_full = building.Building{ .x = 0, .y = 0, .variant = .{ .farm = .{ .food_remaining = 250 } }, .owner = .player, .hp = 100, .build_progress = 100 };
    const b_empty = building.Building{ .x = 0, .y = 0, .variant = .{ .farm = .{ .food_remaining = 0, .fallow = true } }, .owner = .player, .hp = 100, .build_progress = 100 };
    const full = buildingColor(&b_full, &cfg);
    const empty = buildingColor(&b_empty, &cfg);
    const full_sum = @as(u16, full[0]) + full[1] + full[2];
    const empty_sum = @as(u16, empty[0]) + empty[1] + empty[2];
    try std.testing.expect(empty_sum > full_sum);
}

test "unitColor enemy at full HP" {
    const cfg = config.default();
    const u = unit.Unit{ .x = 0, .y = 0, .variant = .soldier, .owner = .enemy, .hp = 100 };
    const c = unitColor(&u, &cfg);
    const expected = fullHpColor(.enemy, .unit, &cfg);
    try std.testing.expectEqual(expected[0], c[0]);
    try std.testing.expectEqual(expected[1], c[1]);
    try std.testing.expectEqual(expected[2], c[2]);
}

test "buildingColor under construction is lighter than complete" {
    const cfg = config.default();
    const b_full = building.Building{ .x = 0, .y = 0, .variant = .house, .owner = .player, .hp = 200, .build_progress = 100 };
    const b_half = building.Building{ .x = 0, .y = 0, .variant = .house, .owner = .player, .hp = 200, .build_progress = 50 };
    const full = buildingColor(&b_full, &cfg);
    const half = buildingColor(&b_half, &cfg);
    const full_sum = @as(u16, full[0]) + full[1] + full[2];
    const half_sum = @as(u16, half[0]) + half[1] + half[2];
    try std.testing.expect(half_sum > full_sum);
}
