const vaxis = @import("vaxis");
const game = @import("game.zig");

pub fn handle(self: *game.State, key: vaxis.Key) void {
    if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) {
        self.quit = true;
    } else if (key.matches(vaxis.Key.left, .{}) or key.matches('h', .{})) {
        self.move_cursor(-1, 0);
    } else if (key.matches(vaxis.Key.right, .{}) or key.matches('l', .{})) {
        self.move_cursor(1, 0);
    } else if (key.matches(vaxis.Key.up, .{}) or key.matches('k', .{})) {
        self.move_cursor(0, -1);
    } else if (key.matches(vaxis.Key.down, .{}) or key.matches('j', .{})) {
        self.move_cursor(0, 1);
    }
}