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
- No heap allocation in the hot path. `game.state.State` is stack-allocated
  (entity arrays heap-allocated once at init; per-tick logic allocates only
  transient pathfinding buffers).
- Every public function on a struct takes `self` as first param:
  `pub fn foo(self: *Struct, ...)`. Exception: `game.state.State` uses free
  functions, not methods on State, to separate data from logic.
- Use `usize` for tile coordinates, `isize` for deltas. Clamp at
  bounds, never underflow.
- Zig errors (`!void`) for things that can actually fail (I/O,
  allocation). `assert` for programmer bugs.
- `pub` only on what other modules need. Everything else is
  file-private.
- Naming (Zig convention): functions and methods `camelCase`
  (`findPath`, `monoNow`, `Tile.isWalkable`); struct/enum/union
  fields and local vars `snake_case` (`cursor_x`, `build_progress`,
  `food_remaining`). Types `PascalCase`.

## Directory Layout

```
src/
  main.zig              entry point, event loop
  config.zig            single source of truth for all constants
  lib/                  generic infra, no game knowledge
    time.zig            monoNow, sleepNs, Ticker, ticksToSeconds
    fmt.zig             formatUint, formatElapsed
    coords.zig         Pos, manhattan, dirs4, parseCoord, colToLetters, headerHeight
    color.zig           lerp, lerpColor, healthRatio, resourceRatio
    pathfinding.zig     generic A* (findPath, findNearestReachable, hasPath) + Scratch
    spatial.zig         generic entity-by-pos queries (indexOfAt, collectPositions, findIndexNearest, findIndexNearestWhere)
    terminal.zig        vaxis wrapper (Color/Style/Key/Event/Canvas/Terminal)
  ui/                   all rendering + input
    color.zig           game color helpers (uses lib/color blend math)
    header.zig          column/row label drawing
    board.zig           map + entity overlay draw (the main frame)
    footer.zig          bottom info panel
    input.zig           key dispatch + cursor/move commands
  game/                 game loop logic + world data
    state.zig           State struct + init/deinit + selection ctx accessors + spatial_index
    tick.zig            sim step (dispatches units + wildlife)
    perf.zig            Perf counters (per-stage timing, A* call count)
    economy.zig         gather state machine, resource flow
    spawning.zig        entity spawn (init helpers + runtime spawn)
    selection.zig       selection ops on Ctx/View passed by caller
    queries.zig         Ctx bundle + Index (O(1) tile->entity) + occupied + collectBlocked
    movement.zig        movement helpers (pathTo, advance, arrived, repathBlocked) on lib A*
    map.zig             GameMap + Tile (terrain data, no rendering)
    mapgen.zig          terrain generation
  units/                unit entities (data + behavior per type)
  buildings/            building entities (data + behavior per type)
  resources/            harvestable resources (deer, tree) + interface
```

## Entity Polymorphism

Entities use tagged-union variants, not vtables. Each entity dir
follows the same pattern:

- A top-level `Kind` enum (glyph + shared dispatch).
- A `Variant = union(Kind)` carrying per-type data.
- The entity struct (Unit/Building/Wildlife) holds shared fields +
  a `variant` field. Dispatch methods on the entity switch on the
  variant tag.
- One file per concrete type owns its struct + per-type behavior
  (glyph, maxHp, damage, resow, wander, etc.). Adding a type = new
  file + one variant arm + switch arms in dispatch methods.

Storage stays SOA (one flat array per entity kind in State), so no
heap-per-entity and no vtable indirection in the hot path.

### units/

- `unit.zig` -- `Pos`, `Owner`, `UnitActivity`, `CargoKind`, `GatherPhase`,
  `Kind`, `Variant`, `Unit` (shared fields + variant), dispatch methods
  (`pos`, `step`, `kind()`, `glyph`, `maxHp`, `attackDamage`).
- `worker.zig` -- `Worker` struct + glyph/maxHp/damage(3).
- `soldier.zig` -- `Soldier` struct + glyph/maxHp/damage(8).

### buildings/

- `building.zig` -- `Kind`, `Variant`, `Building` (shared fields +
  variant), dispatch methods (`kind()`, `glyph`, `label`, `maxHp`,
  `isDropoff`, `popHousing`, `isComplete`).
- `town_center.zig`, `house.zig`, `barracks.zig`, `drop_pile.zig` --
  per-type struct + glyph/maxHp/label/isDropoff/popHousing.
- `farm.zig` -- `Farm` struct (food_remaining, fallow, assigned_worker)
  + glyph/maxHp/label + `resow()` behavior.

### resources/

