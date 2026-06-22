const std = @import("std");
const vaxis = @import("vaxis");

pub const Color = union(enum) {
    default,
    rgb: [3]u8,
    index: u8,
};

pub const Style = struct {
    fg: Color = .default,
    bg: Color = .default,
    bold: bool = false,
    reverse: bool = false,
};

pub const Key = struct {
    kind: KeyKind,
    char_val: u8 = 0,
    ctrl: bool = false,
    shift: bool = false,

    pub const KeyKind = enum {
        char,
        left,
        right,
        up,
        down,
        tab,
        enter,
        escape,
        unknown,
    };

    pub fn isChar(self: Key, ch: u8) bool {
        return !self.ctrl and self.kind == .char and self.char_val == ch;
    }

    pub fn isCtrl(self: Key, ch: u8) bool {
        return self.ctrl and self.kind == .char and self.char_val == ch;
    }

    pub fn isLeft(self: Key) bool {
        return self.kind == .left;
    }

    pub fn isRight(self: Key) bool {
        return self.kind == .right;
    }

    pub fn isUp(self: Key) bool {
        return self.kind == .up;
    }

    pub fn isDown(self: Key) bool {
        return self.kind == .down;
    }

    pub fn isTab(self: Key) bool {
        return self.kind == .tab;
    }

    pub fn isShiftTab(self: Key) bool {
        return self.kind == .tab and self.shift;
    }

    pub fn isEnter(self: Key) bool {
        return self.kind == .enter;
    }

    pub fn isEscape(self: Key) bool {
        return self.kind == .escape;
    }
};

pub const Event = union(enum) {
    key_press: Key,
    resize,
};

pub const Canvas = struct {
    win: vaxis.Window,

    const ASCII_TABLE_SIZE = 128;
    const MIN_PRINTABLE_CHAR = 32;
    const MAX_PRINTABLE_CHAR = 126;

    const ascii_table: [ASCII_TABLE_SIZE][]const u8 = blk: {
        var table: [ASCII_TABLE_SIZE][]const u8 = undefined;
        for (0..ASCII_TABLE_SIZE) |i| {
            table[i] = &[_]u8{@intCast(i)};
        }
        break :blk table;
    };

    pub fn clear(self: Canvas) void {
        self.win.clear();
    }

    pub fn width(self: Canvas) u16 {
        return self.win.width;
    }

    pub fn height(self: Canvas) u16 {
        return self.win.height;
    }

    pub fn writeCell(self: Canvas, x: u16, y: u16, glyph: []const u8, s: Style) void {
        const g: []const u8 = if (glyph.len == 1 and glyph[0] < ASCII_TABLE_SIZE) ascii_table[glyph[0]] else glyph;
        self.win.writeCell(x, y, .{
            .char = .{ .grapheme = g },
            .style = toVaxisStyle(s),
        });
    }

    pub fn writeStr(self: Canvas, x: u16, y: u16, text: []const u8, s: Style) void {
        var cx: u16 = x;
        for (text) |ch| {
            if (ch < MIN_PRINTABLE_CHAR or ch > MAX_PRINTABLE_CHAR) continue;
            self.writeCell(cx, y, &[_]u8{ch}, s);
            cx += 1;
        }
    }
};

const InternalEvent = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

const VxLoop = vaxis.Loop(InternalEvent);

pub const Terminal = struct {
    buf: [1024]u8 = undefined,
    tty: vaxis.Tty = undefined,
    vx: vaxis.Vaxis = undefined,
    loop: VxLoop = undefined,
    alloc: std.mem.Allocator,

    pub fn init(self: *Terminal, io: std.Io, alloc: std.mem.Allocator, env: *std.process.Environ.Map) !void {
        self.alloc = alloc;
        self.tty = try vaxis.Tty.init(io, &self.buf);
        self.vx = try vaxis.init(io, alloc, env, .{});
        self.loop = VxLoop.init(io, &self.tty, &self.vx);
        try self.loop.start();
        try self.vx.enterAltScreen(self.tty.writer());
        try self.vx.queryTerminal(self.tty.writer(), .fromSeconds(1));
    }

    pub fn deinit(self: *Terminal) void {
        self.loop.stop();
        self.vx.deinit(self.alloc, self.tty.writer());
        self.tty.deinit();
    }

    pub fn pollEvent(self: *Terminal) !?Event {
        const vev = try self.loop.tryEvent() orelse return null;
        return switch (vev) {
            .key_press => |vk| Event{ .key_press = fromVaxisKey(vk) },
            .winsize => |ws| blk: {
                try self.vx.resize(self.alloc, self.tty.writer(), ws);
                break :blk Event.resize;
            },
        };
    }

    pub fn canvas(self: *Terminal) Canvas {
        return .{ .win = self.vx.window() };
    }

    pub fn present(self: *Terminal) !void {
        try self.vx.render(self.tty.writer());
    }
};

