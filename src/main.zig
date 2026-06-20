const std = @import("std");
const game = @import("game.zig");
const input = @import("input.zig");
const render = @import("render.zig");
const terminal = @import("terminal.zig");
const time = @import("time.zig");
const config = @import("config.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;

    const cfg = config.default();

    var t: terminal.Terminal = undefined;
    try t.init(io, alloc, init.environ_map);
    defer t.deinit();

    var canvas = t.canvas();
    while (canvas.width() < cfg.map_dims.min_term_width or canvas.height() < cfg.map_dims.min_term_height) {
        while (try t.poll_event()) |ev| {
            if (ev == .resize) break;
        }
        canvas = t.canvas();
        time.sleep_ns(cfg.timing.resize_poll_interval_ns);
    }

    const seed = time.mono_now();
    var state = try game.State.init(alloc, seed, canvas.width(), canvas.height(), &cfg);
    defer state.deinit();
    var ticker = time.Ticker{ .period_ns = cfg.timing.tick_period_ns };

    while (!state.quit) {
        const ticks = ticker.update(time.mono_now());
        for (0..ticks) |_| game.tick(&state);

        while (try t.poll_event()) |ev| {
            switch (ev) {
                .key_press => |key| input.handle(&state, key),
                .resize => {},
            }
        }

        render.draw(t.canvas(), &state);
        try t.present();

        time.sleep_ns(cfg.timing.frame_sleep_ns);
    }
}

test {
    _ = game;
    _ = input;
    _ = render;
    _ = terminal;
    _ = time;
    _ = @import("color.zig");
    _ = @import("fmt.zig");
}
