const std = @import("std");
const state_mod = @import("state.zig");
const unit = @import("../units/unit.zig");
const building = @import("../buildings/building.zig");
const config = @import("../config.zig");
const spawning = @import("spawning.zig");
const lib_spatial = @import("../lib/spatial.zig");
const notify = @import("notify.zig");

pub const QUEUE_DEPTH: usize = 5;
pub const MAX_QUEUES: usize = 16;

pub const Queue = struct {
    building_idx: usize,
    items: [QUEUE_DEPTH]unit.UnitKind = undefined,
    head: usize = 0,
    count: usize = 0,
    active_ticks: u32 = 0,

    pub fn itemAt(self: *const Queue, i: usize) unit.UnitKind {
        return self.items[(self.head + i) % QUEUE_DEPTH];
    }

    pub fn isFull(self: *const Queue) bool {
        return self.count >= QUEUE_DEPTH;
    }

    pub fn pendingCount(self: *const Queue) usize {
        return self.count;
    }
};

pub fn findQueue(s: *const state_mod.State, building_idx: usize) ?usize {
    for (0..s.training_queue_count) |i| {
        if (s.training_queues[i].building_idx == building_idx) return i;
    }
    return null;
}

pub fn trainTicks(kind: unit.UnitKind, cfg: *const config.Config) u32 {
    return switch (kind) {
        .worker => cfg.training.worker_ticks,
        .soldier => cfg.training.soldier_ticks,
    };
}

pub fn canEnqueue(s: *const state_mod.State, building_idx: usize, kind: unit.UnitKind) bool {
    const b = &s.buildings[building_idx];
    if (!b.isComplete()) return false;
    if (b.owner != .player) return false;

    switch (kind) {
        .worker => if (b.kind() != .town_center) return false,
        .soldier => if (b.kind() != .barracks) return false,
    }

    if (!canAfford(s, kind)) return false;

    if (findQueue(s, building_idx)) |qi| {
        if (s.training_queues[qi].isFull()) return false;
    }

    if (state_mod.playerPop(s) + countPending(s) >= state_mod.playerPopCap(s)) return false;

    return true;
}

fn canAfford(s: *const state_mod.State, kind: unit.UnitKind) bool {
    switch (kind) {
        .worker => return s.food >= s.cfg.training.worker_food_cost,
        .soldier => return s.food >= s.cfg.training.soldier_food_cost and s.wood >= s.cfg.training.soldier_wood_cost,
    }
}

fn countPending(s: *const state_mod.State) usize {
    var total: usize = 0;
    for (0..s.training_queue_count) |i| {
        total += s.training_queues[i].count;
    }
    return total;
}

pub fn enqueue(s: *state_mod.State, building_idx: usize, kind: unit.UnitKind) bool {
    const b = &s.buildings[building_idx];
    if (!b.isComplete()) {
        notify.push(s, "Building incomplete", .bad);
        return false;
    }
    if (b.owner != .player) return false;

    switch (kind) {
        .worker => if (b.kind() != .town_center) return false,
        .soldier => if (b.kind() != .barracks) return false,
    }

    if (!canAfford(s, kind)) {
        const msg = switch (kind) {
            .worker => "Need 50 food",
            .soldier => "Need 40 food, 20 wood",
        };
        notify.push(s, msg, .bad);
        return false;
    }

    if (findQueue(s, building_idx)) |qi| {
        if (s.training_queues[qi].isFull()) {
            notify.push(s, "Queue full", .bad);
            return false;
        }
    }

    if (state_mod.playerPop(s) + countPending(s) >= state_mod.playerPopCap(s)) {
        notify.push(s, "Need more housing", .bad);
        return false;
    }

    deductCost(s, kind);

    const qi = findQueue(s, building_idx) orelse blk: {
        if (s.training_queue_count >= MAX_QUEUES) return false;
        const idx = s.training_queue_count;
        s.training_queues[idx] = .{ .building_idx = building_idx };
        s.training_queue_count += 1;
        break :blk idx;
    };

    const q = &s.training_queues[qi];
    const slot = (q.head + q.count) % QUEUE_DEPTH;
    q.items[slot] = kind;
    q.count += 1;

    if (q.active_ticks == 0) {
        q.active_ticks = trainTicks(kind, s.cfg);
    }

    const label = switch (kind) {
        .worker => "Worker",
        .soldier => "Soldier",
    };
    notify.push(s, label, .good);

    return true;
}

