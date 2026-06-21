const std = @import("std");
const config = @import("config.zig");

pub const BuildingKind = enum {
    town_center,
    house,
    barracks,
    farm,
    drop_pile,

    pub fn glyph(self: BuildingKind, cfg: *const config.Config) []const u8 {
        return switch (self) {
            .town_center => cfg.glyphs.town_center,
            .house => cfg.glyphs.house,
            .barracks => cfg.glyphs.barracks,
            .farm => cfg.glyphs.farm,
            .drop_pile => cfg.glyphs.drop_pile,
        };
    }

    pub fn label(self: BuildingKind, cfg: *const config.Config) []const u8 {
        return switch (self) {
            .town_center => cfg.labels.town_center,
            .house => cfg.labels.house,
            .barracks => cfg.labels.barracks,
            .farm => cfg.labels.farm,
            .drop_pile => cfg.labels.drop_pile,
        };
    }

    pub fn is_depot(self: BuildingKind) bool {
        return self == .town_center or self == .drop_pile;
    }
};

pub const BUILD_COMPLETE_PERCENT: u8 = 100;

pub const Building = struct {
    x: usize,
    y: usize,
    kind: BuildingKind,
    owner: Owner,
    hp: u16,
    build_progress: u8 = 100,
    food_remaining: u16 = 0,
    fallow: bool = false,
    assigned_worker: ?usize = null,

    pub fn is_complete(self: *const Building) bool {
        return self.build_progress >= BUILD_COMPLETE_PERCENT;
    }
};

pub const Owner = @import("unit.zig").Owner;

pub fn max_hp(kind: BuildingKind, cfg: *const config.Config) u16 {
    return switch (kind) {
        .town_center => cfg.building_hp.town_center,
        .house => cfg.building_hp.house,
        .barracks => cfg.building_hp.barracks,
        .farm => cfg.building_hp.farm,
        .drop_pile => cfg.building_hp.drop_pile,
    };
}

test "BuildingKind.glyph all uppercase" {
    const cfg = config.default();
    try std.testing.expectEqualStrings("C", BuildingKind.town_center.glyph(&cfg));
    try std.testing.expectEqualStrings("H", BuildingKind.house.glyph(&cfg));
    try std.testing.expectEqualStrings("B", BuildingKind.barracks.glyph(&cfg));
    try std.testing.expectEqualStrings("F", BuildingKind.farm.glyph(&cfg));
    try std.testing.expectEqualStrings("P", BuildingKind.drop_pile.glyph(&cfg));
}

test "max_hp positive" {
    const cfg = config.default();
    try std.testing.expect(max_hp(.town_center, &cfg) > 0);
    try std.testing.expect(max_hp(.town_center, &cfg) > max_hp(.house, &cfg));
}

test "BuildingKind.label non-empty" {
    const cfg = config.default();
    try std.testing.expect(BuildingKind.town_center.label(&cfg).len > 0);
    try std.testing.expect(BuildingKind.house.label(&cfg).len > 0);
    try std.testing.expect(BuildingKind.barracks.label(&cfg).len > 0);
    try std.testing.expect(BuildingKind.farm.label(&cfg).len > 0);
    try std.testing.expect(BuildingKind.drop_pile.label(&cfg).len > 0);
}

test "Building.is_complete" {
    const b1 = Building{ .x = 0, .y = 0, .kind = .house, .owner = .player, .hp = 200, .build_progress = 100 };
    const b2 = Building{ .x = 0, .y = 0, .kind = .house, .owner = .player, .hp = 200, .build_progress = 50 };
    try std.testing.expect(b1.is_complete());
    try std.testing.expect(!b2.is_complete());
}

test "BuildingKind.glyph is uppercase" {
    const cfg = config.default();
    const kinds = [_]BuildingKind{ .town_center, .house, .barracks, .farm, .drop_pile };
    for (kinds) |k| {
        const g = k.glyph(&cfg);
        try std.testing.expect(g.len == 1);
        try std.testing.expect(g[0] >= 'A' and g[0] <= 'Z');
    }
}

test "is_depot identifies depots" {
    try std.testing.expect(BuildingKind.town_center.is_depot());
    try std.testing.expect(BuildingKind.drop_pile.is_depot());
    try std.testing.expect(!BuildingKind.house.is_depot());
    try std.testing.expect(!BuildingKind.farm.is_depot());
}
