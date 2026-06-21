const std = @import("std");
const config = @import("config.zig");

pub const Pos = struct { x: usize, y: usize };

pub const Owner = enum(u2) { player, enemy, neutral };

pub const UnitKind = enum {
    worker,
    soldier,

    pub fn glyph(self: UnitKind, cfg: *const config.Config) []const u8 {
        return switch (self) {
            .worker => cfg.glyphs.worker,
            .soldier => cfg.glyphs.soldier,
        };
    }
};

pub const UnitState = enum { idle, moving, gathering_wood, gathering_food, hunting, constructing };

pub const CarryKind = enum(u2) { none, wood, food };

pub const GatherPhase = enum(u3) { none, to_resource, harvesting, to_depot };

pub const Unit = struct {
    x: usize,
    y: usize,
    kind: UnitKind,
    owner: Owner,
    hp: u16,
    state: UnitState = .idle,
    path: []Pos = &[_]Pos{},
    path_len: usize = 0,
    path_idx: usize = 0,
    dest: ?Pos = null,

    gather_phase: GatherPhase = .none,
    gather_target: ?Pos = null,
    gather_timer: u16 = 0,
    carry: u16 = 0,
    carry_kind: CarryKind = .none,
    target_deer_idx: ?usize = null,
    target_farm_idx: ?usize = null,
    grove_anchor: ?Pos = null,

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
};

pub fn max_hp(kind: UnitKind, cfg: *const config.Config) u16 {
    return switch (kind) {
        .worker => cfg.unit_hp.worker,
        .soldier => cfg.unit_hp.soldier,
    };
}

test "Unit.pos returns coordinates" {
    const u = Unit{ .x = 7, .y = 12, .kind = .worker, .owner = .player, .hp = 50 };
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
    var u = Unit{ .x = 5, .y = 5, .kind = .worker, .owner = .player, .hp = 50, .state = .moving, .path = path_buf, .path_len = 2, .path_idx = 0 };
    u.step();
    try std.testing.expectEqual(@as(usize, 6), u.x);
    try std.testing.expectEqual(UnitState.moving, u.state);
    u.step();
    try std.testing.expectEqual(@as(usize, 7), u.x);
    try std.testing.expectEqual(UnitState.idle, u.state);
    try std.testing.expectEqual(@as(usize, 0), u.path_len);
}

test "Unit.step on idle does nothing" {
    var u = Unit{ .x = 5, .y = 5, .kind = .worker, .owner = .player, .hp = 50, .state = .idle };
    u.step();
    try std.testing.expectEqual(@as(usize, 5), u.x);
}

test "UnitKind.glyph all lowercase" {
    const cfg = config.default();
    try std.testing.expectEqualStrings("w", UnitKind.worker.glyph(&cfg));
    try std.testing.expectEqualStrings("s", UnitKind.soldier.glyph(&cfg));
}

test "max_hp positive" {
    const cfg = config.default();
    try std.testing.expect(max_hp(.worker, &cfg) > 0);
    try std.testing.expect(max_hp(.soldier, &cfg) > 0);
    try std.testing.expect(max_hp(.soldier, &cfg) > max_hp(.worker, &cfg));
}

test "Owner has three variants" {
    try std.testing.expectEqual(@as(usize, 3), @typeInfo(Owner).@"enum".fields.len);
}

test "Unit default state is idle" {
    const u = Unit{ .x = 0, .y = 0, .kind = .worker, .owner = .player, .hp = 50 };
    try std.testing.expectEqual(UnitState.idle, u.state);
}

test "Unit.step path end resets state" {
    const allocator = std.testing.allocator;
    var path_buf = try allocator.alloc(Pos, 1);
    defer allocator.free(path_buf);
    path_buf[0] = .{ .x = 6, .y = 5 };
    var u = Unit{ .x = 5, .y = 5, .kind = .worker, .owner = .player, .hp = 50, .state = .moving, .path = path_buf, .path_len = 1, .path_idx = 0 };
    u.step();
    try std.testing.expectEqual(UnitState.idle, u.state);
    try std.testing.expectEqual(@as(usize, 0), u.path_len);
    try std.testing.expectEqual(@as(usize, 0), u.path_idx);
}

test "UnitKind.glyph is lowercase" {
    const cfg = config.default();
    const kinds = [_]UnitKind{ .worker, .soldier };
    for (kinds) |k| {
        const g = k.glyph(&cfg);
        try std.testing.expect(g.len == 1);
        try std.testing.expect(g[0] >= 'a' and g[0] <= 'z');
    }
}
