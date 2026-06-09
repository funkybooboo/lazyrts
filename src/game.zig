const map = @import("map.zig");

pub const State = struct {
    cursor_x: usize = 3,
    cursor_y: usize = 3,
    quit: bool = false,
    world: map.GameMap,

    pub fn init(seed: u64) State {
        return .{ .world = map.GameMap.init(seed) };
    }

    pub fn move_cursor(self: *State, dx: isize, dy: isize) void {
        const nx = @max(0, @min(@as(isize, @intCast(self.cursor_x)) + dx, @as(isize, @intCast(map.WIDTH - 1))));
        const ny = @max(0, @min(@as(isize, @intCast(self.cursor_y)) + dy, @as(isize, @intCast(map.HEIGHT - 1))));
        self.cursor_x = @intCast(nx);
        self.cursor_y = @intCast(ny);
    }
};

const std = @import("std");

test "move_cursor clamps to bounds" {
    var s = State.init(1);
    s.cursor_x = 0;
    s.cursor_y = 0;
    s.move_cursor(-1, 0);
    try std.testing.expectEqual(@as(usize, 0), s.cursor_x);

    s.cursor_x = map.WIDTH - 1;
    s.move_cursor(1, 0);
    try std.testing.expectEqual(map.WIDTH - 1, s.cursor_x);

    s.cursor_y = 0;
    s.move_cursor(0, -1);
    try std.testing.expectEqual(@as(usize, 0), s.cursor_y);

    s.cursor_y = map.HEIGHT - 1;
    s.move_cursor(0, 1);
    try std.testing.expectEqual(map.HEIGHT - 1, s.cursor_y);
}

test "move_cursor moves normally" {
    var s = State.init(1);
    s.cursor_x = 10;
    s.cursor_y = 10;
    s.move_cursor(5, -3);
    try std.testing.expectEqual(@as(usize, 15), s.cursor_x);
    try std.testing.expectEqual(@as(usize, 7), s.cursor_y);
}

test "init sets cursor at TC" {
    const s = State.init(42);
    try std.testing.expectEqual(@as(usize, 3), s.cursor_x);
    try std.testing.expectEqual(@as(usize, 3), s.cursor_y);
}