- `resource.zig` -- `Kind` (tree, deer) + `ResourceRef` (target handle
  for gather: tree position or deer index).
- `wildlife.zig` -- `Wildlife = union(Kind){deer: Deer}` + dispatch
  (`pos`, `glyph`, `maxHp`, `maxFood`, `isDead`, `foodRemaining`,
  `wander`). Extendable: new wildlife = new variant arm.
- `deer.zig` -- `Deer` struct + `pos()` + glyph/maxHp/maxFood/wander.
- `tree.zig` -- Tree behavior (glyph, totalYield, yieldPerHarvest,
  isAt, remainingAt, deplete). Storage stays in `game/map.zig`
  (`treeRemaining[]`); tree.zig wraps it one-way (no map->tree import).

## Module Responsibilities

### main.zig

Entry point. Owns the terminal event loop. Dispatches:

- `key_press` -> `input.handle()`
- `resize` -> ignored (terminal handles internally)

Uses `lib.time.Ticker` for tick rate from `config.zig`. Calls
`ui.map.draw()`. Does not contain game logic. Wraps render in a
`perf.renderSection` so frame time is tracked separately from tick
stages. `test` block references all modules so `zig build test`
discovers their tests.

### config.zig

Single source of truth for all constants and configuration values.

- All numeric constants, colors, sizes, limits live here.
- Organized by domain: `tick_rate`, `pop_per_housing`, `economy`,
  `selection`, `map_dims`, `entity_limits`, `unit_hp`, `wildlife_hp`,
  `building_hp`, `deer`, `map_gen`, `ui`, `timing`, `colors`, `glyphs`,
  `labels`.
- No runtime overhead: all values are compile-time constants.

### lib/

Generic infrastructure with no game-specific knowledge. Safe to reuse
in other projects.

- `time.zig` -- monotonic clock, nanosleep, `Ticker` (fixed-rate tick
  accumulator), `ticksToSeconds`.
- `fmt.zig` -- `formatUint`, `formatElapsed` (no std.fmt dependency).
- `coords.zig` -- `Pos` (generic 2D point `{x, y}`), `manhattan`
  (grid distance), `dirs4` (the 4 cardinal direction offsets),
  spreadsheet-style coordinate parse/format (A1 <-> x,y), `headerHeight`
  (how many header rows a map width needs).
- `color.zig` -- generic color/blend math: `lerp`, `lerpColor`,
  `healthRatio`, `resourceRatio`. No game types.
- `pathfinding.zig` -- generic A* on a tile grid. `findPath`,
  `findNearestReachable`, `hasPath`. Comptime-generic over a `Grid`
  type duck-typed to expose `width`, `height`,
  `isWalkable(x, y) bool`. Zero-cost (no vtable; compiles to the same
  code as a hardcoded implementation). `Pos` from `coords.zig`.
  All three take a `*Scratch` (persistent, reusable buffer set: g/f
  score, came_from, open heap, closed) instead of an allocator — the
  hot path does ZERO heap allocation per A* call. The open list is a
  binary min-heap (O(log n) pop) with lazy deletion of closed nodes.
  Path reconstruction walks `came_from` backward into `out_path`
  directly, no temp buffer. `Scratch` is owned by `game.State`
  (`path_scratch`), sized once to map w*h at init. Tests use a
  self-contained `TestGrid` (no game imports).
- `spatial.zig` -- generic entity-by-position queries over any slice
  of items that expose a position (`.x`/`.y` fields OR a `pos()`
  method; comptime duck-typed via `@hasField`/`@hasDecl`). `indexOfAt`,
  `indexOfAtExcept`, `collectPositions`, `findIndexNearest`,
  `findIndexNearestWhere` (with a comptime predicate for filtered
  nearest). Zero-cost. Tests use self-contained dummy structs (no game
  imports).
- `terminal.zig` -- wrapper around vaxis. Own types for Color, Style,
  Key, Event, Canvas, Terminal. Conversion functions `fromVaxisKey`,
  `toVaxisStyle`, `toVaxisColor` tested against vaxis types. If
  vaxis breaks on upgrade, these tests fail immediately.

### ui/

Rendering + input. Rendering modules are pure (take `terminal.Canvas`
+ `*const State`, draw, no mutation). `input.zig` mutates state.

- `board.zig` -- `draw()` is the public entry. Draws column/row headers,
  then map tiles + entity overlay, then footer. `cell_style`,
  `tile_style` helpers.
- `header.zig` -- `draw_col_headers`, `draw_row_labels`.
- `footer.zig` -- bottom info panel: tile info, selection (unit group
  or building), food/wood counters, pop/cap, time, hotkey help.
