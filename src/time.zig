const std = @import("std");

pub fn mono_now() u64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i64, ts.sec) * 1_000_000_000 + ts.nsec);
}

pub fn sleep_ns(ns: u64) void {
    var req: std.os.linux.timespec = .{
        .sec = @intCast(ns / 1_000_000_000),
        .nsec = @intCast(ns % 1_000_000_000),
    };
    _ = std.os.linux.nanosleep(&req, null);
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
