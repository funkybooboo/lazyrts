const entity = @import("entity.zig");

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

pub fn full_hp_color(owner: entity.Owner, class: EntityClass) [3]u8 {
    return switch (owner) {
        .player => switch (class) {
            .unit => .{ 0, 200, 200 },
            .building => .{ 0, 170, 170 },
        },
        .enemy => switch (class) {
            .unit => .{ 210, 40, 40 },
            .building => .{ 180, 30, 30 },
        },
        .neutral => .{ 140, 95, 35 },
    };
}

pub fn damaged_color(owner: entity.Owner, class: EntityClass) [3]u8 {
    return switch (owner) {
        .player => switch (class) {
            .unit => .{ 150, 235, 235 },
            .building => .{ 140, 220, 220 },
        },
        .enemy => switch (class) {
            .unit => .{ 255, 140, 140 },
            .building => .{ 255, 120, 120 },
        },
        .neutral => .{ 220, 185, 140 },
    };
}

pub fn unbuilt_color(owner: entity.Owner) [3]u8 {
    return switch (owner) {
        .player => .{ 140, 220, 220 },
        .enemy => .{ 255, 120, 120 },
        .neutral => .{ 255, 230, 100 },
    };
}

pub fn health_ratio(hp: u16, max_hp: u16) f32 {
    if (max_hp == 0) return 1.0;
    return 1.0 - @as(f32, @floatFromInt(hp)) / @as(f32, @floatFromInt(max_hp));
}

pub fn unit_color(u: *const entity.Unit) [3]u8 {
    const full = full_hp_color(u.owner, .unit);
    const damaged = damaged_color(u.owner, .unit);
    const ratio = health_ratio(u.hp, u.kind.max_hp());
    return lerp_color(full, damaged, ratio);
}

pub fn building_color(b: *const entity.Building) [3]u8 {
    const full = full_hp_color(b.owner, .building);
    const damaged = damaged_color(b.owner, .building);
    const hp_ratio = health_ratio(b.hp, b.kind.max_hp());
    if (b.build_progress < 100) {
        const unbuilt = unbuilt_color(b.owner);
        const build_ratio = 1.0 - @as(f32, @floatFromInt(b.build_progress)) / 100.0;
        const built_color = lerp_color(unbuilt, full, 1.0 - build_ratio);
        return lerp_color(built_color, damaged, hp_ratio);
    }
    return lerp_color(full, damaged, hp_ratio);
}

pub const TileColor = struct {
    grass: [3]u8 = .{ 30, 30, 30 },
    tree: [3]u8 = .{ 30, 130, 30 },
    water: [3]u8 = .{ 40, 90, 180 },
};

pub const tile_colors = TileColor{};

const std = @import("std");

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
    const p = full_hp_color(.player, .unit);
    const e = full_hp_color(.enemy, .unit);
    const n = full_hp_color(.neutral, .unit);
    try std.testing.expect(!std.mem.eql(u8, &p, &e));
    try std.testing.expect(!std.mem.eql(u8, &e, &n));
    try std.testing.expect(!std.mem.eql(u8, &p, &n));
}

