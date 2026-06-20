# AGENTS.md -- lazyrts

Coding conventions and module guide for contributors (human or AI).

## Build Commands

```sh
zig build          # compile
zig build run      # run the game
zig build test     # run unit tests
```

Zig 0.16.0 required. Managed via mise.

## Code Style

- No comments unless the *why* is non-obvious. Code should read itself.
- No heap allocation in the hot path. `game.State` is stack-allocated.
- Every public function on a struct takes `self` as first param:
  `pub fn foo(self: *Struct, ...)`. Exception: `game.zig` uses free
  functions, not methods on State, to separate data from logic.
- Use `usize` for tile coordinates, `isize` for deltas. Clamp at
  bounds, never underflow.
- Zig errors (`!void`) for things that can actually fail (I/O,
  allocation). `assert` for programmer bugs.
- `pub` only on what other modules need. Everything else is
  file-private.

## Module Responsibilities

### main.zig

Entry point. Owns the terminal event loop. Dispatches:

- `key_press` -> `input.handle()`
- `resize` -> ignored (terminal handles internally)

Uses `time.Ticker` for tick rate from `config.zig`. Calls `render.draw()`. Does not
contain game logic. `test` block references all modules so
`zig build test` discovers their tests.

### config.zig

Single source of truth for all constants and configuration values.

- All numeric constants, colors, sizes, limits live here
- Organized by domain: `tick_rate`, `map_dims`, `entity_limits`, `unit_hp`, `building_hp`, `deer`, `map_gen`, `ui`, `timing`, `colors`
- Other modules import and re-export as aliases for backward compatibility
- Testable: can override values for testing by importing config directly
- No runtime overhead: all values are compile-time constants

### game.zig

`State` struct -- pure data, no methods except `init(seed)`. All game
logic is free functions.

- State fields: cursor position, quit flag, world map, unit list,
  building list, selected_units (multiselect), gather mode state
- `init(seed)` creates State with fresh map + both TCs registered as
  buildings
- Free functions: `moveCursor`, `tick`, `spawnWorker`, `spawnUnit`,
  `moveSelected`, `selectNext`, `selectIdleWorkers`,
  `selectAllWorkers`, `selectIdleFighters`, `selectAllFighters`,
  `selectNextBuilding`, `unitAt`, `buildingAt`, `playerTC`
- Workers have persistent task states: gathering_wood,
  gathering_food, hunting, constructing
- `spawnUnit(kind, owner, cx, cy)` -- parameterized for AI use
  (milestone 8)
- `findSpawn` is file-private, takes `*const GameMap` not `*State`
- `playerTC` finds player TC position from buildings array
- Every milestone adds fields + functions here

### map.zig

`Tile` enum and `GameMap` struct. Pure data, no rendering knowledge.

- `Tile.glyph()` returns the character. `Tile` does NOT know about
  colors.
- `Tile.isWalkable()` answers whether an entity can stand on that
  tile.
- `GameMap.init(seed)` generates terrain with two TC starts
- `GameMap.at(x, y)` with bounds check (returns `.water` for OOB)
- `GameMap.isWalkable(x, y)` delegates to `Tile.isWalkable()` with
  bounds check
- TC positions as named constants: `PLAYER_TC_X/Y`,
  `ENEMY_TC_X/Y`, `TC_CLEAR_RADIUS`
- No entity tiles (`.worker`, `.soldier`). Entities are separate
  from terrain.
- Color/style lives in `render.zig`, never in `map.zig`

### entity.zig

`Unit` and `Building` types + shared types. Pure data + `Unit.step()`
movement.

- `Pos` -- 2D coordinate, `x`/`y` as `usize`
- `Owner` -- `player` or `enemy` or `neutral`
- `UnitKind` -- `worker` or `soldier` or `deer`, with `glyph()` and
  `maxHp()`
- `BuildingKind` -- `town_center`, `house`, `barracks`, `farm`,
  `drop_pile`, with `glyph()`, `maxHp()`, `label()`, `cost()`,
  `size()`, `damage_to()`
- `UnitState` -- `idle`, `moving`, `gathering_wood`,
  `gathering_food`, `hunting`, `constructing`
- `Unit` -- x, y, kind, owner, hp, state, path, gather_target.
  `pos()`, `step()` methods.
- Units regenerate 1 HP per 30 ticks, pauses 5 ticks after taking
  damage. Workers fight at 3 dmg, soldiers at 8 dmg.
- `Building` -- x, y, kind, owner, hp, build_progress. Multi-tile
  (TC 3x3, House 2x2, Barracks 2x3, Farm 3x3, DropPile 1x1).
  Repairable for 1/2 original wood cost.
