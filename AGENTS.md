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
- Organized by domain: `tick_rate`, `pop_per_housing`, `economy`,
  `selection`, `map_dims`, `entity_limits`, `unit_hp`, `nature_hp`,
  `building_hp`, `deer`, `map_gen`, `ui`, `timing`, `colors`
- `economy` block: yields, carry capacity, gather timers, hunt
  radius, resow cost
- Testable: can override values for testing by importing config directly
- No runtime overhead: all values are compile-time constants

### game.zig

`State` struct -- pure data, no methods except `init(seed)`. All game
logic is free functions.

- State fields: cursor position, quit flag, world map, unit list,
  building list, nature list, selection (multiselect list +
  selected_building), food/wood counters, coord_mode, gather_mode
- `init(seed)` creates State with fresh map + both TCs + starting
  workers + starting player farm + deer herds
- Free functions: `move_cursor`, `tick`, `spawn_worker`, `spawn_unit`,
  `move_selected`, `select_next`/`select_prev`, `select_single`,
  `select_add`, `select_clear`, `select_idle_workers`,
  `select_all_workers`, `select_next_building`/`select_prev_building`,
  `is_unit_selected`, `primary_selected`, `gather_at_cursor`,
  `gather_nearest`, `resow_selected`, `player_tc`, `player_pop`,
  `player_pop_cap`, `elapsed_seconds`
- `tick()` dispatches moving units vs gather-state units to
  `economy.tick_unit`
- Deer spawn in herds: one near each TC, rest scattered with
  min spacing between herd centers
- `spawn_unit(kind, owner, cx, cy)` -- parameterized for AI use
  (milestone 8)
- `find_spawn` is file-private
- `player_tc` finds player TC position from buildings array

### map.zig

`Tile` enum and `GameMap` struct. Pure data, no rendering knowledge.

- `Tile.glyph()` returns the character. `Tile` does NOT know about
  colors.
- `Tile.isWalkable()` answers whether an entity can stand on that
  tile.
- `GameMap.init(seed)` generates terrain with two TC starts
- `GameMap.at(x, y)` with bounds check (returns `.water` for OOB)
- `GameMap.is_walkable(x, y)` delegates to `Tile.isWalkable()` with
  bounds check
- `GameMap.tree_remaining[]` -- per-tile wood remaining; initialized
  to `tree_total_yield` when tree placed
- `GameMap.deplete_tree(x, y, amount)` -- drains wood, flips tile
  to grass at 0
- `GameMap.tree_remaining_at(x, y)` -- query for render coloring
- TC positions: `player_tc_x/y`, `enemy_tc_x/y`
- No entity tiles (`.worker`, `.soldier`). Entities are separate
  from terrain.
- Color/style lives in `render.zig`/`color.zig`, never in `map.zig`

### unit.zig

`Unit` + shared types. Pure data + `Unit.step()` movement.

- `Pos` -- 2D coordinate, `x`/`y` as `usize`
- `Owner` -- `player` or `enemy` or `neutral`
- `UnitKind` -- `worker` or `soldier`, with `glyph()` and `maxHp()`
- `UnitState` -- `idle`, `moving`, `gathering_wood`,
  `gathering_food`, `hunting`, `constructing`
- `GatherPhase` -- `none`, `to_resource`, `harvesting`, `to_depot`
- `CarryKind` -- `none`, `wood`, `food`
- `Unit` -- x, y, kind, owner, hp, state, path, gather_phase,
  gather_target, gather_timer, carry, carry_kind, target_deer_idx,
  target_farm_idx, grove_anchor. `pos()`, `step()` methods.
- Units regenerate 1 HP per 30 ticks, pauses 5 ticks after taking
  damage (milestone 6). Workers fight at 3 dmg, soldiers at 8 dmg.
- `MAX_PATH`, `MAX_UNITS` live in `config.zig`

### building.zig

`Building` type. Pure data.

- `BuildingKind` -- `town_center`, `house`, `barracks`, `farm`,
  `drop_pile`, with `glyph()`, `maxHp()`, `label()`. `is_depot()`
  returns true for TC and drop_pile.
