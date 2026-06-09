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

    pub fn is_char(self: Key, ch: u8) bool {
        return !self.ctrl and self.kind == .char and self.char_val == ch;
    }

    pub fn is_ctrl(self: Key, ch: u8) bool {
        return self.ctrl and self.kind == .char and self.char_val == ch;
    }

    pub fn is_left(self: Key) bool {
        return self.kind == .left;
    }

    pub fn is_right(self: Key) bool {
        return self.kind == .right;
    }

    pub fn is_up(self: Key) bool {
        return self.kind == .up;
    }

    pub fn is_down(self: Key) bool {
        return self.kind == .down;
    }

    pub fn is_tab(self: Key) bool {
        return self.kind == .tab;
    }

    pub fn is_enter(self: Key) bool {
        return self.kind == .enter;
    }

    pub fn is_escape(self: Key) bool {
        return self.kind == .escape;
    }
};

pub const Event = union(enum) {
    key_press: Key,
    resize,
};

pub const Canvas = struct {
    win: vaxis.Window,

    pub fn clear(self: Canvas) void {
        self.win.clear();
    }

    pub fn width(self: Canvas) u16 {
        return self.win.width;
    }

    pub fn height(self: Canvas) u16 {
        return self.win.height;
    }

    pub fn write_cell(self: Canvas, x: u16, y: u16, glyph: []const u8, s: Style) void {
        self.win.writeCell(x, y, .{
            .char = .{ .grapheme = glyph },
            .style = to_vaxis_style(s),
        });
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

    pub fn poll_event(self: *Terminal) !?Event {
        const vev = try self.loop.tryEvent() orelse return null;
        return switch (vev) {
            .key_press => |vk| Event{ .key_press = from_vaxis_key(vk) },
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

fn from_vaxis_key(vk: vaxis.Key) Key {
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
    };
}

fn to_vaxis_style(s: Style) vaxis.Style {
    return .{
        .fg = to_vaxis_color(s.fg),
        .bg = to_vaxis_color(s.bg),
        .bold = s.bold,
        .reverse = s.reverse,
    };
}

fn to_vaxis_color(c: Color) vaxis.Color {
    return switch (c) {
        .default => .default,
        .rgb => |rgb| .{ .rgb = rgb },
        .index => |i| .{ .index = i },
    };
}

test "from_vaxis_key: printable char" {
    const vk: vaxis.Key = .{ .codepoint = 'q' };
    const k = from_vaxis_key(vk);
    try std.testing.expect(k.is_char('q'));
    try std.testing.expect(!k.is_ctrl('q'));
    try std.testing.expect(!k.is_left());
}

test "from_vaxis_key: ctrl+c" {
    const vk: vaxis.Key = .{ .codepoint = 'c', .mods = .{ .ctrl = true } };
    const k = from_vaxis_key(vk);
    try std.testing.expect(k.is_ctrl('c'));
    try std.testing.expect(!k.is_char('c'));
}

test "from_vaxis_key: arrow keys" {
    try std.testing.expectEqual(Key.KeyKind.left, from_vaxis_key(.{ .codepoint = vaxis.Key.left }).kind);
    try std.testing.expectEqual(Key.KeyKind.right, from_vaxis_key(.{ .codepoint = vaxis.Key.right }).kind);
    try std.testing.expectEqual(Key.KeyKind.up, from_vaxis_key(.{ .codepoint = vaxis.Key.up }).kind);
    try std.testing.expectEqual(Key.KeyKind.down, from_vaxis_key(.{ .codepoint = vaxis.Key.down }).kind);
}

test "from_vaxis_key: tab" {
    const k = from_vaxis_key(.{ .codepoint = vaxis.Key.tab });
    try std.testing.expect(k.is_tab());
}

test "from_vaxis_key: enter" {
    const k = from_vaxis_key(.{ .codepoint = vaxis.Key.enter });
    try std.testing.expect(k.is_enter());
}

test "from_vaxis_key: escape" {
    const k = from_vaxis_key(.{ .codepoint = vaxis.Key.escape });
    try std.testing.expect(k.is_escape());
}

test "from_vaxis_key: unknown key" {
    const k = from_vaxis_key(.{ .codepoint = 99999 });
    try std.testing.expectEqual(Key.KeyKind.unknown, k.kind);
}

test "to_vaxis_color: default" {
    const c = to_vaxis_color(.default);
    try std.testing.expectEqual(vaxis.Color.default, c);
}

test "to_vaxis_color: rgb" {
    const c = to_vaxis_color(.{ .rgb = .{ 255, 0, 128 } });
    try std.testing.expect(vaxis.Color.eql(c, .{ .rgb = .{ 255, 0, 128 } }));
}

test "to_vaxis_color: index" {
    const c = to_vaxis_color(.{ .index = 2 });
    try std.testing.expect(vaxis.Color.eql(c, .{ .index = 2 }));
}

test "to_vaxis_style: full round trip" {
    const our: Style = .{
        .fg = .{ .rgb = .{ 100, 180, 255 } },
        .bg = .{ .index = 4 },
        .bold = true,
        .reverse = true,
    };
    const vs = to_vaxis_style(our);
    try std.testing.expect(vs.bold);
    try std.testing.expect(vs.reverse);
    try std.testing.expect(vaxis.Color.eql(vs.fg, .{ .rgb = .{ 100, 180, 255 } }));
    try std.testing.expect(vaxis.Color.eql(vs.bg, .{ .index = 4 }));
}

test "to_vaxis_style: default style" {
    const our: Style = .{};
    const vs = to_vaxis_style(our);
    try std.testing.expect(!vs.bold);
    try std.testing.expect(!vs.reverse);
    try std.testing.expectEqual(vaxis.Color.default, vs.fg);
    try std.testing.expectEqual(vaxis.Color.default, vs.bg);
}
