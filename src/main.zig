const std = @import("std");
const state_mod = @import("game/state.zig");
const tick_mod = @import("game/tick.zig");
const input = @import("ui/input.zig");
const render = @import("ui/board.zig");
const terminal = @import("lib/terminal.zig");
const time = @import("lib/time.zig");
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
        while (try t.pollEvent()) |ev| {
            if (ev == .resize) break;
        }
        canvas = t.canvas();
        time.sleepNs(cfg.timing.resize_poll_interval_ns);
    }

    const seed = time.monoNow();
    var state = try state_mod.State.init(alloc, seed, canvas.width(), canvas.height(), &cfg);
    defer state.deinit();
    var ticker = time.Ticker{ .period_ns = cfg.timing.tick_period_ns };

    while (!state.quit) {
        const ticks = ticker.update(time.monoNow());
        for (0..ticks) |_| tick_mod.tick(&state);

        while (try t.pollEvent()) |ev| {
            switch (ev) {
                .key_press => |key| input.handle(&state, key),
                .resize => {},
            }
        }

        render.draw(t.canvas(), &state);
        try t.present();

        time.sleepNs(cfg.timing.frame_sleep_ns);
    }
}

test {
    _ = state_mod;
    _ = input;
    _ = render;
    _ = terminal;
    _ = time;
    _ = @import("lib/fmt.zig");
    _ = @import("lib/color.zig");
    _ = @import("lib/coords.zig");
    _ = @import("ui/color.zig");
    _ = @import("ui/header.zig");
    _ = @import("ui/footer.zig");
    _ = @import("game/economy.zig");
    _ = @import("lib/pathfinding.zig");
    _ = @import("lib/spatial.zig");
    _ = @import("game/movement.zig");
    _ = @import("game/tick.zig");
    _ = @import("game/training.zig");
    _ = @import("game/notify.zig");
    _ = @import("resources/wildlife.zig");
    _ = @import("resources/deer.zig");
    _ = @import("resources/tree.zig");
    _ = @import("resources/resource.zig");
    _ = @import("buildings/building.zig");
    _ = @import("buildings/town_center.zig");
    _ = @import("buildings/house.zig");
    _ = @import("buildings/barracks.zig");
    _ = @import("buildings/farm.zig");
    _ = @import("buildings/drop_pile.zig");
    _ = @import("units/worker.zig");
    _ = @import("units/soldier.zig");
}
