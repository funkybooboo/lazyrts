const std = @import("std");
const unit = @import("../units/unit.zig");
const coords = @import("../lib/coords.zig");
const lib_spatial = @import("../lib/spatial.zig");
const building = @import("../buildings/building.zig");
const wildlife = @import("../resources/wildlife.zig");

pub const Ctx = struct {
    units: []const unit.Unit,
    buildings: []const building.Building,
    wildlife: []const wildlife.Wildlife,
    index: ?*const Index = null,

    pub fn unitAt(self: Ctx, x: usize, y: usize) ?usize {
        if (self.index) |idx| return idx.unitAt(x, y);
        return lib_spatial.indexOfAt(self.units, x, y);
    }
    pub fn buildingAt(self: Ctx, x: usize, y: usize) ?usize {
        if (self.index) |idx| return idx.buildingAt(x, y);
        return lib_spatial.indexOfAt(self.buildings, x, y);
    }
    pub fn wildlifeAt(self: Ctx, x: usize, y: usize) ?usize {
        if (self.index) |idx| return idx.wildlifeAt(x, y);
        return lib_spatial.indexOfAt(self.wildlife, x, y);
    }
};

pub const Index = struct {
    width: usize,
    height: usize,
    unit_at: []?usize,
    building_at: []?usize,
    wildlife_at: []?usize,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, width: usize, height: usize) !Index {
        const n = width * height;
        return .{
            .width = width,
            .height = height,
            .unit_at = try allocator.alloc(?usize, n),
            .building_at = try allocator.alloc(?usize, n),
            .wildlife_at = try allocator.alloc(?usize, n),
            .allocator = allocator,
        };
    }

    pub fn initZeroed(allocator: std.mem.Allocator, width: usize, height: usize) !Index {
        const self = try init(allocator, width, height);
        @memset(self.unit_at, null);
        @memset(self.building_at, null);
        @memset(self.wildlife_at, null);
        return self;
    }

    pub fn putUnit(self: *Index, i: usize, p: coords.Pos) void {
        if (p.x < self.width and p.y < self.height) self.unit_at[p.y * self.width + p.x] = i;
    }
    pub fn putBuilding(self: *Index, i: usize, p: coords.Pos) void {
        if (p.x < self.width and p.y < self.height) self.building_at[p.y * self.width + p.x] = i;
    }
    pub fn putWildlife(self: *Index, i: usize, p: coords.Pos) void {
        if (p.x < self.width and p.y < self.height) self.wildlife_at[p.y * self.width + p.x] = i;
    }

    pub fn deinit(self: *Index) void {
        self.allocator.free(self.unit_at);
        self.allocator.free(self.building_at);
        self.allocator.free(self.wildlife_at);
    }

    pub fn rebuild(self: *Index, units: []const unit.Unit, buildings: []const building.Building, wl: []const wildlife.Wildlife) void {
        @memset(self.unit_at, null);
        @memset(self.building_at, null);
        @memset(self.wildlife_at, null);
        for (units, 0..) |u, i| {
            if (u.y < self.height and u.x < self.width)
                self.unit_at[u.y * self.width + u.x] = i;
        }
        for (buildings, 0..) |b, i| {
            if (b.y < self.height and b.x < self.width)
                self.building_at[b.y * self.width + b.x] = i;
        }
        for (wl, 0..) |w, i| {
            const p = w.pos();
            if (p.y < self.height and p.x < self.width)
                self.wildlife_at[p.y * self.width + p.x] = i;
        }
    }

    pub fn unitAt(self: *const Index, x: usize, y: usize) ?usize {
        if (x >= self.width or y >= self.height) return null;
        return self.unit_at[y * self.width + x];
    }
    pub fn buildingAt(self: *const Index, x: usize, y: usize) ?usize {
        if (x >= self.width or y >= self.height) return null;
        return self.building_at[y * self.width + x];
    }
    pub fn wildlifeAt(self: *const Index, x: usize, y: usize) ?usize {
        if (x >= self.width or y >= self.height) return null;
        return self.wildlife_at[y * self.width + x];
    }
    pub fn occupied(self: *const Index, x: usize, y: usize) bool {
        return self.unitAt(x, y) != null or self.buildingAt(x, y) != null or self.wildlifeAt(x, y) != null;
    }

    pub fn moveUnit(self: *Index, i: usize, old: coords.Pos, new: coords.Pos) void {
        if (old.x == new.x and old.y == new.y) return;
        if (old.x < self.width and old.y < self.height) self.unit_at[old.y * self.width + old.x] = null;
        if (new.x < self.width and new.y < self.height) self.unit_at[new.y * self.width + new.x] = i;
    }

    pub fn removeWildlife(self: *Index, removed_idx: usize, removed_pos: coords.Pos, swapped_pos: ?coords.Pos) void {
        if (removed_pos.x < self.width and removed_pos.y < self.height)
            self.wildlife_at[removed_pos.y * self.width + removed_pos.x] = null;
        if (swapped_pos) |sp| {
            if (sp.x < self.width and sp.y < self.height)
                self.wildlife_at[sp.y * self.width + sp.x] = removed_idx;
        }
    }
};

