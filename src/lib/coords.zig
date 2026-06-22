const std = @import("std");

pub const Pos = struct { x: usize, y: usize };

pub const Dir = struct { dx: isize, dy: isize };

pub const dirs4 = [_]Dir{
    .{ .dx = 0, .dy = -1 },
    .{ .dx = 0, .dy = 1 },
    .{ .dx = -1, .dy = 0 },
    .{ .dx = 1, .dy = 0 },
};

pub fn manhattan(a: Pos, b: Pos) usize {
    const dx = if (a.x > b.x) a.x - b.x else b.x - a.x;
    const dy = if (a.y > b.y) a.y - b.y else b.y - a.y;
    return dx + dy;
}

pub fn parseCoord(buf: []const u8, len: usize) ?struct { x: usize, y: usize } {
    if (len == 0) return null;
    var col: usize = 0;
    var i: usize = 0;
    while (i < len and buf[i] >= 'A' and buf[i] <= 'Z') : (i += 1) {
        col = col * 26 + (@as(usize, buf[i] - 'A') + 1);
    }
    if (i == 0) return null;
    col -= 1;

    var row: usize = 0;
    while (i < len and buf[i] >= '0' and buf[i] <= '9') : (i += 1) {
        row = row * 10 + (@as(usize, buf[i] - '0'));
    }
    if (row == 0) return null;
    row -= 1;

    return .{ .x = col, .y = row };
}

pub fn colToLetters(col: usize, buf: *[3]u8) []const u8 {
    var n = col + 1;
    var i: usize = 0;
    while (n > 0 and i < 3) {
        n -= 1;
        buf[i] = 'A' + @as(u8, @intCast(n % 26));
        n /= 26;
        i += 1;
    }
    std.mem.reverse(u8, buf[0..i]);
    return buf[0..i];
}

pub fn headerHeight(map_w: usize) u16 {
    var buf: [3]u8 = undefined;
    const letters = colToLetters(map_w -| 1, &buf);
    return @as(u16, @intCast(letters.len));
}

test "parseCoord basic" {
    const r = parseCoord("A5", 2).?;
    try std.testing.expectEqual(@as(usize, 0), r.x);
    try std.testing.expectEqual(@as(usize, 4), r.y);
}

test "parseCoord Z26" {
    const r = parseCoord("Z26", 3).?;
    try std.testing.expectEqual(@as(usize, 25), r.x);
    try std.testing.expectEqual(@as(usize, 25), r.y);
}

test "parseCoord AA1" {
    const r = parseCoord("AA1", 3).?;
    try std.testing.expectEqual(@as(usize, 26), r.x);
    try std.testing.expectEqual(@as(usize, 0), r.y);
}

test "parseCoord invalid" {
    try std.testing.expect(parseCoord("5", 1) == null);
    try std.testing.expect(parseCoord("", 0) == null);
    try std.testing.expect(parseCoord("A", 1) == null);
}

test "colToLetters roundtrip" {
    var buf: [3]u8 = undefined;
    try std.testing.expectEqualStrings("A", colToLetters(0, &buf));
    try std.testing.expectEqualStrings("Z", colToLetters(25, &buf));
    try std.testing.expectEqualStrings("AA", colToLetters(26, &buf));
    try std.testing.expectEqualStrings("AB", colToLetters(27, &buf));
    try std.testing.expectEqualStrings("AZ", colToLetters(51, &buf));
    try std.testing.expectEqualStrings("BA", colToLetters(52, &buf));
}

test "parseCoord B3" {
    const r = parseCoord("B3", 2).?;
    try std.testing.expectEqual(@as(usize, 1), r.x);
    try std.testing.expectEqual(@as(usize, 2), r.y);
}

test "parseCoord multi-letter" {
    const r = parseCoord("AB5", 3).?;
    try std.testing.expectEqual(@as(usize, 27), r.x);
    try std.testing.expectEqual(@as(usize, 4), r.y);
}

test "parseCoord no digits returns null" {
    try std.testing.expect(parseCoord("A", 1) == null);
}

test "colToLetters produces valid column letters" {
    var buf: [3]u8 = undefined;
    try std.testing.expectEqualStrings("A", colToLetters(0, &buf));
    try std.testing.expectEqualStrings("Z", colToLetters(25, &buf));
    try std.testing.expectEqualStrings("AA", colToLetters(26, &buf));
    for (0..30) |col| {
        const letters = colToLetters(col, &buf);
        try std.testing.expect(letters.len > 0);
        for (letters) |ch| {
            try std.testing.expect(ch >= 'A' and ch <= 'Z');
        }
    }
}
