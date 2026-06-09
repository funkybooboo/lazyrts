const std = @import("std");
const vaxis = @import("vaxis");
const game = @import("game.zig");
const input = @import("input.zig");
const render = @import("render.zig");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;

    var buf: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(io, &buf);
    defer tty.deinit();

    var vx = try vaxis.init(io, alloc, init.environ_map, .{});
    defer vx.deinit(alloc, tty.writer());

    var loop: vaxis.Loop(Event) = .init(io, &tty, &vx);
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), .fromSeconds(1));

    var state = game.State.init(42);

    while (!state.quit) {
        const ev = try loop.nextEvent();
        switch (ev) {
            .key_press => |key| input.handle(&state, key),
            .winsize => |ws| try vx.resize(alloc, tty.writer(), ws),
        }
        render.draw(&vx, &state);
        try vx.render(tty.writer());
    }
}