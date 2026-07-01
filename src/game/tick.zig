const std = @import("std");
const state = @import("state.zig");
const unit = @import("../units/unit.zig");
const coords = @import("../lib/coords.zig");
const lib_spatial = @import("../lib/spatial.zig");
const wildlife = @import("../resources/wildlife.zig");
const economy = @import("economy.zig");
const movement = @import("movement.zig");
const training = @import("training.zig");
const config = @import("../config.zig");
const perf = @import("perf.zig");

const State = state.State;

pub fn tick(s: *State) void {
    s.tick_count += 1;
    s.perf.resetTick();
    s.rebuildSpatialIndex();
    const pf_start = s.path_scratch.find_calls;

    {
        const sec = perf.section(&s.perf, .units);
        defer sec.end();
        for (0..s.unit_count) |i| {
            const u = &s.units[i];
            switch (u.state) {
                .moving => {
                    if (u.path_idx < u.path_len) {
                        const next = u.path[u.path_idx];
                        var blocked = false;
                        const ctx = s.spatialCtx();
                        if (ctx.unitAt(next.x, next.y)) |other| {
                            if (other != i) blocked = true;
                        }
                        if (ctx.buildingAt(next.x, next.y) != null) blocked = true;
                        if (ctx.wildlifeAt(next.x, next.y) != null) blocked = true;

                        if (blocked) {
                            if (u.dest) |dest| {
                                switch (movement.repathBlocked(&s.path_scratch, ctx, &s.world, s.units, i, dest, s.tick_count, s.cfg.timing.repath_cooldown_ticks)) {
                                    .fail => u.state = .idle,
                                    .wait, .ok => {},
                                }
                            }
                            continue;
                        }
                    }
                    const old_pos = u.pos();
                    u.step();
                    s.spatial_index.moveUnit(i, old_pos, u.pos());
                },
                .gathering_wood, .gathering_food, .hunting => economy.tickUnit(s, i),
                else => {},
            }
        }
    }
    {
        const sec = perf.section(&s.perf, .wildlife);
        defer sec.end();
        for (0..s.wildlife_count) |i| {
            s.wildlife[i].wander(&s.world, s.spatialCtx(), s.tick_count, i, s.cfg);
        }

        var wi: usize = 0;
        while (wi < s.wildlife_count) {
            const n = &s.wildlife[wi];
            if (n.deer.dead and n.deer.food_remaining > 0) {
                const tick_ms: u32 = @intCast(s.cfg.timing.tick_period_ns / 1_000_000);
                n.deer.rot_accum_ms += tick_ms;
                const rot_interval_ms: u32 = 1000 / s.cfg.economy.deer_rot_rate;
                while (n.deer.rot_accum_ms >= rot_interval_ms) {
                    n.deer.rot_accum_ms -= rot_interval_ms;
                    if (n.deer.food_remaining > 0) {
                        n.deer.food_remaining -= 1;
                    }
                }
            }
            if (n.deer.dead and n.deer.food_remaining == 0) {
                economy.removeDeer(s, wi);
            } else {
                wi += 1;
            }
        }
    }
    {
        const sec = perf.section(&s.perf, .training);
        defer sec.end();
        training.tickQueues(s);
    }
    s.perf.setPathfind(s.path_scratch.find_calls - pf_start);
    s.perf.finishTick();
}

test "tick moves unit along path" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    s.units[0].x = 5;
    s.units[0].y = 5;
    s.units[0].path[0] = .{ .x = 6, .y = 5 };
    s.units[0].path[1] = .{ .x = 7, .y = 5 };
    s.units[0].path_len = 2;
    s.units[0].path_idx = 0;
    s.units[0].state = .moving;

    tick(&s);
    try std.testing.expectEqual(@as(usize, 6), s.units[0].x);
    try std.testing.expectEqual(unit.UnitActivity.moving, s.units[0].state);

    tick(&s);
    try std.testing.expectEqual(@as(usize, 7), s.units[0].x);
    try std.testing.expectEqual(unit.UnitActivity.idle, s.units[0].state);
}

test "tick blocks movement into occupied tile" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();

    s.units[0].x = 10;
    s.units[0].y = 10;
    s.units[0].state = .moving;
    s.units[0].path[0] = .{ .x = 11, .y = 10 };
    s.units[0].path_len = 1;
    s.units[0].path_idx = 0;

    s.units[1].x = 11;
    s.units[1].y = 10;
    s.units[1].state = .idle;
    s.units[1].path_len = 0;

    tick(&s);

    try std.testing.expectEqual(@as(usize, 10), s.units[0].x);
    try std.testing.expectEqual(@as(usize, 10), s.units[0].y);
    try std.testing.expectEqual(unit.UnitActivity.moving, s.units[0].state);
}

test "wildlife wander over many ticks" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    if (s.wildlife_count > 0) {
        const start_x = s.wildlife[0].pos().x;
        const start_y = s.wildlife[0].pos().y;
        for (0..200) |_| tick(&s);
        const moved = s.wildlife[0].pos().x != start_x or s.wildlife[0].pos().y != start_y;
        try std.testing.expect(moved);
    }
}

test "elapsedSeconds" {
    const allocator = std.testing.allocator;
    const cfg = config.default();
    var s = try state.State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    try std.testing.expectEqual(@as(usize, 0), state.elapsedSeconds(&s));
    for (0..10) |_| tick(&s);
    try std.testing.expectEqual(@as(usize, 1), state.elapsedSeconds(&s));
    for (0..50) |_| tick(&s);
    try std.testing.expectEqual(@as(usize, 6), state.elapsedSeconds(&s));
}
