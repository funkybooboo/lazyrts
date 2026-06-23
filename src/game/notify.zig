const state_mod = @import("state.zig");
const fmt = @import("../lib/fmt.zig");

const State = state_mod.State;
pub const Severity = state_mod.NotifSeverity;

pub fn push(s: *State, text: []const u8, sev: Severity) void {
    const slot = s.notif_head;
    var n: state_mod.Notification = .{};
    const copy_len = @min(text.len, n.text.len);
    @memcpy(n.text[0..copy_len], text[0..copy_len]);
    n.len = copy_len;
    n.tick = s.tick_count;
    n.severity = sev;
    s.notifications[slot] = n;
    s.notif_head = (slot + 1) % state_mod.MAX_NOTIFS;
    if (s.notif_count < state_mod.MAX_NOTIFS) s.notif_count += 1;
}

pub fn latest(s: *const State, lifetime: usize) ?*const state_mod.Notification {
    if (s.notif_count == 0) return null;
    const idx = (s.notif_head + state_mod.MAX_NOTIFS - 1) % state_mod.MAX_NOTIFS;
    const n = &s.notifications[idx];
    if (n.len == 0) return null;
    if (s.tick_count - n.tick > lifetime) return null;
    return n;
}

pub fn pushWoodDrop(s: *State, amount: u16) void {
    var buf: [48]u8 = undefined;
    var pos: usize = 0;
    buf[pos] = '+';
    pos += 1;
    pos += fmt.formatUint(buf[pos..], amount);
    const suffix = " wood";
    @memcpy(buf[pos..][0..suffix.len], suffix);
    pos += suffix.len;
    push(s, buf[0..pos], .info);
}

pub fn pushFoodDrop(s: *State, amount: u16) void {
    var buf: [48]u8 = undefined;
    var pos: usize = 0;
    buf[pos] = '+';
    pos += 1;
    pos += fmt.formatUint(buf[pos..], amount);
    const suffix = " food";
    @memcpy(buf[pos..][0..suffix.len], suffix);
    pos += suffix.len;
    push(s, buf[0..pos], .good);
}

pub fn pushUnitTrained(s: *State, label: []const u8) void {
    var buf: [48]u8 = undefined;
    const prefix = "Trained: ";
    const copy_prefix = @min(prefix.len, buf.len);
    @memcpy(buf[0..copy_prefix], prefix[0..copy_prefix]);
    var pos: usize = copy_prefix;
    const remaining = buf.len - pos;
    const copy_label = @min(label.len, remaining);
    @memcpy(buf[pos..][0..copy_label], label[0..copy_label]);
    pos += copy_label;
    push(s, buf[0..pos], .good);
}

pub fn pushFarmDepleted(s: *State) void {
    push(s, "Farm depleted", .bad);
}

pub fn pushTreeDepleted(s: *State) void {
    push(s, "Tree depleted", .info);
}

pub fn pushDeerKilled(s: *State) void {
    push(s, "Deer killed", .good);
}

test "push and latest" {
    const std = @import("std");
    const allocator = std.testing.allocator;
    const config = @import("../config.zig");
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    push(&s, "hello", .info);
    const n = latest(&s, 100).?;
    try std.testing.expectEqualStrings("hello", n.slice());
    try std.testing.expectEqual(Severity.info, n.severity);
}

test "latest returns null when expired" {
    const std = @import("std");
    const allocator = std.testing.allocator;
    const config = @import("../config.zig");
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    push(&s, "hello", .info);
    s.tick_count = 200;
    try std.testing.expect(latest(&s, 100) == null);
}

test "ring buffer wraps" {
    const std = @import("std");
    const allocator = std.testing.allocator;
    const config = @import("../config.zig");
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    for (0..state_mod.MAX_NOTIFS + 2) |i| {
        var buf: [1]u8 = .{@as(u8, @intCast('a' + i % 26))};
        push(&s, &buf, .info);
    }
    try std.testing.expectEqual(state_mod.MAX_NOTIFS, s.notif_count);
}

test "pushFoodDrop formats correctly" {
    const std = @import("std");
    const allocator = std.testing.allocator;
    const config = @import("../config.zig");
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    pushFoodDrop(&s, 10);
    const n = latest(&s, 100).?;
    try std.testing.expectEqualStrings("+10 food", n.slice());
}

test "pushWoodDrop formats correctly" {
    const std = @import("std");
    const allocator = std.testing.allocator;
    const config = @import("../config.zig");
    const cfg = config.default();
    var s = try State.init(allocator, 42, 80, 45, &cfg);
    defer s.deinit();
    pushWoodDrop(&s, 10);
    const n = latest(&s, 100).?;
    try std.testing.expectEqualStrings("+10 wood", n.slice());
}