pub fn occupied(ctx: Ctx, x: usize, y: usize) bool {
    if (ctx.index) |idx| return idx.occupied(x, y);
    return lib_spatial.indexOfAt(ctx.units, x, y) != null or
        lib_spatial.indexOfAt(ctx.buildings, x, y) != null or
        lib_spatial.indexOfAt(ctx.wildlife, x, y) != null;
}

pub fn collectBlocked(ctx: Ctx, out: []coords.Pos, except_unit: ?usize) usize {
    var count: usize = 0;

    count += lib_spatial.collectPositions(ctx.buildings, out[count..]);
    count += lib_spatial.collectPositions(ctx.wildlife, out[count..]);

    for (ctx.units, 0..) |u, i| {
        if (except_unit) |ex| if (i == ex) continue;
        if (count >= out.len) break;
        out[count] = .{ .x = u.x, .y = u.y };
        count += 1;
    }

    return count;
}

test "unitAt finds unit at position" {
    var units = [_]unit.Unit{
        .{ .x = 5, .y = 10, .variant = .worker, .owner = .player, .hp = 100, .state = .idle, .path = &[_]coords.Pos{}, .path_len = 0, .path_idx = 0 },
        .{ .x = 15, .y = 20, .variant = .worker, .owner = .player, .hp = 100, .state = .idle, .path = &[_]coords.Pos{}, .path_len = 0, .path_idx = 0 },
    };
    const ctx: Ctx = .{
        .units = &units,
        .buildings = &[_]building.Building{},
        .wildlife = &[_]wildlife.Wildlife{},
    };
    try std.testing.expectEqual(@as(?usize, 0), lib_spatial.indexOfAt(ctx.units, 5, 10));
    try std.testing.expectEqual(@as(?usize, 1), lib_spatial.indexOfAt(ctx.units, 15, 20));
    try std.testing.expect(lib_spatial.indexOfAt(ctx.units, 0, 0) == null);
}

test "buildingAt finds building at position" {
    var buildings = [_]building.Building{
        .{ .x = 10, .y = 10, .variant = .town_center, .owner = .player, .hp = 1000, .build_progress = 100 },
        .{ .x = 50, .y = 50, .variant = .house, .owner = .player, .hp = 100, .build_progress = 100 },
    };
    const ctx: Ctx = .{
        .units = &[_]unit.Unit{},
        .buildings = &buildings,
        .wildlife = &[_]wildlife.Wildlife{},
    };
    try std.testing.expectEqual(@as(?usize, 0), lib_spatial.indexOfAt(ctx.buildings, 10, 10));
    try std.testing.expectEqual(@as(?usize, 1), lib_spatial.indexOfAt(ctx.buildings, 50, 50));
    try std.testing.expect(lib_spatial.indexOfAt(ctx.buildings, 0, 0) == null);
}

