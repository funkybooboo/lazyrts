const std = @import("std");

pub fn lerp(a: u8, b: u8, t: f32) u8 {
    const result = @as(f32, @floatFromInt(a)) + (@as(f32, @floatFromInt(b)) - @as(f32, @floatFromInt(a))) * t;
    const clamped = @max(0.0, @min(255.0, result));
    return @intFromFloat(clamped);
}

pub fn lerpColor(full: [3]u8, damaged: [3]u8, ratio: f32) [3]u8 {
    return .{
        lerp(full[0], damaged[0], ratio),
        lerp(full[1], damaged[1], ratio),
        lerp(full[2], damaged[2], ratio),
    };
}

pub fn healthRatio(hp: u16, max_hp: u16) f32 {
    if (max_hp == 0) return 1.0;
    return 1.0 - @as(f32, @floatFromInt(hp)) / @as(f32, @floatFromInt(max_hp));
}

pub fn resourceRatio(remaining: u16, total: u16) f32 {
    if (total == 0) return 0.0;
    return @as(f32, @floatFromInt(remaining)) / @as(f32, @floatFromInt(total));
}

test "lerp clamps below zero" {
    try std.testing.expectEqual(@as(u8, 0), lerp(10, 20, -1.0));
}

test "lerp clamps above 255" {
    try std.testing.expectEqual(@as(u8, 255), lerp(200, 210, 10.0));
}

test "lerp midpoint" {
    try std.testing.expectEqual(@as(u8, 15), lerp(10, 20, 0.5));
}

test "lerpColor blends each channel" {
    const c = lerpColor(.{ 0, 100, 200 }, .{ 100, 100, 100 }, 0.5);
    try std.testing.expectEqual(@as(u8, 50), c[0]);
    try std.testing.expectEqual(@as(u8, 100), c[1]);
    try std.testing.expectEqual(@as(u8, 150), c[2]);
}

test "healthRatio zero max returns 1" {
    try std.testing.expectEqual(@as(f32, 1.0), healthRatio(0, 0));
}

test "healthRatio full hp returns 0" {
    try std.testing.expectEqual(@as(f32, 0.0), healthRatio(100, 100));
}

test "healthRatio half hp returns 0.5" {
    try std.testing.expectEqual(@as(f32, 0.5), healthRatio(50, 100));
}

test "resourceRatio zero total returns 0" {
    try std.testing.expectEqual(@as(f32, 0.0), resourceRatio(50, 0));
}

test "resourceRatio full returns 1" {
    try std.testing.expectEqual(@as(f32, 1.0), resourceRatio(100, 100));
}

test "resourceRatio half returns 0.5" {
    try std.testing.expectEqual(@as(f32, 0.5), resourceRatio(50, 100));
}
