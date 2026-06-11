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
| Shift+Tab | Cycle own buildings |
| G | Gather: worker enters persistent gather at cursor |
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
| A | Attack-move to cursor |
| Shift+direction | Add unit to selection |
| Q / Ctrl-C | Quit |

## Project Structure

```
src/
  main.zig         entry point, event loop
  game.zig         State struct, game logic, coordinates, pop counts
  map.zig          Tile enum, GameMap (grid, BFS generation, deer)
  entity.zig       Unit/Building types, owner, hp, state, gather tasks
  pathfinding.zig  A* on tile grid
  input.zig        Key events -> state mutations
  render.zig       map + coordinate headers + entity rendering
  drawer.zig       bottom info panel
  color.zig        color palette, health shading, owner colors
  terminal.zig     vaxis wrapper (Canvas, Key, Style, ASCII lookup)
  time.zig         monotonic clock, tick accumulator
build.zig          build configuration
build.zig.zon      dependency manifest (vaxis)
roadmap.md         milestones with definitions of done
```

Upcoming modules (added as milestones ship):

```
  command.zig      order queue: move, gather, build, attack
  economy.zig      resource counters, drop-off, pop cap, persistent tasks
  combat.zig       adjacency damage per tick, regeneration
  ai.zig           reactive opponent (event-driven, strategy-switching)
```

## Architecture

Single-threaded event loop via vaxis. 10 Hz logic tick, decoupled render. The game state is a plain struct (`game.State`) that modules read/mutate through function calls. No globals, no heap allocation in the hot path.

Rendering is immediate mode: `render.draw()` reads state and writes cells every frame. Each ASCII glyph is stored in a comptime lookup table to avoid vaxis grapheme cache corruption on large terminals.

Map generation uses BFS cluster growth for thick forests and lakes, with TC clear zones guaranteed. A* pathfinding for unit movement. Deer wander randomly as neutral units.

## Costs & Yields

### Buildings

| Building | Food | Wood | Size | HP | Pop |
|----------|------|------|------|----|-----|
| Town Center | 0 | 0 | 3x3 | 500 | +5 |
| House | 0 | 30 | 2x2 | 200 | +5 |
| Barracks | 25 | 50 | 2x3 | 300 | - |
| Farm | 0 | 60 | 3x3 | 100 | - |
| Drop Pile | 0 | 50 | 1x1 | 150 | - |

Farm yields 250 food then goes fallow. Resow for 60 wood. Repair costs half original wood cost.

### Units

| Unit | Food | Wood | HP | Damage/tick | vs Building |
|------|------|------|----|-------------|-------------|
| Worker | 50 | 0 | 50 | 3 | 2 |
| Soldier | 60 | 20 | 100 | 8 | 5 |

### Resources

| Source | Yield |
|--------|-------|
| Tree tile | 100 wood |
| Farm | 250 food (then fallow) |
| Deer | 100 food |

## Scope

| Thing | AOE2 | lazyrts |
|-------|------|---------|
| Resources | food, wood, gold, stone | food, wood |
| Buildings | dozens | TC, House, Barracks, Farm, Drop Pile |
| Units | dozens, with upgrades | Worker, Soldier |
| Ages | Dark through Imperial | none |
| Map | random, dynamic | dynamic, fills terminal |
| Fog of war | yes | exploration only (no re-fog) |
| Players | up to 8 | 1v1 vs AI or human (milestone 10) |

## Design Principles

- Aggressive subtraction: if a feature isn't in the scope table, the answer is *no*
- Two resources: food, wood. Two combat units: Worker, Soldier. Five buildings: TC, House, Barracks, Farm, Drop Pile
- No ages, no tech tree, no save/load
- Workers are persistent: set them gathering and they keep going
- One unit per tile, no stacking
- Multi-tile buildings: TC 3x3, House 2x2, Barracks 2x3, Farm 3x3, Drop Pile 1x1
- All units can fight (workers weak, soldiers strong)
- Units regenerate 1 HP per 30 ticks, pauses 5 ticks after damage
- Unit tests on pure logic only. No render tests -- visual inspection is fine
- Each milestone ships a runnable game