test "wildlifeAt finds wildlife at position" {
    var wildlife_arr = [_]wildlife.Wildlife{
        .{ .deer = .{ .x = 3, .y = 7, .hp = 50 } },
        .{ .deer = .{ .x = 25, .y = 30, .hp = 50 } },
    };
    const ctx: Ctx = .{
        .units = &[_]unit.Unit{},
        .buildings = &[_]building.Building{},
        .wildlife = &wildlife_arr,
    };
    try std.testing.expectEqual(@as(?usize, 0), lib_spatial.indexOfAt(ctx.wildlife, 3, 7));
    try std.testing.expectEqual(@as(?usize, 1), lib_spatial.indexOfAt(ctx.wildlife, 25, 30));
    try std.testing.expect(lib_spatial.indexOfAt(ctx.wildlife, 0, 0) == null);
}

test "wildlifeAtExcept skips specified index" {
    var wildlife_arr = [_]wildlife.Wildlife{
        .{ .deer = .{ .x = 5, .y = 5, .hp = 50 } },
        .{ .deer = .{ .x = 5, .y = 5, .hp = 50 } },
    };
    const ctx: Ctx = .{
        .units = &[_]unit.Unit{},
        .buildings = &[_]building.Building{},
        .wildlife = &wildlife_arr,
    };
    try std.testing.expectEqual(@as(?usize, 0), lib_spatial.indexOfAt(ctx.wildlife, 5, 5));
    try std.testing.expectEqual(@as(?usize, 1), lib_spatial.indexOfAtExcept(ctx.wildlife, 5, 5, 0));
    try std.testing.expectEqual(@as(?usize, 0), lib_spatial.indexOfAtExcept(ctx.wildlife, 5, 5, 1));
}

test "occupied returns true when entity present" {
    var units = [_]unit.Unit{
        .{ .x = 10, .y = 10, .variant = .worker, .owner = .player, .hp = 100, .state = .idle, .path = &[_]coords.Pos{}, .path_len = 0, .path_idx = 0 },
    };
    var buildings = [_]building.Building{
        .{ .x = 20, .y = 20, .variant = .house, .owner = .player, .hp = 100, .build_progress = 100 },
    };
    var wildlife_arr = [_]wildlife.Wildlife{
        .{ .deer = .{ .x = 30, .y = 30, .hp = 50 } },
    };
    const ctx: Ctx = .{
        .units = &units,
        .buildings = &buildings,
        .wildlife = &wildlife_arr,
    };
    try std.testing.expect(occupied(ctx, 10, 10));
    try std.testing.expect(occupied(ctx, 20, 20));
    try std.testing.expect(occupied(ctx, 30, 30));
    try std.testing.expect(!occupied(ctx, 0, 0));
}

test "collectBlocked includes all entities except specified unit" {
    var units = [_]unit.Unit{
        .{ .x = 5, .y = 5, .variant = .worker, .owner = .player, .hp = 100, .state = .idle, .path = &[_]coords.Pos{}, .path_len = 0, .path_idx = 0 },
        .{ .x = 10, .y = 10, .variant = .worker, .owner = .player, .hp = 100, .state = .idle, .path = &[_]coords.Pos{}, .path_len = 0, .path_idx = 0 },
    };
    var buildings = [_]building.Building{
        .{ .x = 15, .y = 15, .variant = .house, .owner = .player, .hp = 100, .build_progress = 100 },
    };
    var wildlife_arr = [_]wildlife.Wildlife{
        .{ .deer = .{ .x = 20, .y = 20, .hp = 50 } },
    };
    const ctx: Ctx = .{
        .units = &units,
        .buildings = &buildings,
        .wildlife = &wildlife_arr,
    };
    var out: [10]coords.Pos = undefined;
    const count = collectBlocked(ctx, &out, 0);
    try std.testing.expectEqual(@as(usize, 3), count);

    const count_all = collectBlocked(ctx, &out, null);
    try std.testing.expectEqual(@as(usize, 4), count_all);
}

