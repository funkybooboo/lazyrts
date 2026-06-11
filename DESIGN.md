# lazyrts

> Real-time strategy. In a terminal. With ~5% of the buttons.

A deliberately tiny AOE2-flavored RTS, written in Zig, rendered as glyphs in your terminal. The "lazy" in the name is the design principle: every feature has to earn its place, and the default answer is *cut it*.

## Core loop

The same loop AOE2 has, just trimmed:

```
gather  ->  build  ->  train  ->  fight  ->  win
```

Win condition: destroy the enemy Town Center.

## Scope

| Thing       | AOE2                          | lazyrts                                       |
|-------------|-------------------------------|-----------------------------------------------|
| Resources   | food, wood, gold, stone       | **food, wood**                                |
| Buildings   | dozens                        | **TC, House, Barracks, Farm, Drop Pile**      |
| Units       | dozens, with upgrades         | **Worker, Soldier, Deer (neutral)**           |
| Ages        | Dark / Feudal / Castle / Imp  | none                                          |
| Tech tree   | huge                          | none                                          |
| Map         | random, big                   | dynamic, fills terminal width                |
| Players     | up to 8                       | 1v1, you vs reactive AI                      |
| Fog of war  | yes                           | exploration only (no re-fog)                  |
| Multiplayer | yes                           | milestone 10                                  |

If you want a feature that isn't in the right column, the answer is *probably not*. Add only if it directly serves the core loop.

## Costs & Yields

### Buildings

| Building | Food | Wood | Size | HP | Pop | Special |
|----------|------|------|------|----|-----|---------|
| Town Center | 0 | 0 | 3x3 | 500 | +5 | Spawns workers, resource depot |
| House | 0 | 30 | 2x2 | 200 | +5 | Increases pop cap |
| Barracks | 25 | 50 | 2x3 | 300 | - | Trains soldiers |
| Farm | 0 | 60 | 3x3 | 100 | - | 1 worker, yields 250 food then goes fallow. Resow: 60 wood |
| Drop Pile | 0 | 50 | 1x1 | 150 | - | Resource depot (shorter worker trips) |

### Units

| Unit | Food | Wood | HP | Damage/tick | vs Building |
|------|------|------|----|-------------|-------------|
| Worker | 50 | 0 | 50 | 3 | 2 |
| Soldier | 60 | 20 | 100 | 8 | 5 |
| Deer | - | - | 25 | 0 | 0 |

### Resource Yields

| Source | Resource | Yield | Notes |
|--------|----------|-------|-------|
| Tree tile | Wood | 100 per tile | Grove = cluster, each tile depleted individually |
| Farm | Food | 250 total | Then fallow, resow for 60 wood |
| Deer | Food | 100 per deer | Worker keeps hunting nearby deer until told to stop |

### Repair

E key repairs selected building. Costs 1/2 original wood cost to fully repair.

### Regeneration

Units heal 1 HP per 30 ticks (3 sec). Pauses for 5 ticks after taking damage.

## Tech stack