- `color.zig` -- game-specific color helpers (`unitColor`, `buildingColor`,
  `wildlifeColor`, `treeTileColor`, `EntityClass`, `fullHpColor`,
  `damagedColor`). Uses `lib/color.zig` for blend math (`lerp`,
  `lerpColor`, `healthRatio`, `resourceRatio`). Depleted resource
  colors defined in `config.colors`.
- `input.zig` -- `handle(*State, Key)`: key-to-state-mutation bridge.
  Owns `moveCursor`/`moveSelected` (the only caller). Key bindings:

### game/

Game loop logic + world data.

- `state.zig` -- `State` struct (pure data + `init`/`deinit`/
  `spatialCtx`) + `unitSelection`/`buildingSelection` (mutable) and
  `selectView`/`buildingView` (const) accessors that produce the small
  selection contexts. `spatialCtx()` attaches `&spatial_index` so callers
  get O(1) position lookups; `rebuildSpatialIndex()` refreshes it (called
  at tick start and before render). Player helpers (`playerTc`, `playerPop`,
  `playerPopCap`, `playerUnitCounts`, `elapsedSeconds`, `gatherAtCursor`,
  `gatherNearest`, `resowSelected`). No re-export facade.
- `tick.zig` -- `tick(s)`: advances moving units, gathers, wildlife
  wander. Wraps each stage in a `perf.section` (units / wildlife /
  training) and calls `perf.finishTick` at the end.
- `perf.zig` -- `Perf` counters: per-stage ns over a rolling 64-sample
  window (tick stages and render tracked in *separate* rings because
  ticks and frames are not 1:1 — multiple ticks can fire per frame).
  `Section`/`RenderSection` are no-ops when `perf.enabled` is false so
  profiling has zero overhead when off. `recordPathfind` counts A*
  calls per tick. Toggled by the `` ` `` key; overlay drawn in
  `ui/board.zig`.
- `economy.zig` -- gather state machine (`tickUnit`), drop-off
  routing (`beginToDropoff`, `routeDropoff`), `startGatherAt`/
  `startGatherNearest`, `tryResow`/`autoResow`/`resowFarm`,
  `findNearestDropoff`/`Tree`/`FreeFarm` (building queries delegate to
  `lib/spatial.findIndexNearest*`; tree uses `findNearestPosWhere`).
  Helper fns (`resetCarry`, `buildingPos`, `pathDrift`) dedupe unit-state
  resets / path-staleness checks. Hunt re-pathing is throttled by
  `config.economy.hunt_drift_repath`: a worker only re-paths to a
  wandering deer when the path endpoint has drifted more than that many
  tiles (or the path is exhausted), instead of every tick the deer
  moves.
- `spawning.zig` -- `init_starting_buildings`/`workers`/`farm`/
  `allocate_paths`/`spawn_deer` (one-time setup, called from
  `State.init`) + runtime `spawnUnit`/`spawnWorker`/`spawnWildlife`.
- `selection.zig` -- selection ops on a small `Ctx`/`View` (units) and
  `BuildingCtx`/`BuildingView` (buildings) passed by the caller:
  `selectSingle`, `selectClear`, `selectAdd`, `selectNext`/`Prev`,
  `selectIdleWorkers`, `selectAllWorkers`, `selectNextBuilding`/
  `selectPrevBuilding`, `hasSelected`, `primarySelected`, plus
  read-only `view*` variants. No per-call state wrappers; callers
  build a ctx via `State.unitSelection()` / `.buildingSelection()`
  (or `.selectView()` / `.buildingView()` for read-only draw paths).
- `queries.zig` -- `Ctx` (game-specific bundle of unit/building/wildlife
  slices + optional `*const Index`) + `occupied` (3-way OR across entity
  kinds) + `collectBlocked` (glues buildings + wildlife + units-with-skip).
  `Ctx.unitAt`/`buildingAt`/`wildlifeAt` do O(1) tile lookups via the
  `Index` when present, falling back to `lib/spatial.indexOfAt` (linear)
  when `index` is null (used in tests / command paths that need fresh
  positions). `Index` is a flat `tile -> ?usize` array per kind (the game
  enforces one entity per tile, so no hash buckets): `rebuild`, `moveUnit`,
  `removeWildlife`, `putUnit`/`putBuilding`/`putWildlife`. Owned by
  `State.spatial_index`, rebuilt at tick start and before render, kept
  current incrementally on step (`moveUnit`), spawn (`put*`), and deer
  removal (`removeWildlife`). Callers needing single-kind linear lookups
  (e.g. command paths targeting a wandering deer) use
  `lib/spatial.indexOfAt(slice, x, y)` directly.
- `movement.zig` -- game-specific movement helpers built on
  `lib/pathfinding.zig`: `adjacentWalkable`, `pathTo`, `pathToAdjacent`,
  `advance`, `arrived`, `isAdjacentTree`, `repathBlocked`. These know
  `Unit`, `queries.Ctx`, `collectBlocked`. The generic A* core
  (`findPath`/`findNearestReachable`/`hasPath`) lives in `lib/`;
  callers needing raw A* import `lib/pathfinding.zig` directly.
  `repathBlocked` throttles re-pathing when a step is blocked: returns
  `.wait` if within `config.timing.repath_cooldown_ticks` of the last
  re-path (lets the blocker move instead of re-pathing every tick),
  `.ok`/`.fail` otherwise. `advance` and `tick`'s `.moving` case both
  route blocked re-paths through it.
- `map.zig` -- `Tile` enum (glyph, isWalkable, label) + `GameMap`
  (tiles, treeRemaining, TC coords, at/isWalkable/set/
  treeRemainingAt/depleteTree/nearTc). Pure data, no rendering
  knowledge.
- `mapgen.zig` -- terrain generation (cluster-based forests, lakes,
  BFS path verification, TC placement).

### input/

Removed. Input lives in `ui/input.zig` (see above).

### Key bindings

`ui/input.zig` handles all keystrokes:

- hjkl / arrows: move cursor
- Q / Ctrl-C: quit
- T: spawn worker at TC
- M: move selected unit to cursor
- Tab / Shift+Tab: cycle player units
- n / N: cycle player buildings
- G: gather at cursor / Shift+G: gather menu (w=wood, d=deer, f=farm)
- c: coordinate input mode (type A1, enter to jump)
- w: select idle workers
- r: resow fallow farm (60 wood)
- Shift+direction: add unit to selection (multiselect)
- ?: toggle help overlay (game keeps running)
- `: toggle perf overlay (per-stage tick/render timing, A* calls/tick)