test "Index: rebuild and O(1) lookups" {
    const allocator = std.testing.allocator;
    var idx = try Index.initZeroed(allocator, 10, 10);
    defer idx.deinit();

    var units = [_]unit.Unit{
        .{ .x = 3, .y = 4, .variant = .worker, .owner = .player, .hp = 50, .path = &[_]coords.Pos{} },
    };
    var buildings = [_]building.Building{
        .{ .x = 7, .y = 7, .variant = .house, .owner = .player, .hp = 100, .build_progress = 100 },
    };
    var wl = [_]wildlife.Wildlife{
        .{ .deer = .{ .x = 1, .y = 1, .hp = 25 } },
    };
    idx.rebuild(&units, &buildings, &wl);

    try std.testing.expectEqual(@as(?usize, 0), idx.unitAt(3, 4));
    try std.testing.expectEqual(@as(?usize, 0), idx.buildingAt(7, 7));
    try std.testing.expectEqual(@as(?usize, 0), idx.wildlifeAt(1, 1));
    try std.testing.expect(idx.unitAt(3, 5) == null);
    try std.testing.expect(idx.occupied(3, 4));
    try std.testing.expect(!idx.occupied(5, 5));
    try std.testing.expect(idx.unitAt(10, 10) == null); // out of bounds
}

test "Index: moveUnit updates tile" {
    const allocator = std.testing.allocator;
    var idx = try Index.initZeroed(allocator, 10, 10);
    defer idx.deinit();
    idx.putUnit(0, .{ .x = 2, .y = 2 });
    try std.testing.expectEqual(@as(?usize, 0), idx.unitAt(2, 2));
    idx.moveUnit(0, .{ .x = 2, .y = 2 }, .{ .x = 2, .y = 3 });
    try std.testing.expect(idx.unitAt(2, 2) == null);
    try std.testing.expectEqual(@as(?usize, 0), idx.unitAt(2, 3));
}

test "Index: removeWildlife clears and remaps swapped" {
    const allocator = std.testing.allocator;
    var idx = try Index.initZeroed(allocator, 10, 10);
    defer idx.deinit();
    idx.putWildlife(0, .{ .x = 1, .y = 1 });
    idx.putWildlife(2, .{ .x = 5, .y = 5 });
    // remove slot 0, swap slot 2 into 0
    idx.removeWildlife(0, .{ .x = 1, .y = 1 }, .{ .x = 5, .y = 5 });
    try std.testing.expect(idx.wildlifeAt(1, 1) == null);
    try std.testing.expectEqual(@as(?usize, 0), idx.wildlifeAt(5, 5));
}

test "Ctx: index path used when present, linear fallback when null" {
    var units = [_]unit.Unit{
        .{ .x = 3, .y = 4, .variant = .worker, .owner = .player, .hp = 50, .path = &[_]coords.Pos{} },
    };
    const buildings = [_]building.Building{};
    const wl = [_]wildlife.Wildlife{};

    const ctx_no_index: Ctx = .{ .units = &units, .buildings = &buildings, .wildlife = &wl, .index = null };
    try std.testing.expectEqual(@as(?usize, 0), ctx_no_index.unitAt(3, 4));
    try std.testing.expect(ctx_no_index.unitAt(0, 0) == null);

    const allocator = std.testing.allocator;
    var idx = try Index.initZeroed(allocator, 10, 10);
    defer idx.deinit();
    idx.rebuild(&units, &buildings, &wl);
    const ctx_indexed: Ctx = .{ .units = &units, .buildings = &buildings, .wildlife = &wl, .index = &idx };
    try std.testing.expectEqual(@as(?usize, 0), ctx_indexed.unitAt(3, 4));
}