- **Language:** Zig.
- **TUI library:** [vaxis](https://github.com/rockorager/libvaxis) -- handles raw mode, input events, double-buffered render. Avoids a week of termios yak-shaving.
- **No external runtime deps** beyond vaxis.

## Rendering

One glyph per tile. Map fills full terminal width. No row labels (coordinates shown in drawer). Column headers remain at top.

| Glyph | Thing |
|-------|-------|
| ` ` | grass |
| `T` | tree |
| `~` | water |
| `C` | Town Center |
| `H` | House |
| `B` | Barracks |
| `F` | Farm |
| `D` | Drop Pile |
| `w` | Worker |
| `s` | Soldier |
| `d` | Deer |

Color: player=cyan, enemy=red, neutral=brown. Selected unit = owner color background. Cursor = owner color background.

## Sim model

Fixed-tick simulation, decoupled render.

- **Logic tick:** 10 Hz. Deterministic. Drives movement, gathering, combat, AI.
- **Render:** redraw on dirty, capped at 30 Hz.
- **Threads:** none. Single-threaded event loop via vaxis.

## UI layout

```
  A
  B     <-- stacked column headers (2-3 rows for AA+ columns)
  C
7  ...map tiles fill terminal edge-to-edge...   00:35
8  ...no row labels, full width...               Pop:2/5 W:2 S:0
9  ...map fills all columns...
------------------------------------------------------------
 Tile:Grass D14   Sel:Worker Player HP:50/50 gathering_wood
 Pop:2/5 W:2 S:0  Wood:340  Food:120                00:35
 G=gather M=move Tab=select J=jump W=idle_w F=idle_f Q=quit
------------------------------------------------------------
```

Map fills terminal edge-to-edge. Bottom 5 rows are the info drawer (expands later for queues). Top 1-3 rows are column headers. No row labels — coordinates shown in drawer.

## Controls

| Key | Action |
|-----|--------|
| hjkl / arrows | Move cursor |
| Tab | Cycle own units |
| Shift+Tab | Cycle own buildings |
| G | Gather: selected worker enters persistent gather at cursor target |
| Shift+G | Auto-find nearest resource of type |
| J | Jump to coordinate |
| M | Move selected unit to cursor |
| T | Train worker at TC |
| W | Select all idle workers |
| Shift+W | Select all workers |
| F | Select all idle fighters |
| Shift+F | Select all fighters |
| B | Build menu (H=House, F=Farm, D=Drop Pile, R=Barracks) |
| E | Repair selected building |
| R | Resow fallow farm (60 wood) |
| A | Attack-move selected unit(s) to cursor |
| Shift+direction | Add unit to selection (multiselect) |
| Q / Ctrl-C | Quit |

## Gathering Behavior

Workers are persistent — set and forget:

- **Wood (G on tree):** Worker moves to edge of grove, chops tile by tile (100 wood each). Drops off at nearest depot (TC or Drop Pile). Stops when grove depleted.
- **Deer (G on deer):** Worker hunts deer (100 food each), continues hunting nearby deer until told to stop. Drops off at nearest depot.
- **Farm (G on farm):** One worker per farm. Produces food until farm depleted (250 food). Farm goes fallow. Resow with R key (60 wood).
- **Build (B menu):** Worker constructs building, keeps building while buildings need construction or until told to stop.
- **Shift+G:** Auto-find nearest resource of type (wood/deer/farm menu).

One unit per tile, no stacking.

## Modules

```
src/
  main.zig         entry + event loop
  game.zig         GameState, tick(), coordinates, pop counts
  map.zig          tile grid, BFS cluster generation, deer spawning
  entity.zig       Worker/Soldier/Deer/Building, owner, hp, state, gather tasks
  pathfinding.zig  A* on tile grid
  command.zig      order queue: move, gather, build, attack
  economy.zig      resource counters, drop-off, pop cap, persistent tasks
  combat.zig       adjacency damage per tick, regeneration
  ai.zig           reactive opponent (event-driven, strategy-switching)
  render.zig       map + entity rendering
  drawer.zig       bottom info panel (tile, unit, resources, hotkeys, queues)
  input.zig        key events -> state mutations
  color.zig        centralized color palette, health shading
  terminal.zig     vaxis wrapper (Canvas, Key, Style, ASCII lookup table)
  time.zig         monotonic clock, tick accumulator
build.zig
build.zig.zon      vaxis dep
```

## Milestones

Each milestone ships a runnable game.

1. **Empty world.** Map renders, cursor moves, Q quits.
2. **One worker.** Place TC, spawn worker, walk to commanded tile via A*.
3. **Economy.** Workers gather persistently, drop off at TC/Pile, counters increment.
4. **Buildings.** Build House, Farm, Barracks, Drop Pile. Workers construct and repair.
5. **Military.** Train Soldier from Barracks. Selection shortcuts for unit groups.
6. **Combat.** All units fight. Workers weak, soldiers strong. Regeneration.
7. **Fog of war.** Unexplored tiles hidden. Explored tiles stay visible. Vision range from units/buildings. AI scouts too.
8. **AI.** Reactive opponent that adapts to player actions and game events.
9. **Win/lose.** Detect TC destruction, show result, restart prompt.
10. **Multiplayer.** Human vs human over network.

## Verification

- Each milestone runs end-to-end manually before moving on. If it isn't fun-ish to play at that milestone, fix that before adding the next layer.
- Unit tests on pure logic only: pathfinding correctness, resource arithmetic, combat math, AI state transitions.
- No automated render tests. Visual inspection is fine for a terminal app.

## Risks and tradeoffs

- **Pathfinding cost.** A* per unit per repath is fine at 80x40 with tens of units. Switch to flow fields only if perf actually bites.
- **Input latency.** Depends on terminal emulator; vaxis raw mode should keep it under ~50 ms.
- **AI complexity.** Reactive AI is harder to debug than scripted. Start with event-response table, grow as needed. Test each trigger independently.
- **Real-time feel.** 10 Hz tick is the sweet spot. If it feels sluggish, raise to 15 Hz before changing architecture.
- **Grapheme rendering.** vaxis stores `[]const u8` grapheme slices, not copies. Stack temporaries get invalidated. Fixed with comptime ASCII lookup table in Canvas.

## Non-goals

Explicit list of things lazyrts will *not* do, so future-me does not relitigate them:

- Multiplayer (moved to milestone 10).
- Save / load.
- Custom maps or map editor.
- Tech trees, civilizations, hero units.
- Mouse support.
- Sound.
- Animation beyond glyph state changes.