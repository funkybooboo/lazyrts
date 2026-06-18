const std = @import("std");

pub const Pos = struct { x: usize, y: usize };

pub const Owner = enum(u2) { player, enemy, neutral };

pub const UnitKind = enum {
    worker,
    soldier,
    deer,

    pub fn glyph(self: UnitKind) []const u8 {
        return switch (self) {
            .worker => "w",
            .soldier => "s",
            .deer => "d",
        };
    }

    pub fn max_hp(self: UnitKind) u16 {
        return switch (self) {
            .worker => 50,
            .soldier => 100,
            .deer => 25,
        };
    }
};

pub const BuildingKind = enum {
    town_center,
    house,
    barracks,
    farm,

    pub fn glyph(self: BuildingKind) []const u8 {
        return switch (self) {
            .town_center => "C",
            .house => "H",
            .barracks => "B",
            .farm => "F",
        };
    }

    pub fn max_hp(self: BuildingKind) u16 {
        return switch (self) {
            .town_center => 500,
            .house => 200,
            .barracks => 300,
            .farm => 100,
        };
    }

    pub fn label(self: BuildingKind) []const u8 {
        return switch (self) {
            .town_center => "TC",
            .house => "House",
            .barracks => "Barracks",
            .farm => "Farm",
        };
    }
};

pub const UnitState = enum { idle, moving };

pub const MAX_PATH: usize = 256;
pub const MAX_UNITS: usize = 128;
pub const MAX_BUILDINGS: usize = 32;

pub const Unit = struct {
    x: usize,
    y: usize,
    kind: UnitKind,
    owner: Owner,
    hp: u16,
    state: UnitState = .idle,
    path: [MAX_PATH]Pos = undefined,
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
        return self.build_progress >= 100;
    }
};

test "Unit.pos returns coordinates" {
    const u = Unit{ .x = 7, .y = 12, .kind = .worker, .owner = .player, .hp = 50 };
    const p = u.pos();
    try std.testing.expectEqual(@as(usize, 7), p.x);
    try std.testing.expectEqual(@as(usize, 12), p.y);
}

test "Unit.step moves along path" {
    var u = Unit{ .x = 5, .y = 5, .kind = .worker, .owner = .player, .hp = 50, .state = .moving };
    u.path[0] = .{ .x = 6, .y = 5 };
    u.path[1] = .{ .x = 7, .y = 5 };
    u.path_len = 2;
    u.path_idx = 0;
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
    try std.testing.expectEqualStrings("w", UnitKind.worker.glyph());
    try std.testing.expectEqualStrings("s", UnitKind.soldier.glyph());
    try std.testing.expectEqualStrings("d", UnitKind.deer.glyph());
}

test "UnitKind.max_hp positive" {
    try std.testing.expect(UnitKind.worker.max_hp() > 0);
    try std.testing.expect(UnitKind.soldier.max_hp() > 0);
    try std.testing.expect(UnitKind.deer.max_hp() > 0);
    try std.testing.expect(UnitKind.soldier.max_hp() > UnitKind.worker.max_hp());
}

test "BuildingKind.glyph all uppercase" {
    try std.testing.expectEqualStrings("C", BuildingKind.town_center.glyph());
    try std.testing.expectEqualStrings("H", BuildingKind.house.glyph());
    try std.testing.expectEqualStrings("B", BuildingKind.barracks.glyph());
    try std.testing.expectEqualStrings("F", BuildingKind.farm.glyph());
}

test "BuildingKind.max_hp positive" {
    try std.testing.expect(BuildingKind.town_center.max_hp() > 0);
    try std.testing.expect(BuildingKind.town_center.max_hp() > BuildingKind.house.max_hp());
}

test "BuildingKind.label non-empty" {
    try std.testing.expect(BuildingKind.town_center.label().len > 0);
    try std.testing.expect(BuildingKind.house.label().len > 0);
    try std.testing.expect(BuildingKind.barracks.label().len > 0);
    try std.testing.expect(BuildingKind.farm.label().len > 0);
}

test "Building.is_complete" {
    const b1 = Building{ .x = 0, .y = 0, .kind = .house, .owner = .player, .hp = 200, .build_progress = 100 };
    const b2 = Building{ .x = 0, .y = 0, .kind = .house, .owner = .player, .hp = 200, .build_progress = 50 };
    try std.testing.expect(b1.is_complete());
    try std.testing.expect(!b2.is_complete());
}

test "UnitKind.glyph is lowercase" {
    const kinds = [_]UnitKind{ .worker, .soldier, .deer };
    for (kinds) |k| {
        const g = k.glyph();
        try std.testing.expect(g.len == 1);
        try std.testing.expect(g[0] >= 'a' and g[0] <= 'z');
    }
}

test "BuildingKind.glyph is uppercase" {
    const kinds = [_]BuildingKind{ .town_center, .house, .barracks, .farm };
    for (kinds) |k| {
        const g = k.glyph();
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
    var u = Unit{ .x = 5, .y = 5, .kind = .worker, .owner = .player, .hp = 50, .state = .moving };
    u.path[0] = .{ .x = 6, .y = 5 };
    u.path_len = 1;
    u.path_idx = 0;
    u.step();
    try std.testing.expectEqual(UnitState.idle, u.state);
    try std.testing.expectEqual(@as(usize, 0), u.path_len);
    try std.testing.expectEqual(@as(usize, 0), u.path_idx);
}