test "damaged_color is lighter than full_hp_color" {
    {
        const full = full_hp_color(.player, .unit);
        const dmg = damaged_color(.player, .unit);
        const full_sum = @as(u16, full[0]) + full[1] + full[2];
        const dmg_sum = @as(u16, dmg[0]) + dmg[1] + dmg[2];
        try std.testing.expect(dmg_sum > full_sum);
    }
    {
        const full = full_hp_color(.enemy, .unit);
        const dmg = damaged_color(.enemy, .unit);
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
    const u = entity.Unit{ .x = 0, .y = 0, .kind = .worker, .owner = .player, .hp = 50 };
    const result = unit_color(&u);
    const expected = full_hp_color(.player, .unit);
    try std.testing.expectEqual(expected[0], result[0]);
    try std.testing.expectEqual(expected[1], result[1]);
    try std.testing.expectEqual(expected[2], result[2]);
}

test "building_color fully built at full HP" {
    const b = entity.Building{ .x = 0, .y = 0, .kind = .town_center, .owner = .player, .hp = 500, .build_progress = 100 };
    const result = building_color(&b);
    const expected = full_hp_color(.player, .building);
    try std.testing.expectEqual(expected[0], result[0]);
    try std.testing.expectEqual(expected[1], result[1]);
    try std.testing.expectEqual(expected[2], result[2]);
}

test "building_color under construction" {
    const b = entity.Building{ .x = 0, .y = 0, .kind = .house, .owner = .player, .hp = 200, .build_progress = 50 };
    const result = building_color(&b);
    const unbuilt = unbuilt_color(.player);
    const full = full_hp_color(.player, .building);
    for (0..3) |i| {
        try std.testing.expect(result[i] >= @min(unbuilt[i], full[i]));
        try std.testing.expect(result[i] <= @max(unbuilt[i], full[i]));
    }
}

test "building_color at zero build progress is near unbuilt" {
    const b = entity.Building{ .x = 0, .y = 0, .kind = .house, .owner = .player, .hp = 200, .build_progress = 0 };
    const result = building_color(&b);
    const unbuilt = unbuilt_color(.player);
    const full = full_hp_color(.player, .building);
    for (0..3) |i| {
        try std.testing.expect(result[i] >= @min(unbuilt[i], full[i]));
        try std.testing.expect(result[i] <= @max(unbuilt[i], full[i]));
    }
}

test "player color distinct from terrain" {
    const p = full_hp_color(.player, .unit);
    const tree = tile_colors.tree;
    const water = tile_colors.water;
    try std.testing.expect(!std.mem.eql(u8, &p, &tree));
    try std.testing.expect(!std.mem.eql(u8, &p, &water));
}

test "enemy color distinct from neutral" {
    const e = full_hp_color(.enemy, .unit);
    const n = full_hp_color(.neutral, .unit);
    try std.testing.expect(!std.mem.eql(u8, &e, &n));
}

test "building_color damaged is lighter than full" {
    const b_full = entity.Building{ .x = 0, .y = 0, .kind = .town_center, .owner = .player, .hp = 500, .build_progress = 100 };
    const b_dmg = entity.Building{ .x = 0, .y = 0, .kind = .town_center, .owner = .player, .hp = 50, .build_progress = 100 };
    const full = building_color(&b_full);
    const dmg = building_color(&b_dmg);
    const full_sum = @as(u16, full[0]) + full[1] + full[2];
    const dmg_sum = @as(u16, dmg[0]) + dmg[1] + dmg[2];
    try std.testing.expect(dmg_sum > full_sum);
}

test "enemy unit color distinct from terrain" {
    const e = full_hp_color(.enemy, .unit);
    const tree = tile_colors.tree;
    try std.testing.expect(!std.mem.eql(u8, &e, &tree));
}

test "neutral color distinct from enemy" {
    const n = full_hp_color(.neutral, .unit);
    const e = full_hp_color(.enemy, .unit);
    try std.testing.expect(!std.mem.eql(u8, &n, &e));
}

test "health_ratio at 1 HP out of 100" {
    try std.testing.expectApproxEqAbs(@as(f32, 0.99), health_ratio(1, 100), 0.02);
}

test "unit_color enemy at full HP" {
    const u = entity.Unit{ .x = 0, .y = 0, .kind = .soldier, .owner = .enemy, .hp = 100 };
    const c = unit_color(&u);
    const expected = full_hp_color(.enemy, .unit);
    try std.testing.expectEqual(expected[0], c[0]);
    try std.testing.expectEqual(expected[1], c[1]);
    try std.testing.expectEqual(expected[2], c[2]);
}

test "building_color under construction is lighter than complete" {
    const b_full = entity.Building{ .x = 0, .y = 0, .kind = .house, .owner = .player, .hp = 200, .build_progress = 100 };
    const b_half = entity.Building{ .x = 0, .y = 0, .kind = .house, .owner = .player, .hp = 200, .build_progress = 50 };
    const full = building_color(&b_full);
    const half = building_color(&b_half);
    const full_sum = @as(u16, full[0]) + full[1] + full[2];
    const half_sum = @as(u16, half[0]) + half[1] + half[2];
    try std.testing.expect(half_sum > full_sum);
}
