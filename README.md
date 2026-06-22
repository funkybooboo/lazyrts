# lazyrts

RTS in a terminal. Like AOE2 shrunk down until only the important parts
are left.

Two resources. Two unit types. Five buildings. No ages, no tech tree,
no save files.

## Build & Run

```sh
zig build          # compile
zig build run      # play
zig build test     # run tests
```

Zig 0.16.0. [libvaxis] fetched automatically.

[libvaxis]: https://github.com/rockorager/libvaxis

## Controls

| Key          | Action                         |
|--------------|--------------------------------|
| hjkl / arrows| Move cursor                    |
| Tab          | Cycle own units                |
| Shift+Tab    | Cycle own units (reverse)      |
| n / N        | Cycle own buildings            |
| G            | Gather at cursor               |
| Shift+G      | Auto-find nearest resource (W/D/F) |
| c            | Jump to coordinate             |
| M            | Move selected unit(s)          |
| T            | Train worker at TC             |
| W            | Select idle workers            |
| R            | Resow fallow farm (selected/cursor) |
| Shift+dir    | Add unit to selection          |
| ?            | Toggle help overlay            |
| Q / Ctrl-C   | Quit                           |

The `?` overlay lists every key. It does not pause the game.

## Costs

### Buildings

| Building    | Food | Wood | Size | HP  | Pop |
|-------------|------|------|------|-----|-----|
| Town Center | -    | -    | 3x3  | 500 | +5  |
| House       | -    | 30   | 2x2  | 200 | +5  |
| Barracks    | 25   | 50   | 2x3  | 300 | -   |
| Farm        | -    | 60   | 3x3  | 100 | -   |
| Drop Pile   | -    | 50   | 1x1  | 100 | -   |

Farms yield 250 food then go fallow. Resow for 60 wood.
Repair costs half the original wood cost.

### Units

| Unit    | Food | Wood | HP  | DPS | vs Building |
|---------|------|------|-----|-----|-------------|
| Worker  | 50   | -    | 50  | 3   | 2           |
| Soldier | 60   | 20   | 100 | 8   | 5           |

### Resources

Trees yield 10 wood per trip (100 total per tile, 10 trips to fell).
Deer yield 10 food per trip (100 total; deer dies on first hunt,
stays as a carcass, lightens as drained, removed at 0).
Farms yield 10 food per trip (250 total, then fallow; resow 60 wood).

Resource tiles/entities lighten in color as they deplete and
disappear when empty.

Deer spawn in herds: one near each TC, the rest scattered with
minimum spacing between herd centers. Herd deer stay near their
herd center when wandering.

## How it works

10 Hz tick loop, decoupled render. Game state is a plain struct — no
globals, no heap in the hot path. A* for pathfinding. BFS cluster growth
for map generation. Workers keep gathering until you tell them to stop.

Units regenerate 1 HP per 30 ticks (3 seconds), pausing for 5 ticks
after taking damage.

## Layout

```
src/
  main.zig, config.zig
  lib/       generic infra (time, fmt, coords, color, pathfinding, spatial, terminal)
  ui/        board, header, footer, color, input
  game/      state, tick, economy, spawning, selection, queries, movement, map, mapgen
  units/     unit, worker, soldier
  buildings/ building, town_center, house, barracks, farm, drop_pile
  resources/ resource, wildlife, deer, tree
```
Generic algorithms (A/*, entity-by-pos queries, color math, 2D
coords) live in `lib/` with no game knowledge. Game logic calls them
directly. See [AGENTS.md](AGENTS.md) for conventions and
[DESIGN.md](DESIGN.md) for the model. Details: [roadmap.md](roadmap.md).

## Status

Milestone 3 (economy) shipped. Working on buildings (milestone 4).
