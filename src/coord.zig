const std = @import("std");

pub fn parse_coord(buf: []const u8, len: usize) ?struct { x: usize, y: usize } {
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

pub fn col_to_letters(col: usize, buf: *[3]u8) []const u8 {
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

test "parse_coord basic" {
    const r = parse_coord("A5", 2).?;
    try std.testing.expectEqual(@as(usize, 0), r.x);
    try std.testing.expectEqual(@as(usize, 4), r.y);
}

test "parse_coord Z26" {
    const r = parse_coord("Z26", 3).?;
    try std.testing.expectEqual(@as(usize, 25), r.x);
    try std.testing.expectEqual(@as(usize, 25), r.y);
}

test "parse_coord AA1" {
    const r = parse_coord("AA1", 3).?;
    try std.testing.expectEqual(@as(usize, 26), r.x);
    try std.testing.expectEqual(@as(usize, 0), r.y);
}

test "parse_coord invalid" {
    try std.testing.expect(parse_coord("5", 1) == null);
    try std.testing.expect(parse_coord("", 0) == null);
    try std.testing.expect(parse_coord("A", 1) == null);
}

test "col_to_letters roundtrip" {
    var buf: [3]u8 = undefined;
    try std.testing.expectEqualStrings("A", col_to_letters(0, &buf));
    try std.testing.expectEqualStrings("Z", col_to_letters(25, &buf));
    try std.testing.expectEqualStrings("AA", col_to_letters(26, &buf));
    try std.testing.expectEqualStrings("AB", col_to_letters(27, &buf));
    try std.testing.expectEqualStrings("AZ", col_to_letters(51, &buf));
    try std.testing.expectEqualStrings("BA", col_to_letters(52, &buf));
}

test "parse_coord B3" {
    const r = parse_coord("B3", 2).?;
    try std.testing.expectEqual(@as(usize, 1), r.x);
    try std.testing.expectEqual(@as(usize, 2), r.y);
}

test "parse_coord multi-letter" {
    const r = parse_coord("AB5", 3).?;
    try std.testing.expectEqual(@as(usize, 27), r.x);
    try std.testing.expectEqual(@as(usize, 4), r.y);
}

test "parse_coord no digits returns null" {
    try std.testing.expect(parse_coord("A", 1) == null);
}

test "col_to_letters produces valid column letters" {
    var buf: [3]u8 = undefined;
    try std.testing.expectEqualStrings("A", col_to_letters(0, &buf));
    try std.testing.expectEqualStrings("Z", col_to_letters(25, &buf));
    try std.testing.expectEqualStrings("AA", col_to_letters(26, &buf));
    for (0..30) |col| {
        const letters = col_to_letters(col, &buf);
        try std.testing.expect(letters.len > 0);
        for (letters) |ch| {
            try std.testing.expect(ch >= 'A' and ch <= 'Z');
        }
    }
}
