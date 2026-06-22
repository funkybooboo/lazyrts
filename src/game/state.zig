const std = @import("std");
const map = @import("map.zig");
const unit = @import("../units/unit.zig");
const building = @import("../buildings/building.zig");
const wildlife = @import("../resources/wildlife.zig");
const movement = @import("movement.zig");
const config = @import("../config.zig");
const time = @import("../lib/time.zig");
const coords = @import("../lib/coords.zig");
const lib_spatial = @import("../lib/spatial.zig");
const queries = @import("queries.zig");
const economy = @import("economy.zig");
const selection = @import("selection.zig");
const spawning = @import("spawning.zig");
const tick_mod = @import("tick.zig");

pub const MAX_SELECT: usize = selection.MAX_SELECT;

pub const State = struct {
    allocator: std.mem.Allocator,
    cursor_x: usize = 0,
    cursor_y: usize = 0,
    quit: bool = false,
    world: map.GameMap,
    units: []unit.Unit,
    unit_count: usize = 0,
    buildings: []building.Building,
    building_count: usize = 0,
    wildlife: []wildlife.Wildlife,
    wildlife_count: usize = 0,
    selected: [MAX_SELECT]usize = @splat(0),
    selected_count: usize = 0,
    selected_building: ?usize = null,
    food: u32 = 0,
    wood: u32 = 0,
    coord_mode: bool = false,
    coord_buf: [5]u8 = @splat(0),
    coord_len: usize = 0,
    gather_mode: bool = false,
    help_mode: bool = false,
    tick_count: usize = 0,
    cfg: *const config.Config,

    pub fn init(allocator: std.mem.Allocator, seed: u64, term_w: u16, term_h: u16, cfg: *const config.Config) !State {
        const term_width: usize = if (term_w < cfg.map_dims.min_term_width) cfg.map_dims.default_width else term_w;
        const term_height: usize = if (term_h < cfg.map_dims.min_term_height) cfg.map_dims.default_height else term_h;

        const map_w: u16 = if (term_width > cfg.ui.label_width) @intCast(term_width - cfg.ui.label_width) else 10;
        const header_h: u16 = coords.headerHeight(map_w);
        const map_area_h = term_height -| cfg.ui.drawer_height -| header_h;
        const map_h: u16 = if (map_area_h > 0) @intCast(map_area_h) else 10;

        const world = try map.GameMap.init(allocator, seed, map_w, map_h, cfg);

        const units = try allocator.alloc(unit.Unit, cfg.entity_limits.max_units);
        errdefer allocator.free(units);
        const buildings = try allocator.alloc(building.Building, cfg.entity_limits.max_buildings);
        errdefer allocator.free(buildings);
        const wildlife_arr = try allocator.alloc(wildlife.Wildlife, cfg.entity_limits.max_wildlife);
        errdefer allocator.free(wildlife_arr);

        var s: State = .{
            .allocator = allocator,
            .world = world,
            .units = units,
            .buildings = buildings,
            .wildlife = wildlife_arr,
            .cfg = cfg,
        };

        for (s.units) |*u| {
            u.* = .{
                .x = 0,
                .y = 0,
                .variant = .worker,
                .owner = .player,
                .hp = 0,
                .state = .idle,
                .path = &[_]coords.Pos{},
                .path_len = 0,
                .path_idx = 0,
            };
        }

        try spawning.initStartingBuildings(&s);
        try spawning.initStartingWorkers(&s);
        try spawning.allocateUnitPaths(&s);
        try spawning.placeStartingFarm(&s);

        s.food = s.cfg.starting_food;
        s.wood = s.cfg.starting_wood;

        selection.selectSingle(s.unitSelection(), 0);
        spawning.spawnDeer(&s);

        s.cursor_x = s.world.player_tc_x;
        s.cursor_y = s.world.player_tc_y;

        return s;
    }

    pub fn deinit(self: *State) void {
        for (0..self.unit_count) |i| {
            self.allocator.free(self.units[i].path);
        }
        self.allocator.free(self.units);
        self.allocator.free(self.buildings);
        self.allocator.free(self.wildlife);
        self.world.deinit(self.allocator);
    }

    pub fn spatialCtx(self: *const State) queries.Ctx {
        return .{
            .units = self.units[0..self.unit_count],
            .buildings = self.buildings[0..self.building_count],
            .wildlife = self.wildlife[0..self.wildlife_count],
        };
    }

    pub fn unitSelection(self: *State) selection.Ctx {
        return .{
            .selected = &self.selected,
            .selected_count = &self.selected_count,
            .selected_building = &self.selected_building,
            .units = self.units[0..self.unit_count],
        };
    }

    pub fn buildingSelection(self: *State) selection.BuildingCtx {
        return .{
            .selected_building = &self.selected_building,
            .selected_count = &self.selected_count,
            .buildings = self.buildings[0..self.building_count],
        };
    }

    pub fn selectView(self: *const State) selection.View {
        return .{ .selected = &self.selected, .count = self.selected_count };
    }

    pub fn buildingView(self: *const State) selection.BuildingView {
        return .{ .building = self.selected_building, .buildings = self.buildings[0..self.building_count] };
    }
};

