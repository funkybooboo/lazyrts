# AGENTS.md -- lazyrts

Coding conventions and module guide for contributors (human or AI).

## Build Commands

```bash
zig build          # compile
zig build run      # run the game
zig build test     # run unit tests
```

Zig 0.16.0 required. Managed via mise.

## Code Style

- No comments unless the *why* is non-obvious. Code should read itself.
- No heap allocation in the hot path. `game.State` is stack-allocated.
- Every public function on a struct takes `self` as first param: `pub fn foo(self: *Struct, ...)`. Exception: `game.zig` uses free functions, not methods on State, to separate data from logic.
- Use `usize` for tile coordinates, `isize` for deltas. Clamp at bounds, never underflow.
- Zig errors (`!void`) for things that can actually fail (I/O, allocation). `assert` for programmer bugs.
- `pub` only on what other modules need. Everything else is file-private.

## Module Responsibilities

### main.zig
Entry point. Owns the terminal event loop. Dispatches:
- `key_press` -> `input.handle()`
- `resize` -> ignored (terminal handles internally)
Uses `time.Ticker` for 10 Hz tick. Calls `render.draw()`. Does not contain game logic.
`test` block references all modules so `zig build test` discovers their tests.

### game.zig
`State` struct -- pure data, no methods except `init(seed)`. All game logic is free functions.
- State fields: cursor position, quit flag, world map, unit list, building list, selected_unit
- `init(seed)` creates State with fresh map + both TCs registered as buildings
- Free functions: `moveCursor`, `tick`, `spawnWorker`, `spawnUnit`, `moveSelected`, `selectNext`, `unitAt`, `buildingAt`, `playerTC`
- `spawnUnit(kind, owner, cx, cy)` -- parameterized for AI use (milestone 7)
- `findSpawn` is file-private, takes `*const GameMap` not `*State`
- `playerTC` finds player TC position from buildings array
- Every milestone adds fields + functions here

### map.zig
`Tile` enum and `GameMap` struct. Pure data, no rendering knowledge.
- `Tile.glyph()` returns the character. `Tile` does NOT know about colors.
- `Tile.isWalkable()` answers whether an entity can stand on that tile.
- `GameMap.init(seed)` generates terrain with two TC starts
- `GameMap.at(x, y)` with bounds check (returns `.water` for OOB)
- `GameMap.isWalkable(x, y)` delegates to `Tile.isWalkable()` with bounds check
- TC positions as named constants: `PLAYER_TC_X/Y`, `ENEMY_TC_X/Y`, `TC_CLEAR_RADIUS`
- No entity tiles (`.worker`, `.soldier`). Entities are separate from terrain.
- Color/style lives in `render.zig`, never in `map.zig`

### entity.zig
`Unit` and `Building` types + shared types. Pure data + `Unit.step()` movement.
- `Pos` -- 2D coordinate, `x`/`y` as `usize`
- `Owner` -- `player` or `enemy`
- `UnitKind` -- `worker` or `soldier`, with `glyph()` and `maxHp()`
- `BuildingKind` -- `town_center`, `house`, `barracks`, `farm`, with `glyph()` and `maxHp()`
- `UnitState` -- `idle` or `moving`
- `Unit` -- x, y, kind, owner, hp, state, path. `pos()`, `step()` methods.
- `Building` -- x, y, kind, owner, hp. No movement.
- `MAX_PATH`, `MAX_UNITS`, `MAX_BUILDINGS` -- constants

### pathfinding.zig
A* on the tile grid. Uses `GameMap.isWalkable()` for passability.
- `findPath(map, start, goal, out_path) ?usize` -- returns path length or null
- Stack-allocated working set (no heap).
- Tested on straight line, obstacles, unreachable, same-tile, unwalkable goal.

### time.zig
Monotonic clock and tick accumulator.
- `monoNow() u64` -- current time in nanoseconds (CLOCK_MONOTONIC)
- `sleepNs(ns)` -- nanosleep wrapper
- `Ticker` struct -- accumulates elapsed time, fires ticks at fixed period
- `Ticker.update(now) usize` -- returns number of ticks to process

### input.zig
Key-to-state-mutation bridge. Takes `*State` and a `term.Key`, mutates state.
One public function: `handle(*State, term.Key)`.
No rendering, no I/O.

### render.zig
Takes a `term.Canvas` and `*const State`, draws the frame.
- `draw()` is the only public function.
- `tileStyle()` and `entityStyle()` map data to visual style.
- Uses `game.entityAt()` for entity overlay.
- No state mutation. Pure rendering.

### terminal.zig
Wrapper around vaxis. Own types for Color, Style, Key, Event, Canvas, Terminal.
- `Color` -- `default`, `rgb`, `index` (no vaxis dependency in our API)
- `Style` -- `fg`, `bg`, `bold`, `reverse` only
- `Key` -- `kind` (char/arrow/tab/enter/escape/unknown), `char_val`, `ctrl`. Query methods: `isChar`, `isCtrl`, `isLeft`, etc.
- `Event` -- `key_press` or `resize`
- `Canvas` -- `clear`, `writeCell`, `width`, `height`
- `Terminal` -- `init`, `deinit`, `pollEvent`, `canvas`, `present`
- Conversion functions `fromVaxisKey`, `toVaxisStyle`, `toVaxisColor` tested against vaxis types.
- If vaxis breaks on upgrade, these tests fail immediately.

## Adding a New Module (from milestone 3 onward)

The spec lists these upcoming modules:
```
command.zig      order queue: move, gather, build, attack
combat.zig       adjacency damage per tick
economy.zig      resource counters, drop-off, pop cap
ai.zig           scripted opponent
```

When adding one:
1. Put it in `src/`. Import in `game.zig` or `main.zig` as needed.
2. Pure logic goes in the module. Tests go in the same file.
3. `game.State` gains the new fields. Other modules read/update `*State`.
4. `input.zig` gains key bindings. `render.zig` gains display code.
5. Run `zig build test` before declaring done.

## Testing Rules

- Unit tests on pure logic only: state mutations, map lookups, pathfinding, combat math, AI transitions
- No render tests. Verify visually.
- Each test file lives alongside its module (e.g., tests in `map.zig` test `GameMap`)
- Tests must pass with `zig build test`
- Every milestone adds tests for its new pure-logic functions

## Milestone Workflow

1. Read `roadmap.md` for the current milestone's definition of done
2. Implement the feature across the relevant modules
3. Add unit tests for all new pure-logic functions
4. Run `zig build && zig build test`
5. Run `zig build run` and playtest manually
6. If it isn't fun-ish, fix that before moving on
7. Update roadmap.md checkboxes

## Git Conventions

- Small commits. Commit early, commit often.
- Don't commit unless asked.
- Don't commit secrets, .zig-cache, zig-out, or zig-pkg.