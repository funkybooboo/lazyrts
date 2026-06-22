const std = @import("std");
const coords = @import("coords.zig");

pub const Pos = coords.Pos;

fn itemPos(item: anytype) Pos {
    const T = @TypeOf(item);
    if (@hasField(T, "x") and @hasField(T, "y")) return .{ .x = item.x, .y = item.y };
    if (@hasDecl(T, "pos")) return item.pos();
    @compileError("itemPos requires .x/.y fields or a pos() method");
}

pub fn indexOfAt(items: anytype, x: usize, y: usize) ?usize {
    for (items, 0..) |item, i| {
        const p = itemPos(item);
        if (p.x == x and p.y == y) return i;
    }
    return null;
}

pub fn indexOfAtExcept(items: anytype, x: usize, y: usize, except_idx: usize) ?usize {
    for (items, 0..) |item, i| {
        if (i == except_idx) continue;
        const p = itemPos(item);
        if (p.x == x and p.y == y) return i;
    }
    return null;
}

pub fn collectPositions(items: anytype, out: []Pos) usize {
    var n: usize = 0;
    for (items) |item| {
        if (n >= out.len) break;
        out[n] = itemPos(item);
        n += 1;
    }
    return n;
}

pub fn findIndexNearest(items: anytype, from: Pos, radius: usize) ?usize {
    var best: ?usize = null;
    var best_d: usize = std.math.maxInt(usize);
    for (items, 0..) |item, i| {
        const d = coords.manhattan(from, itemPos(item));
        if (d > radius) continue;
        if (d < best_d) {
            best_d = d;
            best = i;
        }
    }
    return best;
}

pub fn findIndexNearestWhere(items: anytype, from: Pos, radius: usize, predicate: anytype) ?usize {
    var best: ?usize = null;
    var best_d: usize = std.math.maxInt(usize);
    for (items, 0..) |item, i| {
        if (!predicate(item)) continue;
        const d = coords.manhattan(from, itemPos(item));
        if (d > radius) continue;
        if (d < best_d) {
            best_d = d;
            best = i;
        }
    }
    return best;
}

pub fn findFirstWhere(items: anytype, predicate: anytype) ?usize {
    for (items, 0..) |item, i| {
        if (predicate(item)) return i;
    }
    return null;
}

pub fn countWhere(items: anytype, predicate: anytype) usize {
    var n: usize = 0;
    for (items) |item| {
        if (predicate(item)) n += 1;
    }
    return n;
}

pub fn sumWhere(items: anytype, ctx: anytype, value_fn: anytype, predicate: anytype) usize {
    var sum: usize = 0;
    for (items) |item| {
        if (predicate(item)) sum += value_fn(ctx, item);
    }
    return sum;
}

pub fn findNearestPosWhere(ctx: anytype, from: Pos, radius: usize, predicate: anytype) ?Pos {
    var best: ?Pos = null;
    var best_d: usize = std.math.maxInt(usize);
    var dy: isize = -@as(isize, @intCast(radius));
    while (dy <= @as(isize, @intCast(radius))) : (dy += 1) {
        var dx: isize = -@as(isize, @intCast(radius));
        while (dx <= @as(isize, @intCast(radius))) : (dx += 1) {
            const tx = @as(isize, @intCast(from.x)) + dx;
            const ty = @as(isize, @intCast(from.y)) + dy;
            if (tx < 0 or ty < 0) continue;
            const p: Pos = .{ .x = @intCast(tx), .y = @intCast(ty) };
            if (!predicate(ctx, p)) continue;
            const d = coords.manhattan(from, p);
            if (d < best_d) {
                best_d = d;
                best = p;
            }
        }
    }
    return best;
}

const PosStruct = struct { x: usize, y: usize, tag: u8 = 0 };
const PosMethod = struct {
    px: usize,
    py: usize,
    tag: u8 = 0,

    fn pos(self: PosMethod) Pos {
        return .{ .x = self.px, .y = self.py };
    }
};

test "itemPos: struct with x/y fields" {
    const p = itemPos(PosStruct{ .x = 3, .y = 7 });
    try std.testing.expectEqual(@as(usize, 3), p.x);
    try std.testing.expectEqual(@as(usize, 7), p.y);
}

test "itemPos: struct with pos() method" {
    const p = itemPos(PosMethod{ .px = 5, .py = 9 });
    try std.testing.expectEqual(@as(usize, 5), p.x);
    try std.testing.expectEqual(@as(usize, 9), p.y);
}

test "indexOfAt: finds matching item" {
    const items = [_]PosStruct{ .{ .x = 3, .y = 7 }, .{ .x = 25, .y = 30 } };
    try std.testing.expectEqual(@as(?usize, 0), indexOfAt(&items, 3, 7));
    try std.testing.expectEqual(@as(?usize, 1), indexOfAt(&items, 25, 30));
    try std.testing.expect(indexOfAt(&items, 0, 0) == null);
}

test "indexOfAt: works with pos() method type" {
    const items = [_]PosMethod{ .{ .px = 3, .py = 7 }, .{ .px = 25, .py = 30 } };
    try std.testing.expectEqual(@as(?usize, 0), indexOfAt(&items, 3, 7));
    try std.testing.expectEqual(@as(?usize, 1), indexOfAt(&items, 25, 30));
}

test "indexOfAtExcept: skips specified index" {
    const items = [_]PosStruct{ .{ .x = 5, .y = 5 }, .{ .x = 5, .y = 5 } };
    try std.testing.expectEqual(@as(?usize, 0), indexOfAt(&items, 5, 5));
    try std.testing.expectEqual(@as(?usize, 1), indexOfAtExcept(&items, 5, 5, 0));
    try std.testing.expectEqual(@as(?usize, 0), indexOfAtExcept(&items, 5, 5, 1));
}

