pub const Tile = enum(u8) {
    grass = ' ',
    tree = 'T',
    water = '~',
    town_center = 'C',
    house = 'H',
    barracks = 'B',
    farm = 'F',
    worker = 'w',
    soldier = 's',

    pub fn glyph(self: Tile) []const u8 {
        return &.{@intFromEnum(self)};
    }
};

pub const WIDTH: usize = 80;
pub const HEIGHT: usize = 40;

pub const GameMap = struct {
    tiles: [HEIGHT][WIDTH]Tile,

    pub fn init(seed: u64) GameMap {
        var m: GameMap = undefined;
        var rng = std.Random.DefaultPrng.init(seed);

        for (&m.tiles) |*row| {
            for (row) |*t| {
                const r = rng.random().int(u8);
                t.* = if (r < 12) .tree else if (r < 14) .water else .grass;
            }
        }

        m.clear(3, 3, 3);
        m.tiles[3][3] = .town_center;
        m.clear(WIDTH - 4, HEIGHT - 4, 3);
        m.tiles[HEIGHT - 4][WIDTH - 4] = .town_center;

        return m;
    }

    pub fn at(self: *const GameMap, x: usize, y: usize) Tile {
        if (x >= WIDTH or y >= HEIGHT) return .water;
        return self.tiles[y][x];
    }

    fn clear(self: *GameMap, cx: usize, cy: usize, radius: usize) void {
        const y0 = if (cy > radius) cy - radius else 0;
        const y1 = @min(cy + radius + 1, HEIGHT);
        const x0 = if (cx > radius) cx - radius else 0;
        const x1 = @min(cx + radius + 1, WIDTH);
        for (y0..y1) |y| {
            for (x0..x1) |x| {
                self.tiles[y][x] = .grass;
            }
        }
    }
};

const std = @import("std");

test "at returns water for out of bounds" {
    var m = GameMap.init(1);
    try std.testing.expectEqual(.water, m.at(WIDTH, 0));
    try std.testing.expectEqual(.water, m.at(0, HEIGHT));
    try std.testing.expectEqual(.water, m.at(WIDTH + 100, HEIGHT + 100));
}

test "at returns tile within bounds" {
    var m = GameMap.init(1);
    try std.testing.expectEqual(.town_center, m.at(3, 3));
}

test "init places both TCs" {
    var m = GameMap.init(99);
    try std.testing.expectEqual(.town_center, m.at(3, 3));
    try std.testing.expectEqual(.town_center, m.at(WIDTH - 4, HEIGHT - 4));
}

test "init clears areas around TCs" {
    var m = GameMap.init(99);
    try std.testing.expectEqual(.grass, m.at(2, 2));
    try std.testing.expectEqual(.grass, m.at(4, 4));
}

test "glyph returns single char" {
    try std.testing.expectEqualStrings("T", Tile.tree.glyph());
    try std.testing.expectEqualStrings(" ", Tile.grass.glyph());
    try std.testing.expectEqualStrings("~", Tile.water.glyph());
    try std.testing.expectEqualStrings("C", Tile.town_center.glyph());
}