pub fn gatherAtCursor(s: *State) void {
    const target = coords.Pos{ .x = s.cursor_x, .y = s.cursor_y };
    if (s.selected_count == 0) return;
    for (0..s.selected_count) |si| {
        const i = s.selected[si];
        _ = economy.startGatherAt(s, i, target);
    }
}

pub fn gatherNearest(s: *State, kind: economy.GatherKind) void {
    if (s.selected_count == 0) return;
    for (0..s.selected_count) |si| {
        const i = s.selected[si];
        _ = economy.startGatherNearest(s, i, kind);
    }
}

pub fn resowSelected(s: *State) bool {
    if (s.selected_building) |bi| {
        return economy.resowFarm(s, bi);
    }
    const bi = lib_spatial.indexOfAt((s.spatialCtx()).buildings, s.cursor_x, s.cursor_y) orelse return false;
    return economy.resowFarm(s, bi);
}

pub fn playerTc(s: *const State) ?coords.Pos {
    const Pred = struct {
        fn ok(b: building.Building) bool {
            return b.kind() == .town_center and b.owner == .player;
        }
    };
    const i = lib_spatial.findFirstWhere(s.buildings[0..s.building_count], Pred.ok) orelse return null;
    return .{ .x = s.buildings[i].x, .y = s.buildings[i].y };
}

pub fn playerPop(s: *const State) usize {
    const Pred = struct {
        fn ok(u: unit.Unit) bool {
            return u.owner == .player;
        }
    };
    return lib_spatial.countWhere(s.units[0..s.unit_count], Pred.ok);
}

pub fn playerPopCap(s: *const State) usize {
    const Pred = struct {
        fn ok(b: building.Building) bool {
            return b.owner == .player and b.isComplete();
        }
    };
    const PopHousing = struct {
        fn housing(cfg: *const config.Config, b: building.Building) usize {
            return b.popHousing(cfg);
        }
    };
    return lib_spatial.sumWhere(
        s.buildings[0..s.building_count],
        s.cfg,
        PopHousing.housing,
        Pred.ok,
    );
}

pub fn playerUnitCounts(s: *const State) struct { workers: usize, soldiers: usize } {
    var worker_count: usize = 0;
    var soldier_count: usize = 0;
    for (0..s.unit_count) |i| {
        if (s.units[i].owner == .player) {
            switch (s.units[i].variant) {
                .worker => worker_count += 1,
                .soldier => soldier_count += 1,
            }
        }
    }
    return .{ .workers = worker_count, .soldiers = soldier_count };
}

pub fn elapsedSeconds(s: *const State) usize {
    return time.ticksToSeconds(s.tick_count, s.cfg.tick_rate);
}

test "playerTc returns player town center position" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const tc = playerTc(&s).?;
    try std.testing.expectEqual(@as(usize, s.world.player_tc_x), tc.x);
    try std.testing.expectEqual(@as(usize, s.world.player_tc_y), tc.y);
}

test "playerTc returns null with no player TC" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.buildings[0].owner = .enemy;
    s.buildings[1].owner = .enemy;
    try std.testing.expect(playerTc(&s) == null);
}

test "playerPop counts player units" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    try std.testing.expectEqual(@as(usize, 2), playerPop(&s));
}

test "playerPopCap counts from buildings" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    try std.testing.expectEqual(@as(usize, 5), playerPopCap(&s));
}

test "playerPopCap ignores incomplete buildings" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.buildings[0].build_progress = 50;
    try std.testing.expectEqual(@as(usize, 0), playerPopCap(&s));
}

test "map dimensions account for labels and drawer" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    const s = try State.init(allocator, 42, 120, 50, &cfg);
    defer {
        var mut_s = s;
        mut_s.deinit();
    }
    try std.testing.expect(s.world.width > 0);
    try std.testing.expect(s.world.height > 0);
    try std.testing.expect(s.world.width < 120);
    try std.testing.expect(s.world.height < 50);
}

test "spatialCtx provides correct slices" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    const ctx = s.spatialCtx();
    try std.testing.expectEqual(s.unit_count, ctx.units.len);
    try std.testing.expectEqual(s.building_count, ctx.buildings.len);
    try std.testing.expectEqual(s.wildlife_count, ctx.wildlife.len);
}