test "collectPositions: fills buffer with positions" {
    const items = [_]PosStruct{ .{ .x = 1, .y = 2 }, .{ .x = 3, .y = 4 }, .{ .x = 5, .y = 6 } };
    var out: [4]Pos = undefined;
    const n = collectPositions(&items, &out);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqual(@as(usize, 1), out[0].x);
    try std.testing.expectEqual(@as(usize, 6), out[2].y);
}

test "collectPositions: truncates at buffer len" {
    const items = [_]PosStruct{ .{ .x = 1, .y = 2 }, .{ .x = 3, .y = 4 }, .{ .x = 5, .y = 6 } };
    var out: [2]Pos = undefined;
    const n = collectPositions(&items, &out);
    try std.testing.expectEqual(@as(usize, 2), n);
    try std.testing.expectEqual(@as(usize, 3), out[1].x);
}

test "findIndexNearest: returns closest within radius" {
    const items = [_]PosStruct{ .{ .x = 10, .y = 10 }, .{ .x = 12, .y = 12 }, .{ .x = 50, .y = 50 } };
    try std.testing.expectEqual(@as(?usize, 0), findIndexNearest(&items, .{ .x = 10, .y = 10 }, 100));
    try std.testing.expectEqual(@as(?usize, 1), findIndexNearest(&items, .{ .x = 13, .y = 13 }, 100));
}

test "findIndexNearest: radius excludes far items" {
    const items = [_]PosStruct{ .{ .x = 10, .y = 10 }, .{ .x = 50, .y = 50 } };
    try std.testing.expectEqual(@as(?usize, 0), findIndexNearest(&items, .{ .x = 10, .y = 10 }, 5));
    try std.testing.expect(findIndexNearest(&items, .{ .x = 0, .y = 0 }, 5) == null);
}

test "findIndexNearest: empty slice returns null" {
    const items = [_]PosStruct{};
    try std.testing.expect(findIndexNearest(&items, .{ .x = 0, .y = 0 }, 100) == null);
}

fn isTagOne(item: PosStruct) bool {
    return item.tag == 1;
}

test "findIndexNearestWhere: respects predicate" {
    const items = [_]PosStruct{
        .{ .x = 10, .y = 10, .tag = 0 },
        .{ .x = 12, .y = 12, .tag = 1 },
        .{ .x = 50, .y = 50, .tag = 1 },
    };
    try std.testing.expectEqual(@as(?usize, 1), findIndexNearestWhere(&items, .{ .x = 10, .y = 10 }, 100, isTagOne));
    try std.testing.expect(findIndexNearestWhere(&items, .{ .x = 10, .y = 10 }, 1, isTagOne) == null);
}

test "findIndexNearestWhere: empty slice returns null" {
    const items = [_]PosStruct{};
    try std.testing.expect(findIndexNearestWhere(&items, .{ .x = 0, .y = 0 }, 100, isTagOne) == null);
}

test "findFirstWhere: returns first matching index" {
    const items = [_]PosStruct{ .{ .x = 1, .y = 1, .tag = 0 }, .{ .x = 2, .y = 2, .tag = 1 }, .{ .x = 3, .y = 3, .tag = 1 } };
    try std.testing.expectEqual(@as(?usize, 1), findFirstWhere(&items, isTagOne));
}

test "findFirstWhere: no match returns null" {
    const items = [_]PosStruct{ .{ .x = 1, .y = 1, .tag = 0 } };
    try std.testing.expect(findFirstWhere(&items, isTagOne) == null);
}

fn isTagOneCount(item: PosStruct) bool {
    return item.tag == 1;
}

test "countWhere: counts matching items" {
    const items = [_]PosStruct{ .{ .x = 1, .y = 1, .tag = 0 }, .{ .x = 2, .y = 2, .tag = 1 }, .{ .x = 3, .y = 3, .tag = 1 } };
    try std.testing.expectEqual(@as(usize, 2), countWhere(&items, isTagOneCount));
    try std.testing.expectEqual(@as(usize, 1), countWhere(&items, isTagZero));
    try std.testing.expectEqual(@as(usize, 0), countWhere(&[_]PosStruct{}, isTagOneCount));
}

fn isTagZero(item: PosStruct) bool {
    return item.tag == 0;
}

fn valueOfTag(item: PosStruct) usize {
    return @as(usize, item.tag) + 1;
}

test "sumWhere: sums value_fn over matching items" {
    const items = [_]PosStruct{ .{ .x = 1, .y = 1, .tag = 0 }, .{ .x = 2, .y = 2, .tag = 1 }, .{ .x = 3, .y = 3, .tag = 1 } };
    const ctx: usize = 0;
    const valueOfTagC = struct {
        fn call(_: usize, item: PosStruct) usize {
            return @as(usize, item.tag) + 1;
        }
    }.call;
    try std.testing.expectEqual(@as(usize, 4), sumWhere(&items, ctx, valueOfTagC, isTagOneCount));
}

const isEvenRowCtx = struct {
    fn call(_: void, p: Pos) bool {
        return p.y % 2 == 0;
    }
}.call;

test "findNearestPosWhere: finds nearest matching position" {
    const near = findNearestPosWhere({}, .{ .x = 5, .y = 5 }, 3, isEvenRowCtx).?;
    try std.testing.expectEqual(@as(usize, 5), near.x);
    try std.testing.expectEqual(@as(usize, 4), near.y);
}

test "findNearestPosWhere: nothing in radius returns null" {
    const isFarAway = struct {
        fn call(_: void, p: Pos) bool {
            return p.x > 100;
        }
    }.call;
    try std.testing.expect(findNearestPosWhere({}, .{ .x = 5, .y = 5 }, 3, isFarAway) == null);
}
