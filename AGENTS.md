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
- Every public function on a struct takes `self` as first param: `pub fn foo(self: *State, ...)`.
- Use `usize` for tile coordinates, `isize` for deltas. Clamp at bounds, never underflow.
- Zig errors (`!void`) for things that can actually fail (I/O, allocation). `assert` for programmer bugs.
- `pub` only on what other modules need. Everything else is file-private.

## Module Responsibilities

### main.zig
Entry point. Owns the vaxis event loop. Dispatches:
- `key_press` -> `input.handle()`
- `winsize` -> `vx.resize()`
Then calls `render.draw()`. Does not contain game logic.

### game.zig
`State` struct -- the single source of truth. All game data lives here.
- Cursor position, quit flag, world map, resources, entities, etc.
- `init(seed)` creates a State with a fresh map
- `move_cursor()` -- pure logic, tested
- Milestone 2 adds: `tick()`, entity lists, resource counters
- Milestone 3 adds: economy state
- Every milestone adds fields here

### map.zig
`Tile` enum and `GameMap` struct. Pure data, no rendering knowledge.
- `Tile.glyph()` returns the character. `Tile` does NOT know about colors.
- `GameMap.init(seed)` generates terrain with two TC starts
- `GameMap.at(x, y)` with bounds check (returns `.water` for OOB)
- Color/style is in `render.zig`, never in `map.zig`

### input.zig
Key-to-state-mutation bridge. Takes `*State` and a `vaxis.Key`, mutates state.
One public function: `handle(*State, vaxis.Key)`.
No rendering, no I/O.

### render.zig
Takes `*vaxis.Vaxis` and `*const State`, draws the frame.
- `draw()` is the only public function.
- `tile_style()` maps `Tile` -> `vaxis.Style` (colors live here).
- No state mutation. Pure rendering.

## Adding a New Module (from milestone 2 onward)

The spec lists these upcoming modules:
```
entity.zig       Worker / Soldier / Building, owner, hp, state
command.zig      order queue: move, gather, build, attack
pathfinding.zig  A* on tile grid
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