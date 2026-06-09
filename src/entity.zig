pub const Pos = struct { x: usize, y: usize };

pub const Owner = enum(u1) { player, enemy };

pub const UnitKind = enum {
    worker,
    soldier,

    pub fn glyph(self: UnitKind) []const u8 {
        return switch (self) {
            .worker => "w",
            .soldier => "s",
        };
    }

    pub fn max_hp(self: UnitKind) u16 {
        return switch (self) {
            .worker => 50,
            .soldier => 100,
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
};

pub const UnitState = enum { idle, moving };

pub const MAX_PATH: usize = 256;
pub const MAX_UNITS: usize = 64;
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
};