fn deductCost(s: *state_mod.State, kind: unit.UnitKind) void {
    switch (kind) {
        .worker => s.food -= s.cfg.training.worker_food_cost,
        .soldier => {
            s.food -= s.cfg.training.soldier_food_cost;
            s.wood -= s.cfg.training.soldier_wood_cost;
        },
    }
}

pub fn tickQueues(s: *state_mod.State) void {
    var i: usize = 0;
    while (i < s.training_queue_count) {
        const q = &s.training_queues[i];
        if (q.active_ticks > 0) {
            q.active_ticks -= 1;
            if (q.active_ticks == 0) {
                const kind = q.itemAt(0);
                const b = &s.buildings[q.building_idx];
                _ = spawning.spawnUnit(s, kind, .player, b.x, b.y);
                q.head = (q.head + 1) % QUEUE_DEPTH;
                q.count -= 1;

                if (q.count > 0) {
                    q.active_ticks = trainTicks(q.itemAt(0), s.cfg);
                }
            }
        }

        if (q.count == 0) {
            if (i < s.training_queue_count - 1) {
                s.training_queues[i] = s.training_queues[s.training_queue_count - 1];
            }
            s.training_queue_count -= 1;
            continue;
        }

        i += 1;
    }
}

pub fn findBuildingForTraining(s: *const state_mod.State, kind: unit.UnitKind) ?usize {
    const target_kind: building.Kind = switch (kind) {
        .worker => .town_center,
        .soldier => .barracks,
    };

    if (s.selected_building) |bi| {
        if (bi < s.building_count) {
            const b = &s.buildings[bi];
            if (b.kind() == target_kind and b.owner == .player and b.isComplete()) {
                return bi;
            }
        }
    }

    for (0..s.building_count) |i| {
        const b = &s.buildings[i];
        if (b.kind() == target_kind and b.owner == .player and b.isComplete()) {
            return i;
        }
    }

    return null;
}

test "canEnqueue checks building type" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state_mod.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();

    try std.testing.expect(canEnqueue(&s, 0, .worker));
    try std.testing.expect(!canEnqueue(&s, 0, .soldier));
}

test "enqueue adds to queue" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state_mod.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();

    try std.testing.expect(enqueue(&s, 0, .worker));
    try std.testing.expectEqual(@as(usize, 1), s.training_queue_count);
    try std.testing.expectEqual(@as(usize, 1), s.training_queues[0].count);
    try std.testing.expectEqual(unit.UnitKind.worker, s.training_queues[0].itemAt(0));
}

test "enqueue multiple units" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state_mod.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();

    try std.testing.expect(enqueue(&s, 0, .worker));
    try std.testing.expect(enqueue(&s, 0, .worker));
    try std.testing.expect(enqueue(&s, 0, .worker));

    try std.testing.expectEqual(@as(usize, 1), s.training_queue_count);
    try std.testing.expectEqual(@as(usize, 3), s.training_queues[0].count);
}

test "tickQueues spawns unit when complete" {
    const allocator = std.testing.allocator;
    var cfg = config.default();
    cfg.training.worker_ticks = 2;
    var s = try state_mod.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();

    const before = s.unit_count;
    try std.testing.expect(enqueue(&s, 0, .worker));

    tickQueues(&s);
    try std.testing.expectEqual(@as(u32, 1), s.training_queues[0].active_ticks);

    tickQueues(&s);
    try std.testing.expectEqual(@as(u32, 0), s.training_queues[0].active_ticks);
    try std.testing.expectEqual(@as(usize, 0), s.training_queue_count);
    try std.testing.expectEqual(before + 1, s.unit_count);
}

test "findBuildingForTraining uses selected building" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state_mod.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();

    const bi = findBuildingForTraining(&s, .worker).?;
    try std.testing.expectEqual(@as(usize, 0), bi);
}
