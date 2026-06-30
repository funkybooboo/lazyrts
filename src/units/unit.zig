const std = @import("std");
const config = @import("../config.zig");
const coords = @import("../lib/coords.zig");
const worker = @import("worker.zig");
const soldier = @import("soldier.zig");

const Pos = coords.Pos;

pub const Owner = enum(u2) { player, enemy, neutral };

pub const UnitActivity = enum { idle, moving, gathering_wood, gathering_food, hunting, constructing };

pub const CargoKind = enum(u2) { none, wood, food };

pub const GatherPhase = enum(u3) { none, to_resource, harvesting, to_dropoff };

pub const Kind = enum {
    worker,
    soldier,

    pub fn glyph(self: Kind, cfg: *const config.Config) []const u8 {
        return switch (self) {
            .worker => worker.glyph(cfg),
            .soldier => soldier.glyph(cfg),
        };
    }
};

pub const UnitKind = Kind;

pub const Variant = union(Kind) {
    worker: worker.Worker,
    soldier: soldier.Soldier,
};

pub fn variantOf(kind: Kind) Variant {
    return switch (kind) {
        .worker => .{ .worker = .{} },
        .soldier => .{ .soldier = .{} },
    };
}

pub const Unit = struct {
    x: usize,
    y: usize,
    variant: Variant,
    owner: Owner,
    hp: u16,
    state: UnitActivity = .idle,
    path: []Pos = &[_]Pos{},
    path_len: usize = 0,
    path_idx: usize = 0,
    dest: ?Pos = null,

    gather_phase: GatherPhase = .none,
    gather_target: ?Pos = null,
    gather_accum_ms: u32 = 0,
    carry: u16 = 0,
    carry_kind: CargoKind = .none,
    target_deer_idx: ?usize = null,
    target_farm_idx: ?usize = null,
    grove_anchor: ?Pos = null,
    last_repath_tick: usize = 0,

    pub fn pos(self: *const Unit) Pos {
        return .{ .x = self.x, .y = self.y };
    }

    pub fn step(self: *Unit) void {
        if (self.path_idx >= self.path_len) return;
        self.x = self.path[self.path_idx].x;
        self.y = self.path[self.path_idx].y;
        self.path_idx += 1;
        if (self.path_idx >= self.path_len) {
            self.path_len = 0;
            self.path_idx = 0;
            if (self.state == .moving) self.state = .idle;
        }
    }

    pub fn kind(self: *const Unit) Kind {
        return std.meta.activeTag(self.variant);
    }

    pub fn glyph(self: *const Unit, cfg: *const config.Config) []const u8 {
        return self.kind().glyph(cfg);
    }

    pub fn maxHp(self: *const Unit, cfg: *const config.Config) u16 {
        return switch (self.variant) {
            .worker => worker.maxHp(cfg),
            .soldier => soldier.maxHp(cfg),
        };
    }

    pub fn attackDamage(self: *const Unit) u16 {
        return switch (self.variant) {
            .worker => worker.damage(),
            .soldier => soldier.damage(),
        };
    }
};

pub fn maxHp(kind: UnitKind, cfg: *const config.Config) u16 {
    return switch (kind) {
        .worker => worker.maxHp(cfg),
        .soldier => soldier.maxHp(cfg),
    };
}

test "Unit.pos returns coordinates" {
    const u = Unit{ .x = 7, .y = 12, .variant = .worker, .owner = .player, .hp = 50 };
    const p = u.pos();
    try std.testing.expectEqual(@as(usize, 7), p.x);
    try std.testing.expectEqual(@as(usize, 12), p.y);
}

test "Unit.step moves along path" {
    const allocator = std.testing.allocator;
    var path_buf = try allocator.alloc(Pos, 2);
    defer allocator.free(path_buf);
    path_buf[0] = .{ .x = 6, .y = 5 };
    path_buf[1] = .{ .x = 7, .y = 5 };
    var u = Unit{ .x = 5, .y = 5, .variant = .worker, .owner = .player, .hp = 50, .state = .moving, .path = path_buf, .path_len = 2, .path_idx = 0 };
    u.step();
    try std.testing.expectEqual(@as(usize, 6), u.x);
    try std.testing.expectEqual(UnitActivity.moving, u.state);
    u.step();
    try std.testing.expectEqual(@as(usize, 7), u.x);
    try std.testing.expectEqual(UnitActivity.idle, u.state);
    try std.testing.expectEqual(@as(usize, 0), u.path_len);
}

