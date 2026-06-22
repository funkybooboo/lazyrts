const std = @import("std");

pub fn formatUint(buf: []u8, val: u64) usize {
    if (val == 0) {
        if (buf.len > 0) buf[0] = '0';
        return 1;
    }
    var tmp: [20]u8 = undefined;
    var n = val;
    var i: usize = 0;
    while (n > 0) {
        tmp[i] = '0' + @as(u8, @intCast(n % 10));
        n /= 10;
        i += 1;
    }
    var j: usize = 0;
    while (i > 0) {
        i -= 1;
        if (j < buf.len) buf[j] = tmp[i];
        j += 1;
    }
    return j;
}

pub fn formatElapsed(secs: usize, buf: []u8, seconds_per_minute: usize) []const u8 {
    const mins = secs / seconds_per_minute;
    const secs_rem = secs % seconds_per_minute;
    var pos: usize = 0;
    if (mins < 10) {
        if (pos < buf.len) buf[pos] = '0';
        pos += 1;
    }
    pos += formatUint(buf[pos..], mins);
    if (pos < buf.len) buf[pos] = ':';
    pos += 1;
    if (secs_rem < 10) {
        if (pos < buf.len) buf[pos] = '0';
        pos += 1;
    }
    pos += formatUint(buf[pos..], secs_rem);
    return buf[0..pos];
}

test "formatUint formats zero" {
    var buf: [8]u8 = undefined;
    const len = formatUint(&buf, 0);
    try std.testing.expectEqualStrings("0", buf[0..len]);
}

test "formatUint formats single digit" {
    var buf: [8]u8 = undefined;
    const len = formatUint(&buf, 5);
    try std.testing.expectEqualStrings("5", buf[0..len]);
}

test "formatUint formats multi digit" {
    var buf: [8]u8 = undefined;
    const len = formatUint(&buf, 123);
    try std.testing.expectEqualStrings("123", buf[0..len]);
}

test "formatUint formats large number" {
    var buf: [20]u8 = undefined;
    const len = formatUint(&buf, 18446744073709551615);
    try std.testing.expectEqualStrings("18446744073709551615", buf[0..len]);
}

test "formatElapsed single digit minutes and seconds" {
    var buf: [8]u8 = undefined;
    const result = formatElapsed(65, &buf, 60);
    try std.testing.expectEqualStrings("01:05", result);
}

test "formatElapsed double digit minutes" {
    var buf: [8]u8 = undefined;
    const result = formatElapsed(125, &buf, 60);
    try std.testing.expectEqualStrings("02:05", result);
}

test "formatElapsed zero seconds" {
    var buf: [8]u8 = undefined;
    const result = formatElapsed(0, &buf, 60);
    try std.testing.expectEqualStrings("00:00", result);
}

test "formatElapsed large minutes" {
    var buf: [8]u8 = undefined;
    const result = formatElapsed(600, &buf, 60);
    try std.testing.expectEqualStrings("10:00", result);
}
