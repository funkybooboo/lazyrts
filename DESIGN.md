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

| Thing       | AOE2                          | lazyrts                          |
|-------------|-------------------------------|----------------------------------|
| Resources   | food, wood, gold, stone       | **food, wood**                   |
| Buildings   | dozens                        | **TC, House, Barracks, Farm**    |
| Units       | dozens, with upgrades         | **Worker, Soldier**              |
| Ages        | Dark / Feudal / Castle / Imp  | none                             |
| Tech tree   | huge                          | none                             |
| Map         | random, big                   | dynamic size, fits terminal      |
| Players     | up to 8                       | 1v1, you vs scripted AI          |
| Fog of war  | yes                           | not in v1                        |
| Multiplayer | yes                           | no                               |

If you want a feature that isn't in the right column, the answer is *probably not*. Add only if it directly serves the core loop.

## Tech stack

- **Language:** Zig.
- **TUI library:** [vaxis](https://github.com/rockorager/libvaxis) -- handles raw mode, input events, double-buffered render. Avoids a week of termios yak-shaving.
- **No external runtime deps** beyond vaxis.

## Rendering

One glyph per tile. Coordinates shown as column letters (A-Z, AA-AZ...) stacked vertically in header, row numbers on left.

| Glyph | Thing            |
|-------|------------------|
| ` `   | grass            |
| `T`   | tree             |
| `~`   | water            |
| `C`   | Town Center      |
| `H`   | House            |
| `B`   | Barracks         |
| `F`   | Farm             |
| `w`   | Worker           |
| `s`   | Soldier          |
| `d`   | Deer             |

Color: player=cyan, enemy=red, neutral=brown. Selected unit = owner color background. Cursor = owner color background. Health = color brightness (dark=healthy, bright=damaged).

## Sim model

Fixed-tick simulation, decoupled render.

- **Logic tick:** 10 Hz. Deterministic. Drives movement, gathering, combat, AI.
- **Render:** redraw on dirty, capped at 30 Hz.
- **Threads:** none. Single-threaded event loop via vaxis.

This is the standard RTS architecture for a reason -- it makes replay, AI scripting, and debugging tractable.

## UI layout

```
 A
 B     <-- stacked column headers (2-3 rows for AA+ columns)
 C
7  ...map tiles fill terminal edge-to-edge...   00:35
8  ...row labels on left, 3 chars wide...         Pop:2/5 W:2 S:0
9  ...drawer shows tile/entity info at bottom...    hjkl=move Q=quit
------------------------------------------------------------
 Tile:Grass D14   Sel:Worker Player HP:50/50 moving
 Pop:2/5 W:2 S:0                                      00:35
 hjkl=move T=spawn M=move Tab=select G=coord Q=quit
------------------------------------------------------------
```

Map fills terminal edge-to-edge. Bottom 5 rows are the info drawer. Top 1-3 rows are column headers (stacked for multi-letter columns like AA). Left 3 columns are row number labels.

## Controls

| Key            | Action                                   |
|----------------|------------------------------------------|
| Arrows / hjkl  | Move cursor                              |
| Tab            | Cycle own units                          |
| G              | Enter coordinate jump mode               |
| M              | Move selected unit to cursor             |
| T              | Train worker at TC                        |
| Q / Ctrl-C     | Quit                                     |

## Modules

```
src/
  main.zig         entry + event loop
  game.zig         GameState, tick(), coordinates, pop counts
  map.zig          tile grid, BFS cluster generation, deer spawning
  entity.zig       Worker / Soldier / Deer / Building, owner, hp, state
  command.zig      order queue: move, gather, build, attack (milestone 3+)
  pathfinding.zig  A* on tile grid
  combat.zig       adjacency damage per tick (milestone 6+)
  economy.zig      resource counters, drop-off, pop cap (milestone 3+)
  ai.zig           scripted opponent (milestone 7+)
  render.zig       map + label + entity rendering
  drawer.zig       bottom info panel rendering
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
3. **Economy.** Trees on map -> worker chops -> drops at TC -> wood counter increments.
4. **Buildings.** Build House (pop cap) and Farm (food).
5. **Military.** Build Barracks, train Soldier.
6. **Combat.** Two armies fight (manual control of both sides).
7. **AI.** Scripted opponent with a fixed build order.
8. **Win/lose.** Detect TC destruction, show result, restart prompt.

## Verification

- Each milestone runs end-to-end manually before moving on. If it isn't fun-ish to play at that milestone, fix that before adding the next layer.
- Unit tests on pure logic only: pathfinding correctness, resource arithmetic, combat math, AI state transitions.
- No automated render tests. Visual inspection is fine for a terminal app.

## Risks and tradeoffs

- **Pathfinding cost.** A* per unit per repath is fine at 80x40 with tens of units. Switch to flow fields only if perf actually bites.
- **Input latency.** Depends on terminal emulator; vaxis raw mode should keep it under ~50 ms.
- **AI brittleness.** Scripted AI is dumb but predictable, which is correct for "simple". Resist behavior trees and utility AI.
- **Real-time feel.** 10 Hz tick is the sweet spot. If it feels sluggish, raise to 15 Hz before changing architecture.
- **Grapheme rendering.** vaxis stores `[]const u8` grapheme slices, not copies. Stack temporaries get invalidated. Fixed with comptime ASCII lookup table in Canvas.

## Non-goals

Explicit list of things lazyrts will *not* do, so future-me does not relitigate them:

- Multiplayer / networking.
- Save / load.
- Custom maps or map editor.
- Tech trees, civilizations, hero units.
- Mouse support.
- Sound.
- Animation beyond glyph state changes.

## Name

Short. The "lazy" is honest -- the design wins by aggressive subtraction, not feature count.