- `Building` -- x, y, kind, owner, hp, build_progress,
  food_remaining, fallow, assigned_worker.
- Building costs: House=30w, Barracks=25f+50w, Farm=60w,
  DropPile=50w, FarmResow=60w
- Unit costs: Worker=50f, Soldier=60f+20w
- `MAX_BUILDINGS` lives in `config.zig`

### nature.zig

`Nature` (deer). Pure data + `wander()`.

- `NatureKind` -- `deer`
- `Nature` -- x, y, kind, hp, state, food_remaining, dead.
- `max_food()` returns per-deer food capacity.
- Dead deer stop wandering but remain harvestable until food=0.

### economy.zig

Resource counters, gather state machine, drop-off routing.

- `find_nearest_depot`, `find_nearest_tree`, `find_nearest_deer`,
  `find_free_farm` -- spatial queries for gather targeting
- `tick_unit(s, i)` -- drives per-worker gather state machine:
  to_resource -> harvesting -> to_depot -> loop
- `start_gather_at`, `start_gather_nearest` -- entry points from
  input.zig (G key, Shift+G menu)
- `resow_farm`, `auto_resow` -- manual R key + auto-resow on return
  when wood banked
- `remove_deer` -- swap-remove, updates other workers' deer indices
- State fields read/written: `food`, `wood` counters live in
  `game.State`

### pathfinding.zig

A* on the tile grid. Uses `GameMap.is_walkable()` for passability.

- `find_path(allocator, map, start, goal, out_path, blocked) ?usize`
  -- returns path length or null. `blocked` is optional list of
  extra impassable positions (other units).
- `find_nearest_reachable(allocator, map, goal, blocked) ?Pos` --
  BFS from goal outward, used when goal is blocked.
- `has_path(allocator, map, start, goal) bool` -- used by map gen.
- Working sets heap-allocated per call (freed on return).
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
- `tile_style()` maps terrain to style; tree color reads
  `tree_remaining_at` for depletion shading.
- Uses `spatial.*` for entity overlay. Resource tiles/entities
  lighten as depleted (see `color.zig`).
- Fog of war: unexplored tiles render as unknown (milestone 7)
- No state mutation. Pure rendering.

### color.zig

Color helpers. Pure.

- `unit_color`, `building_color`, `nature_color` -- blend by HP /
  build progress / food remaining
- `tree_tile_color` -- lerp tree color by `tree_remaining` ratio
- `resource_ratio(remaining, total) f32`
- Depleted resource colors defined in `config.colors`

### drawer.zig

Bottom info panel. Pure rendering.

- `draw(canvas, state)` -- tile info, selection (unit group or
  building), food/wood counters, pop/cap, time, hotkey help
- Building selection shows: HP, depot tag, pop contribution, farm
  food/fallow/worker status, build progress, position

### spatial.zig

Entity-by-position queries. Pure.

- `unit_at`, `building_at`, `nature_at`, `nature_at_except`,
  `occupied`, `collect_blocked`

### coord.zig, fmt.zig

Coordinate parsing/formatting and uint formatting helpers.

### terminal.zig

Wrapper around vaxis. Own types for Color, Style, Key, Event, Canvas,
Terminal.

- `Color` -- `default`, `rgb`, `index` (no vaxis dependency in our
  API)
- `Style` -- `fg`, `bg`, `bold`, `reverse` only
- `Key` -- `kind` (char/arrow/tab/enter/escape/unknown), `char_val`,
  `ctrl`, `shift`. Query methods: `is_char`, `is_ctrl`, `is_left`,
  etc.
- `Event` -- `key_press` or `resize`
- `Canvas` -- `clear`, `write_cell`, `write_str`, `width`, `height`
- `Terminal` -- `init`, `deinit`, `poll_event`, `canvas`, `present`
- Conversion functions `from_vaxis_key`, `to_vaxis_style`,
  `to_vaxis_color` tested against vaxis types.
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