fn fromVaxisKey(vk: vaxis.Key) Key {
    const kind: Key.KeyKind = switch (vk.codepoint) {
        vaxis.Key.left => .left,
        vaxis.Key.right => .right,
        vaxis.Key.up => .up,
        vaxis.Key.down => .down,
        vaxis.Key.tab => .tab,
        vaxis.Key.enter => .enter,
        vaxis.Key.escape => .escape,
        else => blk: {
            if (vk.codepoint < 128 and vk.codepoint >= 32) {
                break :blk .char;
            }
            break :blk .unknown;
        },
    };
    return .{
        .kind = kind,
        .char_val = if (kind == .char) @intCast(vk.codepoint) else 0,
        .ctrl = vk.mods.ctrl,
        .shift = vk.mods.shift,
    };
}

fn toVaxisStyle(s: Style) vaxis.Style {
    return .{
        .fg = toVaxisColor(s.fg),
        .bg = toVaxisColor(s.bg),
        .bold = s.bold,
        .reverse = s.reverse,
    };
}

fn toVaxisColor(c: Color) vaxis.Color {
    return switch (c) {
        .default => .default,
        .rgb => |rgb| .{ .rgb = rgb },
        .index => |i| .{ .index = i },
    };
}

test "fromVaxisKey: printable char" {
    const vk: vaxis.Key = .{ .codepoint = 'q' };
    const k = fromVaxisKey(vk);
    try std.testing.expect(k.isChar('q'));
    try std.testing.expect(!k.isCtrl('q'));
    try std.testing.expect(!k.isLeft());
}

test "fromVaxisKey: ctrl+c" {
    const vk: vaxis.Key = .{ .codepoint = 'c', .mods = .{ .ctrl = true } };
    const k = fromVaxisKey(vk);
    try std.testing.expect(k.isCtrl('c'));
    try std.testing.expect(!k.isChar('c'));
}

test "fromVaxisKey: arrow keys" {
    try std.testing.expectEqual(Key.KeyKind.left, fromVaxisKey(.{ .codepoint = vaxis.Key.left }).kind);
    try std.testing.expectEqual(Key.KeyKind.right, fromVaxisKey(.{ .codepoint = vaxis.Key.right }).kind);
    try std.testing.expectEqual(Key.KeyKind.up, fromVaxisKey(.{ .codepoint = vaxis.Key.up }).kind);
    try std.testing.expectEqual(Key.KeyKind.down, fromVaxisKey(.{ .codepoint = vaxis.Key.down }).kind);
}

test "fromVaxisKey: tab" {
    const k = fromVaxisKey(.{ .codepoint = vaxis.Key.tab });
    try std.testing.expect(k.isTab());
}

test "fromVaxisKey: enter" {
    const k = fromVaxisKey(.{ .codepoint = vaxis.Key.enter });
    try std.testing.expect(k.isEnter());
}

test "fromVaxisKey: escape" {
    const k = fromVaxisKey(.{ .codepoint = vaxis.Key.escape });
    try std.testing.expect(k.isEscape());
}

test "fromVaxisKey: unknown key" {
    const k = fromVaxisKey(.{ .codepoint = 99999 });
    try std.testing.expectEqual(Key.KeyKind.unknown, k.kind);
}

test "toVaxisColor: default" {
    const c = toVaxisColor(.default);
    try std.testing.expectEqual(vaxis.Color.default, c);
}

test "toVaxisColor: rgb" {
    const c = toVaxisColor(.{ .rgb = .{ 255, 0, 128 } });
    try std.testing.expect(vaxis.Color.eql(c, .{ .rgb = .{ 255, 0, 128 } }));
}

test "toVaxisColor: index" {
    const c = toVaxisColor(.{ .index = 2 });
    try std.testing.expect(vaxis.Color.eql(c, .{ .index = 2 }));
}

test "toVaxisStyle: full round trip" {
    const our: Style = .{
        .fg = .{ .rgb = .{ 100, 180, 255 } },
        .bg = .{ .index = 4 },
        .bold = true,
        .reverse = true,
    };
    const vs = toVaxisStyle(our);
    try std.testing.expect(vs.bold);
    try std.testing.expect(vs.reverse);
    try std.testing.expect(vaxis.Color.eql(vs.fg, .{ .rgb = .{ 100, 180, 255 } }));
    try std.testing.expect(vaxis.Color.eql(vs.bg, .{ .index = 4 }));
}

test "toVaxisStyle: default style" {
    const our: Style = .{};
    const vs = toVaxisStyle(our);
    try std.testing.expect(!vs.bold);
    try std.testing.expect(!vs.reverse);
    try std.testing.expectEqual(vaxis.Color.default, vs.fg);
    try std.testing.expectEqual(vaxis.Color.default, vs.bg);
}
