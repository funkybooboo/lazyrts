const std = @import("std");
const config = @import("config.zig");
const fmt = @import("fmt.zig");

pub const NS_PER_SEC: u64 = 1_000_000_000;
pub const NS_PER_MS: u64 = 1_000_000;

pub fn mono_now() u64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i64, ts.sec) * @as(i64, @intCast(NS_PER_SEC)) + ts.nsec);
}

pub fn sleep_ns(ns: u64) void {
    var req: std.os.linux.timespec = .{
        .sec = @intCast(ns / NS_PER_SEC),
        .nsec = @intCast(ns % NS_PER_SEC),
    };
    _ = std.os.linux.nanosleep(&req, null);
}

pub fn ticks_to_seconds(tick_count: usize, tick_rate: usize) usize {
    return tick_count / tick_rate;
}

pub fn format_elapsed(secs: usize, buf: []u8, seconds_per_minute: usize) []const u8 {
    const mins = secs / seconds_per_minute;
    const secs_rem = secs % seconds_per_minute;
    var pos: usize = 0;
    if (mins < 10) {
        if (pos < buf.len) buf[pos] = '0';
        pos += 1;
    }
    pos += fmt.format_uint(buf[pos..], mins);
    if (pos < buf.len) buf[pos] = ':';
    pos += 1;
    if (secs_rem < 10) {
        if (pos < buf.len) buf[pos] = '0';
        pos += 1;
    }
    pos += fmt.format_uint(buf[pos..], secs_rem);
    return buf[0..pos];
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

test "ticks_to_seconds basic conversion" {
    try std.testing.expectEqual(@as(usize, 0), ticks_to_seconds(0, 10));
    try std.testing.expectEqual(@as(usize, 1), ticks_to_seconds(10, 10));
    try std.testing.expectEqual(@as(usize, 6), ticks_to_seconds(60, 10));
    try std.testing.expectEqual(@as(usize, 5), ticks_to_seconds(50, 10));
}

test "format_elapsed single digit minutes and seconds" {
    var buf: [8]u8 = undefined;
    const result = format_elapsed(65, &buf, 60);
    try std.testing.expectEqualStrings("01:05", result);
}

test "format_elapsed double digit minutes" {
    var buf: [8]u8 = undefined;
    const result = format_elapsed(125, &buf, 60);
    try std.testing.expectEqualStrings("02:05", result);
}

test "format_elapsed zero seconds" {
    var buf: [8]u8 = undefined;
    const result = format_elapsed(0, &buf, 60);
    try std.testing.expectEqualStrings("00:00", result);
}

test "format_elapsed large minutes" {
    var buf: [8]u8 = undefined;
    const result = format_elapsed(600, &buf, 60);
    try std.testing.expectEqualStrings("10:00", result);
}
