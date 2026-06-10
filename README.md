# lazyrts

Real-time strategy. In a terminal. With ~5% of the buttons.

A deliberately tiny AOE2-flavored RTS, written in Zig, rendered as glyphs in your terminal. The "lazy" in the name is the design principle: every feature has to earn its place, and the default answer is *cut it*.

## Build & Run

```bash
zig build          # compile
zig build run      # run the game
zig build test     # run unit tests
```

Requires Zig 0.16.0. Depends on [libvaxis](https://github.com/rockorager/libvaxis) (fetched automatically by the build system).

## Controls

| Key | Action |
|-----|--------|
| hjkl / arrows | Move cursor |
| Tab | Cycle own units |
| G | Jump to coordinate |
| M | Move selected unit to cursor |
| T | Train worker at TC |
| Q / Ctrl-C | Quit |

More controls added as milestones ship. See roadmap.md.

## Project Structure

```
src/
  main.zig         entry point, event loop
  game.zig         State struct, game logic, coordinates, pop counts
  map.zig          Tile enum, GameMap (grid, BFS generation, deer)
  entity.zig       Unit / Building types, owner, hp, state, path
  pathfinding.zig  A* on tile grid
  input.zig        Key events -> state mutations
  render.zig       map + coordinate labels + entity rendering
  drawer.zig       bottom info panel
  color.zig        color palette, health shading, owner colors
  terminal.zig     vaxis wrapper (Canvas, Key, Style, ASCII lookup)
  time.zig         monotonic clock, tick accumulator
build.zig          build configuration
build.zig.zon      dependency manifest (vaxis)
roadmap.md         milestones with definitions of done
```

## Architecture

Single-threaded event loop via vaxis. 10 Hz logic tick, decoupled render. The game state is a plain struct (`game.State`) that modules read/mutate through function calls. No globals, no heap allocation in the hot path.

Rendering is immediate mode: `render.draw()` reads state and writes cells every frame. Each ASCII glyph is stored in a comptime lookup table to avoid vaxis grapheme cache corruption on large terminals.

Map generation uses BFS cluster growth for thick forests and lakes, with TC clear zones guaranteed. A* pathfinding for unit movement. Deer wander randomly as neutral units.

## Design Principles

- Aggressive subtraction: if a feature isn't in the scope table, the answer is *no*
- Two resources: food, wood. Two units: Worker, Soldier. Four buildings: TC, House, Barracks, Farm
- No ages, no tech tree, no fog of war, no multiplayer, no save/load
- Unit tests on pure logic only. No render tests -- visual inspection is fine
- Each milestone ships a runnable game

## Scope

| Thing | AOE2 | lazyrts |
|-------|------|---------|
| Resources | food, wood, gold, stone | food, wood |
| Buildings | dozens | TC, House, Barracks, Farm |
| Units | dozens, with upgrades | Worker, Soldier |
| Ages | Dark through Imperial | none |
| Map | random, dynamic | dynamic, fits terminal |
| Players | up to 8 | 1v1 vs scripted AI |