test "Unit.step on idle does nothing" {
    var u = Unit{ .x = 5, .y = 5, .variant = .worker, .owner = .player, .hp = 50, .state = .idle };
    u.step();
    try std.testing.expectEqual(@as(usize, 5), u.x);
}

test "Kind.glyph all lowercase" {
    const cfg = config.default();
    try std.testing.expectEqualStrings("w", Kind.worker.glyph(&cfg));
    try std.testing.expectEqualStrings("s", Kind.soldier.glyph(&cfg));
}

test "maxHp positive" {
    const cfg = config.default();
    try std.testing.expect(maxHp(.worker, &cfg) > 0);
    try std.testing.expect(maxHp(.soldier, &cfg) > 0);
    try std.testing.expect(maxHp(.soldier, &cfg) > maxHp(.worker, &cfg));
}

test "Owner has three variants" {
    try std.testing.expectEqual(@as(usize, 3), @typeInfo(Owner).@"enum".fields.len);
}

test "Unit default state is idle" {
    const u = Unit{ .x = 0, .y = 0, .variant = .worker, .owner = .player, .hp = 50 };
    try std.testing.expectEqual(UnitActivity.idle, u.state);
}

test "Unit.step path end resets state" {
    const allocator = std.testing.allocator;
    var path_buf = try allocator.alloc(Pos, 1);
    defer allocator.free(path_buf);
    path_buf[0] = .{ .x = 6, .y = 5 };
    var u = Unit{ .x = 5, .y = 5, .variant = .worker, .owner = .player, .hp = 50, .state = .moving, .path = path_buf, .path_len = 1, .path_idx = 0 };
    u.step();
    try std.testing.expectEqual(UnitActivity.idle, u.state);
    try std.testing.expectEqual(@as(usize, 0), u.path_len);
    try std.testing.expectEqual(@as(usize, 0), u.path_idx);
}

test "Kind.glyph is lowercase" {
    const cfg = config.default();
    const kinds = [_]Kind{ .worker, .soldier };
    for (kinds) |k| {
        const g = k.glyph(&cfg);
        try std.testing.expect(g.len == 1);
        try std.testing.expect(g[0] >= 'a' and g[0] <= 'z');
    }
}

test "variantOf round-trips kind" {
    try std.testing.expectEqual(Kind.worker, std.meta.activeTag(variantOf(.worker)));
    try std.testing.expectEqual(Kind.soldier, std.meta.activeTag(variantOf(.soldier)));
}

test "Unit.kind reports variant tag" {
    const uw = Unit{ .x = 0, .y = 0, .variant = .worker, .owner = .player, .hp = 50 };
    const us = Unit{ .x = 0, .y = 0, .variant = .soldier, .owner = .player, .hp = 50 };
    try std.testing.expectEqual(Kind.worker, uw.kind());
    try std.testing.expectEqual(Kind.soldier, us.kind());
}

test "Unit.maxHp dispatches per variant" {
    const cfg = config.default();
    const uw = Unit{ .x = 0, .y = 0, .variant = .worker, .owner = .player, .hp = 50 };
    const us = Unit{ .x = 0, .y = 0, .variant = .soldier, .owner = .player, .hp = 50 };
    try std.testing.expect(us.maxHp(&cfg) > uw.maxHp(&cfg));
}

test "Unit.attackDamage worker 3 soldier 8" {
    const uw = Unit{ .x = 0, .y = 0, .variant = .worker, .owner = .player, .hp = 50 };
    const us = Unit{ .x = 0, .y = 0, .variant = .soldier, .owner = .player, .hp = 50 };
    try std.testing.expectEqual(@as(u16, 3), uw.attackDamage());
    try std.testing.expectEqual(@as(u16, 8), us.attackDamage());
}
