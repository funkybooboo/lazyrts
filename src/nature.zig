const std = @import("std");
const config = @import("config.zig");
const unit = @import("unit.zig");
const game = @import("game.zig");

pub const NatureKind = enum {
    deer,

    pub fn glyph(self: NatureKind, cfg: *const config.Config) []const u8 {
        return switch (self) {
            .deer => cfg.glyphs.deer,
        };
    }
};

pub const NatureState = enum { idle, wandering };

pub const Nature = struct {
    x: usize,
    y: usize,
    kind: NatureKind,
    hp: u16,
    state: NatureState = .idle,
};

pub fn max_hp(kind: NatureKind, cfg: *const config.Config) u16 {
    return switch (kind) {
        .deer => cfg.nature_hp.deer,
    };
}

pub fn wander(n: *Nature, map: anytype, state: anytype, tick_count: usize, idx: usize, cfg: *const config.Config) void {
    if (n.state != .idle) return;
    if (tick_count % cfg.deer.wander_interval != 0) return;

    var rng = std.Random.DefaultPrng.init(tick_count * cfg.deer.seed_mult_tick + idx * cfg.deer.seed_mult_idx + @as(u64, @intCast(n.x)));
    const should_wander = rng.random().intRangeAtMost(usize, 0, 2) == 0;
    if (!should_wander) return;

    // Try all directions, pick a random valid one to avoid getting stuck
    const dirs = [_]struct { dx: isize, dy: isize }{
        .{ .dx = 0, .dy = -1 }, .{ .dx = 0, .dy = 1 },
        .{ .dx = -1, .dy = 0 }, .{ .dx = 1, .dy = 0 },
    };
    
    // Collect valid moves
    var valid_moves: [4]usize = undefined;
    var valid_count: usize = 0;
    
    for (dirs, 0..) |d, i| {
        const next_x = @as(isize, @intCast(n.x)) + d.dx;
        const next_y = @as(isize, @intCast(n.y)) + d.dy;
        if (next_x < 0 or next_y < 0) continue;
        const unit_x: usize = @intCast(next_x);
        const unit_y: usize = @intCast(next_y);
        if (unit_x < map.width and unit_y < map.height and map.is_walkable(unit_x, unit_y)) {
            // Check if not occupied by other entities
            if (game.unit_at(state, unit_x, unit_y) == null and
                game.building_at(state, unit_x, unit_y) == null and
                game.nature_at_except(state, unit_x, unit_y, idx) == null) {
                valid_moves[valid_count] = i;
                valid_count += 1;
            }
        }
    }
    
    // Pick a random valid move
    if (valid_count > 0) {
        const move_idx = rng.random().intRangeAtMost(usize, 0, valid_count - 1);
        const d = dirs[valid_moves[move_idx]];
        const next_x = @as(isize, @intCast(n.x)) + d.dx;
        const next_y = @as(isize, @intCast(n.y)) + d.dy;
        n.x = @intCast(next_x);
        n.y = @intCast(next_y);
    }
}

test "NatureKind.glyph" {
    const cfg = config.default();
    try std.testing.expectEqualStrings("d", NatureKind.deer.glyph(&cfg));
}

test "max_hp positive" {
    const cfg = config.default();
    try std.testing.expect(max_hp(.deer, &cfg) > 0);
}

test "Nature default state is idle" {
    const n = Nature{ .x = 0, .y = 0, .kind = .deer, .hp = 25 };
    try std.testing.expectEqual(NatureState.idle, n.state);
}
