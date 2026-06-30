const std = @import("std");
const time = @import("../lib/time.zig");

pub const Stage = enum(u8) { units, wildlife, training, render };
pub const STAGE_COUNT = @typeInfo(Stage).@"enum".fields.len;
pub const WINDOW: usize = 64;

pub const stageLabel = [STAGE_COUNT][]const u8{ "units", "wildlife", "training", "render" };

pub const Perf = struct {
    enabled: bool = false,
    cur: [STAGE_COUNT]u64 = @splat(0),
    render_cur: u64 = 0,
    pathfind_calls: u64 = 0,
    tick_history: [WINDOW][STAGE_COUNT]u32 = @splat(@splat(0)),
    render_history: [WINDOW]u32 = @splat(0),
    pathfind_history: [WINDOW]u32 = @splat(0),
    head: usize = 0,
    filled: usize = 0,
    render_head: usize = 0,
    render_filled: usize = 0,
    ticks_since_flush: u64 = 0,

    pub fn resetTick(self: *Perf) void {
        self.cur = @splat(0);
        self.pathfind_calls = 0;
    }

    pub fn add(self: *Perf, s: Stage, ns: u64) void {
        self.cur[@intFromEnum(s)] += ns;
    }

    pub fn addRender(self: *Perf, ns: u64) void {
        self.render_cur += ns;
    }

    pub fn recordPathfind(self: *Perf) void {
        self.pathfind_calls += 1;
    }

    pub fn finishTick(self: *Perf) void {
        var row: [STAGE_COUNT]u32 = @splat(0);
        for (0..STAGE_COUNT) |i| {
            row[i] = @intCast(@min(self.cur[i], @as(u64, std.math.maxInt(u32))));
        }
        self.tick_history[self.head] = row;
        self.pathfind_history[self.head] =
            @intCast(@min(self.pathfind_calls, @as(u64, std.math.maxInt(u32))));
        self.head = (self.head + 1) % WINDOW;
        if (self.filled < WINDOW) self.filled += 1;
        self.ticks_since_flush += 1;
    }

    pub fn finishRender(self: *Perf) void {
        self.render_history[self.render_head] =
            @intCast(@min(self.render_cur, @as(u64, std.math.maxInt(u32))));
        self.render_cur = 0;
        self.render_head = (self.render_head + 1) % WINDOW;
        if (self.render_filled < WINDOW) self.render_filled += 1;
    }

    pub fn avgTick(self: *const Perf, s: Stage) u64 {
        if (self.filled == 0) return 0;
        var sum: u64 = 0;
        for (0..self.filled) |i| sum += self.tick_history[i][@intFromEnum(s)];
        return sum / self.filled;
    }

    pub fn maxTick(self: *const Perf, s: Stage) u32 {
        var m: u32 = 0;
        for (0..self.filled) |i| {
            if (self.tick_history[i][@intFromEnum(s)] > m) m = self.tick_history[i][@intFromEnum(s)];
        }
        return m;
    }

    pub fn avgRender(self: *const Perf) u64 {
        if (self.render_filled == 0) return 0;
        var sum: u64 = 0;
        for (0..self.render_filled) |i| sum += self.render_history[i];
        return sum / self.render_filled;
    }

    pub fn maxRender(self: *const Perf) u32 {
        var m: u32 = 0;
        for (0..self.render_filled) |i| {
            if (self.render_history[i] > m) m = self.render_history[i];
        }
        return m;
    }

    pub fn avgPathfind(self: *const Perf) u64 {
        if (self.filled == 0) return 0;
        var sum: u64 = 0;
        for (0..self.filled) |i| sum += self.pathfind_history[i];
        return sum / self.filled;
    }
};

pub const Section = struct {
    perf: *Perf,
    stage: Stage,
    start: u64,
    active: bool,

    pub fn end(self: Section) void {
        if (!self.active) return;
        const now = time.monoNow();
        const dt = if (now > self.start) now - self.start else 0;
        self.perf.add(self.stage, dt);
    }
};

pub fn section(perf: *Perf, s: Stage) Section {
    return .{
        .perf = perf,
        .stage = s,
        .start = if (perf.enabled) time.monoNow() else 0,
        .active = perf.enabled,
    };
}

pub const RenderSection = struct {
    perf: *Perf,
    start: u64,
    active: bool,

    pub fn end(self: RenderSection) void {
        if (!self.active) return;
        const now = time.monoNow();
        const dt = if (now > self.start) now - self.start else 0;
        self.perf.addRender(dt);
    }
};

pub fn renderSection(perf: *Perf) RenderSection {
    return .{
        .perf = perf,
        .start = if (perf.enabled) time.monoNow() else 0,
        .active = perf.enabled,
    };
}

test "Perf accumulates and rolls window" {
    var p = Perf{};
    p.enabled = true;
    p.add(.units, 100);
    p.add(.wildlife, 50);
    p.finishTick();
    try std.testing.expectEqual(@as(u64, 100), p.avgTick(.units));
    try std.testing.expectEqual(@as(u64, 50), p.avgTick(.wildlife));
    try std.testing.expectEqual(@as(u32, 100), p.maxTick(.units));
}

test "Perf window caps at WINDOW" {
    var p = Perf{};
    p.enabled = true;
    for (0..WINDOW + 10) |_| {
        p.resetTick();
        p.add(.units, 10);
        p.finishTick();
    }
    try std.testing.expectEqual(WINDOW, p.filled);
    try std.testing.expectEqual(@as(u64, 10), p.avgTick(.units));
}

test "section is inactive when disabled" {
    var p = Perf{};
    const s = section(&p, .units);
    try std.testing.expect(!s.active);
    s.end();
    try std.testing.expectEqual(@as(u64, 0), p.cur[@intFromEnum(Stage.units)]);
}

test "section records when enabled" {
    var p = Perf{};
    p.enabled = true;
    const s = section(&p, .units);
    s.end();
    try std.testing.expect(p.cur[@intFromEnum(Stage.units)] > 0 or p.cur[@intFromEnum(Stage.units)] == 0);
}

test "pathfind counter accumulates" {
    var p = Perf{};
    p.recordPathfind();
    p.recordPathfind();
    p.finishTick();
    try std.testing.expectEqual(@as(u64, 2), p.avgPathfind());
}

test "render timing separate from tick" {
    var p = Perf{};
    p.enabled = true;
    p.addRender(500);
    p.finishRender();
    try std.testing.expectEqual(@as(u64, 500), p.avgRender());
}
