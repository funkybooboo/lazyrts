const std = @import("std");
const config = @import("../config.zig");
const unit = @import("../units/unit.zig");
const coords = @import("../lib/coords.zig");
const game_map = @import("../game/map.zig");
const queries = @import("../game/queries.zig");
const deer_mod = @import("deer.zig");

pub const Deer = deer_mod.Deer;
pub const DeerState = deer_mod.State;

pub const Kind = enum {
    deer,

    pub fn glyph(self: Kind, cfg: *const config.Config) []const u8 {
        return switch (self) {
            .deer => deer_mod.glyph(cfg),
        };
    }
};

pub const WildlifeKind = Kind;

pub const Variant = union(Kind) {
    deer: Deer,
};

pub fn variantOf(kind: Kind) Variant {
    return switch (kind) {
        .deer => .{ .deer = .{ .x = 0, .y = 0, .hp = 0 } },
    };
}

pub const Wildlife = union(Kind) {
    deer: Deer,

    pub fn kind(self: Wildlife) Kind {
        return std.meta.activeTag(self);
    }

    pub fn pos(self: Wildlife) coords.Pos {
        return switch (self) {
            .deer => |d| d.pos(),
        };
    }

    pub fn glyph(self: Wildlife, cfg: *const config.Config) []const u8 {
        return self.kind().glyph(cfg);
    }

    pub fn maxHp(self: Wildlife, cfg: *const config.Config) u16 {
        return switch (self) {
            .deer => deer_mod.maxHp(cfg),
        };
    }

    pub fn maxFood(self: Wildlife, cfg: *const config.Config) u16 {
        return switch (self) {
            .deer => deer_mod.maxFood(cfg),
        };
    }

    pub fn isDead(self: Wildlife) bool {
        return switch (self) {
            .deer => |d| d.dead,
        };
    }

    pub fn foodRemaining(self: Wildlife) u16 {
        return switch (self) {
            .deer => |d| d.food_remaining,
        };
    }

    pub fn wander(self: *Wildlife, m: *const game_map.GameMap, ctx: queries.Ctx, tick_count: usize, idx: usize, cfg: *const config.Config) void {
        switch (self.*) {
            .deer => |*d| deer_mod.wander(d, m, ctx, tick_count, idx, cfg),
        }
    }
};

pub fn maxHp(kind: Kind, cfg: *const config.Config) u16 {
    return switch (kind) {
        .deer => deer_mod.maxHp(cfg),
    };
}

pub fn maxFood(kind: Kind, cfg: *const config.Config) u16 {
    return switch (kind) {
        .deer => deer_mod.maxFood(cfg),
    };
}

test "Kind.glyph is d" {
    const cfg = config.default();
    try std.testing.expectEqualStrings("d", Kind.deer.glyph(&cfg));
}

test "maxHp positive" {
    const cfg = config.default();
    try std.testing.expect(maxHp(.deer, &cfg) > 0);
}

test "maxFood positive" {
    const cfg = config.default();
    try std.testing.expect(maxFood(.deer, &cfg) > 0);
}

test "variantOf round-trips kind" {
    try std.testing.expectEqual(Kind.deer, std.meta.activeTag(variantOf(.deer)));
}

test "Wildlife.pos dispatches" {
    const w: Wildlife = .{ .deer = .{ .x = 7, .y = 12, .hp = 25 } };
    try std.testing.expectEqual(@as(usize, 7), w.pos().x);
    try std.testing.expectEqual(@as(usize, 12), w.pos().y);
}

test "Wildlife.isDead dispatches" {
    const w_alive: Wildlife = .{ .deer = .{ .x = 0, .y = 0, .hp = 25 } };
    const w_dead: Wildlife = .{ .deer = .{ .x = 0, .y = 0, .hp = 25, .dead = true } };
    try std.testing.expect(!w_alive.isDead());
    try std.testing.expect(w_dead.isDead());
}

test "Wildlife.foodRemaining dispatches" {
    const w: Wildlife = .{ .deer = .{ .x = 0, .y = 0, .hp = 25, .food_remaining = 80 } };
    try std.testing.expectEqual(@as(u16, 80), w.foodRemaining());
}
