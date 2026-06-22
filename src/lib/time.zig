const std = @import("std");

pub const NS_PER_SEC: u64 = 1_000_000_000;
pub const NS_PER_MS: u64 = 1_000_000;

pub fn monoNow() u64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i64, ts.sec) * @as(i64, @intCast(NS_PER_SEC)) + ts.nsec);
}

pub fn sleepNs(ns: u64) void {
    var req: std.os.linux.timespec = .{
        .sec = @intCast(ns / NS_PER_SEC),
        .nsec = @intCast(ns % NS_PER_SEC),
    };
    _ = std.os.linux.nanosleep(&req, null);
}

pub fn ticksToSeconds(tick_count: usize, tick_rate: usize) usize {
    return tick_count / tick_rate;
}

pub const Ticker = struct {
    period_ns: u64,
    accum: u64 = 0,
    last: ?u64 = null,

    pub fn update(self: *Ticker, now: u64) usize {
        if (self.last) |prev| {
            if (now > prev) {
                self.accum += now - prev;
            }
        }
        self.last = now;

        var ticks: usize = 0;
        while (self.accum >= self.period_ns) {
            self.accum -= self.period_ns;
            ticks += 1;
        }
        return ticks;
    }
};

test "Ticker accumulates and fires" {
    var t = Ticker{ .period_ns = 100, .last = 1000, .accum = 250 };
    const n = t.update(1000);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqual(@as(u64, 50), t.accum);
}

test "Ticker returns 0 when no time passed" {
    var t = Ticker{ .period_ns = 100, .last = 1000, .accum = 0 };
    const n = t.update(1000);
    try std.testing.expectEqual(@as(usize, 0), n);
}

test "Ticker accumulates across multiple updates" {
    var t = Ticker{ .period_ns = 100, .last = 0, .accum = 0 };
    const n1 = t.update(60);
    try std.testing.expectEqual(@as(usize, 0), n1);
    try std.testing.expectEqual(@as(u64, 60), t.accum);
    const n2 = t.update(120);
    try std.testing.expectEqual(@as(usize, 1), n2);
    try std.testing.expectEqual(@as(u64, 20), t.accum);
}

test "ticksToSeconds basic conversion" {
    try std.testing.expectEqual(@as(usize, 0), ticksToSeconds(0, 10));
    try std.testing.expectEqual(@as(usize, 1), ticksToSeconds(10, 10));
    try std.testing.expectEqual(@as(usize, 6), ticksToSeconds(60, 10));
    try std.testing.expectEqual(@as(usize, 5), ticksToSeconds(50, 10));
}