## Testing Rules

- Unit tests on pure logic only: state mutations, map lookups,
  pathfinding, combat math, entity dispatch, gather state transitions.
- No render tests. Verify visually.
- Each test file lives alongside its module (tests in `map.zig` test
  `GameMap`, etc.).
- Tests must pass with `zig build test`.
- Every milestone adds tests for its new pure-logic functions.

## Milestone Workflow

1. Read `roadmap.md` for the current milestone's definition of done.
2. Implement the feature across the relevant modules.
3. Add unit tests for all new pure-logic functions.
4. Run `zig build && zig build test`.
5. Run `zig build run` and playtest manually.
6. If it isn't fun-ish, fix that before moving on.
7. Update `roadmap.md` checkboxes.

## Git Conventions

- Small commits. Commit early, commit often.
- Don't commit unless asked.
- Don't commit secrets, .zig-cache, zig-out, or zig-pkg.

## Milestones

1. Empty world
2. One worker
3. Economy (persistent gather, drop piles)
4. Concurrency (queue architecture, producer-consumer, thread pool)
5. Buildings (construct, repair, multi-tile)
6. Military (training, selection shortcuts)
7. Combat (all units fight, regeneration)
8. Fog of war (exploration, vision)
9. AI (reactive, strategy-switching)
10. Win/lose (TC destruction, restart)
11. Multiplayer (human vs human)

## Adding a New Entity Type

1. New file in the entity dir (e.g. `src/units/archer.zig`): define
   the per-type struct + glyph/maxHp/damage/behavior.
2. In the dir's top file (e.g. `units/unit.zig`): add a `Kind` enum
   variant, a `Variant` union arm, and switch arms in every dispatch
   method (`glyph`, `maxHp`, `attackDamage`, ...).
3. `game/spawning.zig` gains the spawn path if player-buildable.
4. `ui/input.zig` gains the key binding.
5. `ui/` rendering picks it up automatically via entity dispatch.
6. Add tests in the new file. Run `zig build test`.

## Pending Internal Folds (optional, no file-count change)

- `spawning.zig` init helpers (`init_starting_*`, `spawn_deer`) could
  move into `state.init` to keep one-time setup with State
  construction; runtime `spawn_*` stays.
- `economy.zig` `findNearestDropoff`/`tree`/`farm` could partially move
  to `queries.zig`, but each carries a game-specific filter
  (`isDropoff`/owner/tile-scan/farm-assignment) so the generic core is
  small. `findNearestDeer` already delegates to
  `lib/spatial.findIndexNearest`.
