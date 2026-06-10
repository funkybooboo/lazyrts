const std = @import("std");
const game = @import("game.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const term = @import("terminal.zig");
const ti = @import("time.zig");

const tick_period_ns: u64 = 100_000_000;
const frame_sleep_ns: u64 = 1_000_000;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;

    var t: term.Terminal = undefined;
    try t.init(io, alloc, init.environ_map);
    defer t.deinit();

    var canvas = t.canvas();
    while (canvas.width() < 20 or canvas.height() < 15) {
        while (try t.poll_event()) |ev| {
            if (ev == .resize) break;
        }
        canvas = t.canvas();
        ti.sleep_ns(10_000_000);
    }

    const seed: u64 = ti.mono_now();
    var state = game.State.init(seed, canvas.width(), canvas.height());
    var ticker = ti.Ticker{ .period_ns = tick_period_ns };

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

        ti.sleep_ns(frame_sleep_ns);
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
