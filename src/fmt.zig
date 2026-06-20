pub fn format_uint(buf: []u8, val: u64) usize {
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

test "format_uint formats zero" {
    var buf: [8]u8 = undefined;
    const len = format_uint(&buf, 0);
    try @import("std").testing.expectEqualStrings("0", buf[0..len]);
}

test "format_uint formats single digit" {
    var buf: [8]u8 = undefined;
    const len = format_uint(&buf, 5);
    try @import("std").testing.expectEqualStrings("5", buf[0..len]);
}

test "format_uint formats multi digit" {
    var buf: [8]u8 = undefined;
    const len = format_uint(&buf, 123);
    try @import("std").testing.expectEqualStrings("123", buf[0..len]);
}

test "format_uint formats large number" {
    var buf: [20]u8 = undefined;
    const len = format_uint(&buf, 18446744073709551615);
    try @import("std").testing.expectEqualStrings("18446744073709551615", buf[0..len]);
}
