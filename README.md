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
| Shift+Tab    | Cycle own buildings            |
| G            | Gather at cursor               |
| Shift+G      | Auto-find nearest resource    |
| J            | Jump to coordinate             |
| M            | Move selected unit             |
| T            | Train worker at TC             |
| W            | Select idle workers            |
| Shift+W      | Select all workers             |
| F            | Select idle fighters           |
| Shift+F      | Select all fighters            |
| B            | Build menu (H/F/D/R)          |
| E            | Repair building                |
| R            | Resow fallow farm              |
| A            | Attack-move                    |
| Shift+dir    | Add unit to selection          |
| Q / Ctrl-C   | Quit                           |

## Costs

### Buildings

| Building    | Food | Wood | Size | HP  | Pop |
|-------------|------|------|------|-----|-----|
| Town Center | -    | -    | 3x3  | 500 | +5  |
| House       | -    | 30   | 2x2  | 200 | +5  |
| Barracks    | 25   | 50   | 2x3  | 300 | -   |
| Farm        | -    | 60   | 3x3  | 100 | -   |
| Drop Pile   | -    | 50   | 1x1  | 150 | -   |

Farms yield 250 food then go fallow. Resow for 60 wood.
Repair costs half the original wood cost.

### Units

| Unit    | Food | Wood | HP  | DPS | vs Building |
|---------|------|------|-----|-----|-------------|
| Worker  | 50   | -    | 50  | 3   | 2           |
| Soldier | 60   | 20   | 100 | 8   | 5           |

### Resources

Trees give 100 wood. Deer give 100 food.
Farms give 250 food then go fallow.

## How it works

10 Hz tick loop, decoupled render. Game state is a plain struct — no
globals, no heap in the hot path. A* for pathfinding. BFS cluster growth
for map generation. Workers keep gathering until you tell them to stop.

Units regenerate 1 HP per 30 ticks (3 seconds), pausing for 5 ticks
after taking damage.

## Status

Milestone 2 shipped. Working on economy (milestone 3).
See [roadmap.md](roadmap.md) for details.
