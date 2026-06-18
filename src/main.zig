const std = @import("std");
const game = @import("game.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const term = @import("terminal.zig");
const ti = @import("time.zig");

const TICK_PERIOD_NS = 100_000_000;
const RESIZE_POLL_INTERVAL_NS = 10_000_000;
const FRAME_SLEEP_NS = 1_000_000;
const MIN_FRAME_WIDTH = 20;
const MIN_FRAME_HEIGHT = 15;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;

    var t: term.Terminal = undefined;
    try t.init(io, alloc, init.environ_map);
    defer t.deinit();

    var canvas = t.canvas();
    while (canvas.width() < MIN_FRAME_WIDTH or canvas.height() < MIN_FRAME_HEIGHT) {
        while (try t.poll_event()) |ev| {
            if (ev == .resize) break;
        }
        canvas = t.canvas();
        ti.sleep_ns(RESIZE_POLL_INTERVAL_NS);
    }

    const seed = ti.mono_now();
    var state = game.State.init(seed, canvas.width(), canvas.height());
    var ticker = ti.Ticker{ .period_ns = TICK_PERIOD_NS };

    while (!state.quit) {
        const ticks = ticker.update(ti.mono_now());
        for (0..ticks) |_| game.tick(&state);

        while (try t.poll_event()) |ev| {
            switch (ev) {
                .key_press => |key| input.handle(&state, key),
                .resize => {},
            }
        }

        render.draw(t.canvas(), &state);
        try t.present();

        ti.sleep_ns(FRAME_SLEEP_NS);
    }
}

test {
    _ = game;
    _ = input;
    _ = render;
    _ = term;
    _ = ti;
    _ = @import("color.zig");
}
