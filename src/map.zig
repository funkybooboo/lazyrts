pub const Tile = enum(u8) {
    grass = ' ',
    tree = 'T',
    water = '~',
    town_center = 'C',
    house = 'H',
    barracks = 'B',
    farm = 'F',

    pub fn glyph(self: Tile) []const u8 {
        return switch (self) {
            .grass => " ",
            .tree => "T",
            .water => "~",
            .town_center => "C",
            .house => "H",
            .barracks => "B",
            .farm => "F",
        };
    }

    pub fn is_walkable(self: Tile) bool {
        return switch (self) {
            .grass, .town_center, .farm => true,
            .tree, .water, .house, .barracks => false,
        };
    }
};

pub const WIDTH: usize = 80;
pub const HEIGHT: usize = 40;

pub const PLAYER_TC_X: usize = 3;
pub const PLAYER_TC_Y: usize = 3;
pub const ENEMY_TC_X: usize = WIDTH - 4;
pub const ENEMY_TC_Y: usize = HEIGHT - 4;
pub const TC_CLEAR_RADIUS: usize = 3;

const TREE_THRESHOLD: u8 = 12;
const WATER_THRESHOLD: u8 = 14;

pub const GameMap = struct {
    tiles: [HEIGHT][WIDTH]Tile,

    pub fn init(seed: u64) GameMap {
        var m: GameMap = undefined;
        var rng = std.Random.DefaultPrng.init(seed);

        for (&m.tiles) |*row| {
            for (row) |*t| {
                const r = rng.random().int(u8);
                t.* = if (r < TREE_THRESHOLD) .tree else if (r < WATER_THRESHOLD) .water else .grass;
            }
        }

        m.clear(PLAYER_TC_X, PLAYER_TC_Y, TC_CLEAR_RADIUS);
        m.tiles[PLAYER_TC_Y][PLAYER_TC_X] = .town_center;
        m.clear(ENEMY_TC_X, ENEMY_TC_Y, TC_CLEAR_RADIUS);
        m.tiles[ENEMY_TC_Y][ENEMY_TC_X] = .town_center;

        return m;
    }

    pub fn at(self: *const GameMap, x: usize, y: usize) Tile {
        if (x >= WIDTH or y >= HEIGHT) return .water;
        return self.tiles[y][x];
    }

    pub fn is_walkable(self: *const GameMap, x: usize, y: usize) bool {
        return self.at(x, y).is_walkable();
    }

    pub fn set(self: *GameMap, x: usize, y: usize, tile: Tile) void {
        if (x >= WIDTH or y >= HEIGHT) return;
        self.tiles[y][x] = tile;
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
    try std.testing.expectEqual(.town_center, m.at(PLAYER_TC_X, PLAYER_TC_Y));
}

test "init places both TCs" {
    var m = GameMap.init(99);
    try std.testing.expectEqual(.town_center, m.at(PLAYER_TC_X, PLAYER_TC_Y));
    try std.testing.expectEqual(.town_center, m.at(ENEMY_TC_X, ENEMY_TC_Y));
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

test "is_walkable on Tile" {
    try std.testing.expect(Tile.grass.is_walkable());
    try std.testing.expect(Tile.town_center.is_walkable());
    try std.testing.expect(!Tile.tree.is_walkable());
    try std.testing.expect(!Tile.water.is_walkable());
    try std.testing.expect(!Tile.house.is_walkable());
    try std.testing.expect(Tile.farm.is_walkable());
}

test "is_walkable on GameMap" {
    var m = GameMap.init(99);
    try std.testing.expect(m.is_walkable(PLAYER_TC_X, PLAYER_TC_Y));
    try std.testing.expect(!m.is_walkable(WIDTH, 0));
}

test "set changes a tile" {
    var m = GameMap.init(99);
    try std.testing.expectEqual(.grass, m.at(5, 5));
    m.set(5, 5, .house);
    try std.testing.expectEqual(.house, m.at(5, 5));
}

test "set ignores out of bounds" {
    var m = GameMap.init(99);
    m.set(WIDTH, 0, .house);
    try std.testing.expectEqual(.water, m.at(WIDTH, 0));
}
