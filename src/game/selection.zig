const std = @import("std");
const unit = @import("../units/unit.zig");
const building = @import("../buildings/building.zig");
const config = @import("../config.zig");

pub const MAX_SELECT: usize = 128;

pub const Ctx = struct {
    selected: []usize,
    selected_count: *usize,
    selected_building: *?usize,
    units: []const unit.Unit,
};

pub const View = struct {
    selected: []const usize,
    count: usize,
};

pub const BuildingCtx = struct {
    selected_building: *?usize,
    selected_count: *usize,
    buildings: []const building.Building,
};

pub const BuildingView = struct {
    building: ?usize,
    buildings: []const building.Building,
};

pub fn selectSingle(c: Ctx, idx: usize) void {
    c.selected[0] = idx;
    c.selected_count.* = 1;
    c.selected_building.* = null;
}

pub fn selectClear(c: Ctx) void {
    c.selected_count.* = 0;
    c.selected_building.* = null;
}

pub fn hasSelected(c: Ctx, idx: usize) bool {
    return isUnitSelected(c.selected[0..c.selected_count.*], idx);
}

pub fn primarySelected(c: Ctx) ?usize {
    if (c.selected_count.* == 0) return null;
    return c.selected[0];
}

pub fn viewHasSelected(v: View, idx: usize) bool {
    return isUnitSelected(v.selected[0..v.count], idx);
}

pub fn viewPrimarySelected(v: View) ?usize {
    if (v.count == 0) return null;
    return v.selected[0];
}

pub fn viewHasBuildingSelected(v: BuildingView, idx: usize) bool {
    if (v.building) |b| return b == idx;
    return false;
}

pub fn selectAdd(c: Ctx, idx: usize) void {
    if (idx >= c.units.len) return;
    if (c.units[idx].owner != .player) return;
    if (isUnitSelected(c.selected[0..c.selected_count.*], idx)) return;
    if (c.selected_count.* >= MAX_SELECT) return;
    c.selected[c.selected_count.*] = idx;
    c.selected_count.* += 1;
    c.selected_building.* = null;
}

pub fn selectNext(c: Ctx) void {
    cycle(c, 1);
}

pub fn selectPrev(c: Ctx) void {
    cycle(c, 0);
}

fn cycle(c: Ctx, forward: usize) void {
    const n = c.units.len;
    if (n == 0) {
        c.selected_count.* = 0;
        return;
    }
    const start: usize = if (primarySelected(c)) |sel|
        switch (forward) {
            1 => (sel + 1) % n,
            else => if (sel == 0) n - 1 else sel - 1,
        }
    else
        switch (forward) {
            1 => 0,
            else => n - 1,
        };
    var i: usize = start;
    while (true) {
        if (c.units[i].owner == .player) {
            selectSingle(c, i);
            return;
        }
        i = switch (forward) {
            1 => (i + 1) % n,
            else => if (i == 0) n - 1 else i - 1,
        };
        if (i == start) break;
    }
    c.selected_count.* = 0;
}

pub fn selectIdleWorkers(c: Ctx) void {
    selectMatching(c, false);
}

pub fn selectAllWorkers(c: Ctx) void {
    selectMatching(c, true);
}

fn selectMatching(c: Ctx, include_busy: bool) void {
    c.selected_count.* = 0;
    c.selected_building.* = null;
    for (c.units, 0..) |u, i| {
        if (c.selected_count.* >= MAX_SELECT) break;
        if (u.owner != .player or u.kind() != .worker) continue;
        if (!include_busy and u.state != .idle) continue;
        c.selected[c.selected_count.*] = i;
        c.selected_count.* += 1;
    }
}

pub fn selectNextBuilding(c: BuildingCtx) void {
    cycleBuilding(c, 1);
}

pub fn selectPrevBuilding(c: BuildingCtx) void {
    cycleBuilding(c, 0);
}

fn cycleBuilding(c: BuildingCtx, forward: usize) void {
    const n = c.buildings.len;
    if (n == 0) {
        c.selected_building.* = null;
        return;
    }
    const start: usize = if (c.selected_building.*) |sel|
        switch (forward) {
            1 => (sel + 1) % n,
            else => if (sel == 0) n - 1 else sel - 1,
        }
    else
        switch (forward) {
            1 => 0,
            else => n - 1,
        };
    var i: usize = start;
    while (true) {
        if (c.buildings[i].owner == .player) {
            c.selected_building.* = i;
            c.selected_count.* = 0;
            return;
        }
        i = switch (forward) {
            1 => (i + 1) % n,
            else => if (i == 0) n - 1 else i - 1,
        };
        if (i == start) break;
    }
    c.selected_building.* = null;
}

fn isUnitSelected(selected: []const usize, idx: usize) bool {
    for (selected) |s| {
        if (s == idx) return true;
    }
    return false;
}

test {
    const std_testing = std.testing;
    const cfg = config.default();
    const allocator = std_testing.allocator;
    const state = @import("state.zig");
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();

    const c = s.unitSelection();
    selectClear(c);
    try std_testing.expect(primarySelected(c) == null);

    selectSingle(c, 0);
    try std_testing.expectEqual(@as(?usize, 0), primarySelected(c));
    try std_testing.expect(hasSelected(c, 0));
    try std_testing.expect(!hasSelected(c, 1));

    const first = primarySelected(c).?;
    selectNext(c);
    const second = primarySelected(c).?;
    try std_testing.expect(first != second);

    s.units[0].state = .moving;
    selectIdleWorkers(c);
    for (0..c.selected_count.*) |i| {
        try std_testing.expectEqual(unit.UnitActivity.idle, s.units[c.selected[i]].state);
        try std_testing.expectEqual(unit.UnitKind.worker, s.units[c.selected[i]].kind());
    }

    selectAllWorkers(c);
    var expected: usize = 0;
    for (s.units[0..s.unit_count]) |u| {
        if (u.owner == .player and u.kind() == .worker) expected += 1;
    }
    try std_testing.expectEqual(expected, c.selected_count.*);

    var player_idxs: [8]usize = undefined;
    var pn: usize = 0;
    for (s.units[0..s.unit_count], 0..) |u, i| {
        if (u.owner == .player and pn < 8) {
            player_idxs[pn] = i;
            pn += 1;
        }
    }
    if (pn >= 2) {
        selectSingle(c, player_idxs[0]);
        selectAdd(c, player_idxs[1]);
        try std_testing.expectEqual(@as(usize, 2), c.selected_count.*);
        try std_testing.expect(hasSelected(c, player_idxs[1]));
    }

    const bc = s.buildingSelection();
    selectNextBuilding(bc);
    const b = bc.selected_building.*.?;
    try std_testing.expectEqual(unit.Owner.player, s.buildings[b].owner);

    for (s.units[0..s.unit_count]) |*u| u.owner = .enemy;
    selectClear(c);
    selectNext(c);
    try std_testing.expect(primarySelected(c) == null);
}