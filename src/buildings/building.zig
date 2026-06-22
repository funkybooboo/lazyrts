const std = @import("std");
const config = @import("../config.zig");
const town_center = @import("town_center.zig");
const house = @import("house.zig");
const barracks = @import("barracks.zig");
const farm = @import("farm.zig");
const drop_pile = @import("drop_pile.zig");

pub const Owner = @import("../units/unit.zig").Owner;

pub const BUILD_COMPLETE_PERCENT: u8 = 100;

pub const Kind = enum {
    town_center,
    house,
    barracks,
    farm,
    drop_pile,

    pub fn glyph(self: Kind, cfg: *const config.Config) []const u8 {
        return switch (self) {
            .town_center => town_center.glyph(cfg),
            .house => house.glyph(cfg),
            .barracks => barracks.glyph(cfg),
            .farm => farm.glyph(cfg),
            .drop_pile => drop_pile.glyph(cfg),
        };
    }

    pub fn label(self: Kind, cfg: *const config.Config) []const u8 {
        return switch (self) {
            .town_center => town_center.label(cfg),
            .house => house.label(cfg),
            .barracks => barracks.label(cfg),
            .farm => farm.label(cfg),
            .drop_pile => drop_pile.label(cfg),
        };
    }

    pub fn isDropoff(self: Kind) bool {
        return switch (self) {
            .town_center => town_center.isDropoff(),
            .drop_pile => drop_pile.isDropoff(),
            else => false,
        };
    }
};

pub const BuildingKind = Kind;

pub const Variant = union(Kind) {
    town_center: town_center.TownCenter,
    house: house.House,
    barracks: barracks.Barracks,
    farm: farm.Farm,
    drop_pile: drop_pile.DropPile,
};

pub fn variantOf(kind: Kind) Variant {
    return switch (kind) {
        .town_center => .{ .town_center = .{} },
        .house => .{ .house = .{} },
        .barracks => .{ .barracks = .{} },
        .farm => .{ .farm = .{} },
        .drop_pile => .{ .drop_pile = .{} },
    };
}

pub const Building = struct {
    x: usize,
    y: usize,
    variant: Variant,
    owner: Owner,
    hp: u16,
    build_progress: u8 = 100,

    pub fn isComplete(self: *const Building) bool {
        return self.build_progress >= BUILD_COMPLETE_PERCENT;
    }

    pub fn kind(self: *const Building) Kind {
        return std.meta.activeTag(self.variant);
    }

    pub fn glyph(self: *const Building, cfg: *const config.Config) []const u8 {
        return self.kind().glyph(cfg);
    }

    pub fn label(self: *const Building, cfg: *const config.Config) []const u8 {
        return self.kind().label(cfg);
    }

    pub fn maxHp(self: *const Building, cfg: *const config.Config) u16 {
        return switch (self.variant) {
            .town_center => town_center.maxHp(cfg),
            .house => house.maxHp(cfg),
            .barracks => barracks.maxHp(cfg),
            .farm => farm.maxHp(cfg),
            .drop_pile => drop_pile.maxHp(cfg),
        };
    }

    pub fn isDropoff(self: *const Building) bool {
        return self.kind().isDropoff();
    }

    pub fn popHousing(self: *const Building, cfg: *const config.Config) usize {
        return switch (self.variant) {
            .town_center => town_center.popHousing(cfg),
            .house => house.popHousing(cfg),
            .barracks => barracks.popHousing(cfg),
            .farm => farm.popHousing(cfg),
            .drop_pile => drop_pile.popHousing(cfg),
        };
    }
};

pub fn maxHp(kind: BuildingKind, cfg: *const config.Config) u16 {
    return switch (kind) {
        .town_center => town_center.maxHp(cfg),
        .house => house.maxHp(cfg),
        .barracks => barracks.maxHp(cfg),
        .farm => farm.maxHp(cfg),
        .drop_pile => drop_pile.maxHp(cfg),
    };
}

test "Kind.glyph all uppercase" {
    const cfg = config.default();
    try std.testing.expectEqualStrings("C", Kind.town_center.glyph(&cfg));
    try std.testing.expectEqualStrings("H", Kind.house.glyph(&cfg));
    try std.testing.expectEqualStrings("B", Kind.barracks.glyph(&cfg));
    try std.testing.expectEqualStrings("F", Kind.farm.glyph(&cfg));
    try std.testing.expectEqualStrings("P", Kind.drop_pile.glyph(&cfg));
}

test "maxHp positive" {
    const cfg = config.default();
    try std.testing.expect(maxHp(.town_center, &cfg) > 0);
    try std.testing.expect(maxHp(.town_center, &cfg) > maxHp(.house, &cfg));
}

test "Kind.label non-empty" {
    const cfg = config.default();
    try std.testing.expect(Kind.town_center.label(&cfg).len > 0);
    try std.testing.expect(Kind.house.label(&cfg).len > 0);
    try std.testing.expect(Kind.barracks.label(&cfg).len > 0);
    try std.testing.expect(Kind.farm.label(&cfg).len > 0);
    try std.testing.expect(Kind.drop_pile.label(&cfg).len > 0);
}

test "Building.isComplete" {
    const b1 = Building{ .x = 0, .y = 0, .variant = .house, .owner = .player, .hp = 200, .build_progress = 100 };
    const b2 = Building{ .x = 0, .y = 0, .variant = .house, .owner = .player, .hp = 200, .build_progress = 50 };
    try std.testing.expect(b1.isComplete());
    try std.testing.expect(!b2.isComplete());
}

test "Kind.glyph is uppercase" {
    const cfg = config.default();
    const kinds = [_]Kind{ .town_center, .house, .barracks, .farm, .drop_pile };
    for (kinds) |k| {
        const g = k.glyph(&cfg);
        try std.testing.expect(g.len == 1);
        try std.testing.expect(g[0] >= 'A' and g[0] <= 'Z');
    }
}

test "isDropoff identifies dropoffs" {
    try std.testing.expect(Kind.town_center.isDropoff());
    try std.testing.expect(Kind.drop_pile.isDropoff());
    try std.testing.expect(!Kind.house.isDropoff());
    try std.testing.expect(!Kind.farm.isDropoff());
}

test "variantOf round-trips kind" {
    try std.testing.expectEqual(Kind.town_center, std.meta.activeTag(variantOf(.town_center)));
    try std.testing.expectEqual(Kind.farm, std.meta.activeTag(variantOf(.farm)));
}

test "Building.kind reports variant tag" {
    const b1 = Building{ .x = 0, .y = 0, .variant = .town_center, .owner = .player, .hp = 500 };
    const b2 = Building{ .x = 0, .y = 0, .variant = .{ .farm = .{} }, .owner = .player, .hp = 100 };
    try std.testing.expectEqual(Kind.town_center, b1.kind());
    try std.testing.expectEqual(Kind.farm, b2.kind());
}

test "Building.popHousing dispatches per variant" {
    const cfg = config.default();
    const tc = Building{ .x = 0, .y = 0, .variant = .town_center, .owner = .player, .hp = 500 };
    const h = Building{ .x = 0, .y = 0, .variant = .house, .owner = .player, .hp = 200 };
    const f = Building{ .x = 0, .y = 0, .variant = .{ .farm = .{} }, .owner = .player, .hp = 100 };
    try std.testing.expect(tc.popHousing(&cfg) > 0);
    try std.testing.expect(h.popHousing(&cfg) > 0);
    try std.testing.expectEqual(@as(usize, 0), f.popHousing(&cfg));
}