- One unit per tile, no stacking. Units must path around each other.
- Building costs: House=30w, Barracks=25f+50w, Farm=60w,
  DropPile=50w, FarmResow=60w
- Unit costs: Worker=50f, Soldier=60f+20w
- Resource yields: Tree=100w, Farm=250f (then fallow), Deer=100f
- `MAX_PATH`, `MAX_UNITS`, `MAX_BUILDINGS` -- constants

### pathfinding.zig

A* on the tile grid. Uses `GameMap.isWalkable()` for passability.

- `findPath(map, start, goal, out_path) ?usize` -- returns path
  length or null
- Stack-allocated working set (no heap).
- Tested on straight line, obstacles, unreachable, same-tile,
  unwalkable goal.

### time.zig

Monotonic clock and tick accumulator.

- `monoNow() u64` -- current time in nanoseconds (CLOCK_MONOTONIC)
- `sleepNs(ns)` -- nanosleep wrapper
- `Ticker` struct -- accumulates elapsed time, fires ticks at fixed
  period
- `Ticker.update(now) usize` -- returns number of ticks to process

### input.zig

Key-to-state-mutation bridge. Takes `*State` and a `term.Key`, mutates
state. One public function: `handle(*State, term.Key)`.

Key bindings (current and planned):

- hjkl / arrows: move cursor
- Q / Ctrl-C: quit
- T: spawn worker at TC
- M: move selected unit to cursor
- Tab: cycle player units
- Shift+Tab: cycle player buildings
- G: gather (persistent task -- wood, deer, farm)
- J: cursor jump (coordinate input mode)
- W: select all idle workers
- Shift+W: select all workers
- F: select all idle fighters
- Shift+F: select all fighters
- Shift+direction: add unit to selection (multiselect)
- B: build menu (H=House, F=Farm, D=Drop Pile, R=Barracks)
- E: repair selected building
- R: resow fallow farm (60 wood)
- A: attack-move (milestone 6)

No rendering, no I/O.

### render.zig

Takes a `term.Canvas` and `*const State`, draws the frame.

- `draw()` is the only public function.
- `tileStyle()` and `entityStyle()` map data to visual style.
- Uses `game.entityAt()` for entity overlay.
- Fog of war: unexplored tiles render as unknown, explored tiles dim,
  visible tiles bright (milestone 7)
- No state mutation. Pure rendering.

### terminal.zig

Wrapper around vaxis. Own types for Color, Style, Key, Event, Canvas,
Terminal.

- `Color` -- `default`, `rgb`, `index` (no vaxis dependency in our
  API)
- `Style` -- `fg`, `bg`, `bold`, `reverse` only
- `Key` -- `kind` (char/arrow/tab/enter/escape/unknown), `char_val`,
  `ctrl`. Query methods: `isChar`, `isCtrl`, `isLeft`, etc.
- `Event` -- `key_press` or `resize`
- `Canvas` -- `clear`, `writeCell`, `width`, `height`
- `Terminal` -- `init`, `deinit`, `pollEvent`, `canvas`, `present`
- Conversion functions `fromVaxisKey`, `toVaxisStyle`,
  `toVaxisColor` tested against vaxis types.
- If vaxis breaks on upgrade, these tests fail immediately.

## Adding a New Module (from milestone 3 onward)

The spec lists these upcoming modules:

```text
command.zig      order queue: move, gather, build, attack
economy.zig      resource counters, drop-off, pop cap, persistent tasks
combat.zig       adjacency damage per tick, unit regeneration
fog.zig          visibility, explored tiles, vision range
ai.zig           reactive opponent (event-driven, strategy-switching)
```

When adding one:

1. Put it in `src/`. Import in `game.zig` or `main.zig` as needed.
2. Pure logic goes in the module. Tests go in the same file.
3. `game.State` gains the new fields. Other modules read/update
   `*State`.
4. `input.zig` gains key bindings. `render.zig` gains display code.
5. Run `zig build test` before declaring done.

## Milestones

1. Empty world
2. One worker
3. Economy (persistent gather, drop piles)
4. Buildings (construct, repair, multi-tile)
5. Military (training, selection shortcuts)
6. Combat (all units fight, regeneration)
7. Fog of war (exploration, vision)
8. AI (reactive, strategy-switching)
9. Win/lose (TC destruction, restart)
10. Multiplayer (human vs human)

## Testing Rules

- Unit tests on pure logic only: state mutations, map lookups,
  pathfinding, combat math, AI transitions
- No render tests. Verify visually.
- Each test file lives alongside its module (e.g., tests in
  `map.zig` test `GameMap`)
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
