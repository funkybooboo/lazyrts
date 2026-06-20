const std = @import("std");
const config = @import("config.zig");

pub const Pos = struct { x: usize, y: usize };

pub const Owner = enum(u2) { player, enemy, neutral };

pub const UnitKind = enum {
    worker,
    soldier,
    deer,

    pub fn glyph(self: UnitKind, cfg: *const config.Config) []const u8 {
        return switch (self) {
            .worker => cfg.glyphs.worker,
            .soldier => cfg.glyphs.soldier,
            .deer => cfg.glyphs.deer,
        };
    }
};

pub const BuildingKind = enum {
    town_center,
    house,
    barracks,
    farm,

    pub fn glyph(self: BuildingKind, cfg: *const config.Config) []const u8 {
        return switch (self) {
            .town_center => cfg.glyphs.town_center,
            .house => cfg.glyphs.house,
            .barracks => cfg.glyphs.barracks,
            .farm => cfg.glyphs.farm,
        };
    }

    pub fn label(self: BuildingKind, cfg: *const config.Config) []const u8 {
        return switch (self) {
            .town_center => cfg.labels.town_center,
            .house => cfg.labels.house,
            .barracks => cfg.labels.barracks,
            .farm => cfg.labels.farm,
        };
    }
};

pub const UnitState = enum { idle, moving };

pub const BUILD_COMPLETE_PERCENT: u8 = 100;

pub fn unit_max_hp(kind: UnitKind, cfg: *const config.Config) u16 {
    return switch (kind) {
        .worker => cfg.unit_hp.worker,
        .soldier => cfg.unit_hp.soldier,
        .deer => cfg.unit_hp.deer,
    };
}

pub fn building_max_hp(kind: BuildingKind, cfg: *const config.Config) u16 {
    return switch (kind) {
        .town_center => cfg.building_hp.town_center,
        .house => cfg.building_hp.house,
        .barracks => cfg.building_hp.barracks,
        .farm => cfg.building_hp.farm,
    };
}

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

    pub fn pos(self: *const Unit) Pos {
        return .{ .x = self.x, .y = self.y };
    }

    pub fn step(self: *Unit) void {
        if (self.state != .moving) return;
        if (self.path_idx >= self.path_len) return;
        self.x = self.path[self.path_idx].x;
        self.y = self.path[self.path_idx].y;
        self.path_idx += 1;
        if (self.path_idx >= self.path_len) {
            self.state = .idle;
            self.path_len = 0;
            self.path_idx = 0;
        }
    }
};

pub const Building = struct {
    x: usize,
    y: usize,
    kind: BuildingKind,
    owner: Owner,
    hp: u16,
    build_progress: u8 = 100,

    pub fn is_complete(self: *const Building) bool {
        return self.build_progress >= BUILD_COMPLETE_PERCENT;
    }
};

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
    try std.testing.expectEqualStrings("d", UnitKind.deer.glyph(&cfg));
}

test "unit_max_hp positive" {
    const cfg = config.default();
    try std.testing.expect(unit_max_hp(.worker, &cfg) > 0);
    try std.testing.expect(unit_max_hp(.soldier, &cfg) > 0);
    try std.testing.expect(unit_max_hp(.deer, &cfg) > 0);
    try std.testing.expect(unit_max_hp(.soldier, &cfg) > unit_max_hp(.worker, &cfg));
}

test "BuildingKind.glyph all uppercase" {
    const cfg = config.default();
    try std.testing.expectEqualStrings("C", BuildingKind.town_center.glyph(&cfg));
    try std.testing.expectEqualStrings("H", BuildingKind.house.glyph(&cfg));
    try std.testing.expectEqualStrings("B", BuildingKind.barracks.glyph(&cfg));
    try std.testing.expectEqualStrings("F", BuildingKind.farm.glyph(&cfg));
}

test "building_max_hp positive" {
    const cfg = config.default();
    try std.testing.expect(building_max_hp(.town_center, &cfg) > 0);
    try std.testing.expect(building_max_hp(.town_center, &cfg) > building_max_hp(.house, &cfg));
}

test "BuildingKind.label non-empty" {
    const cfg = config.default();
    try std.testing.expect(BuildingKind.town_center.label(&cfg).len > 0);
    try std.testing.expect(BuildingKind.house.label(&cfg).len > 0);
    try std.testing.expect(BuildingKind.barracks.label(&cfg).len > 0);
    try std.testing.expect(BuildingKind.farm.label(&cfg).len > 0);
}

test "Building.is_complete" {
    const b1 = Building{ .x = 0, .y = 0, .kind = .house, .owner = .player, .hp = 200, .build_progress = 100 };
    const b2 = Building{ .x = 0, .y = 0, .kind = .house, .owner = .player, .hp = 200, .build_progress = 50 };
    try std.testing.expect(b1.is_complete());
    try std.testing.expect(!b2.is_complete());
}

test "UnitKind.glyph is lowercase" {
    const cfg = config.default();
    const kinds = [_]UnitKind{ .worker, .soldier, .deer };
    for (kinds) |k| {
        const g = k.glyph(&cfg);
        try std.testing.expect(g.len == 1);
        try std.testing.expect(g[0] >= 'a' and g[0] <= 'z');
    }
}

test "BuildingKind.glyph is uppercase" {
    const cfg = config.default();
    const kinds = [_]BuildingKind{ .town_center, .house, .barracks, .farm };
    for (kinds) |k| {
        const g = k.glyph(&cfg);
        try std.testing.expect(g.len == 1);
        try std.testing.expect(g[0] >= 'A' and g[0] <= 'Z');
    }
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
