# lazyrts design doc

Win condition: destroy the enemy Town Center.

## Scope

If it's not in this table, the answer is *no*.

| Thing     | AOE2                          | lazyrts                                   |
|-----------|-------------------------------|-------------------------------------------|
| Resources | food, wood, gold, stone      | food, wood                                |
| Buildings | dozens                       | TC, House, Barracks, Farm, Drop Pile      |
| Units     | dozens + upgrades             | Worker, Soldier, Deer (neutral)           |
| Ages      | Dark through Imperial        | none                                      |
| Tech tree | huge                         | none                                      |
| Map       | random, big                  | dynamic, fills terminal                   |
| Players   | up to 8                      | 1v1                                       |
| Fog of war| yes                          | exploration only, no re-fog               |

## Costs

### Buildings

| Building    | Food | Wood | Size | HP  | Pop | Notes                         |
|-------------|------|------|------|-----|-----|-------------------------------|
| Town Center | -    | -    | 3x3  | 500 | +5  | Spawns workers, resource depot|
| House       | -    | 30   | 2x2  | 200 | +5  |                               |
| Barracks    | 25   | 50   | 2x3  | 300 | -   | Trains soldiers               |
| Farm        | -    | 60   | 3x3  | 100 | -   | 250 food then fallow, resow 60|
| Drop Pile   | -    | 50   | 1x1  | 100 | -   | Resource depot                |

### Units

| Unit    | Food | Wood | HP  | Dmg/tick | vs Building |
|---------|------|------|-----|----------|-------------|
| Worker  | 50   | -    | 50  | 3        | 2           |
| Soldier | 60   | 20   | 100 | 8        | 5           |
| Deer    | -    | -    | 25  | 0        | 0           |

### Resources

| Source | Yield      | Notes                                       |
|--------|------------|---------------------------------------------|
| Tree   | 100 wood (10/trip) | Each tile drained over 10 trips; lightens as depleted |
| Farm   | 250 food (10/trip) | Then fallow, resow for 60 wood; auto-resow if wood banked |
| Deer   | 100 food (10/trip) | Dies on first hunt, carcass drained over 10 trips |

One unit per tile. Workers drop off at nearest depot (TC or Drop
Pile). Repair costs half original wood cost.

Regeneration: 1 HP per 30 ticks (3 sec). Pauses 5 ticks after
taking damage.

## Gathering

Workers are persistent. Set once, they keep going.

- **Wood (G on tree):** Move to grove edge, chop tile (10 wood/trip,
  100 per tile), drop off at nearest depot. Stop when grove gone.
- **Deer (G on deer):** Hunt deer (10 food/trip, 100 total). Deer
  dies on first hunt, stays as carcass, lightens as drained, removed
  at 0. Keep hunting nearby deer until told to stop.
- **Farm (G on farm):** One worker per farm. Produces 250 food (10/trip)
  then goes fallow. Resow with R (60 wood) or auto-resow on return if
  wood banked.
- **Build (B menu):** Worker constructs, keeps building until done
  or told to stop. (milestone 4)
- **Shift+G:** Auto-find nearest resource (W=wood, D=deer, F=farm).

Resource tiles/entities lighten in color as they deplete and
disappear when empty. Deer spawn in herds (one near each TC, rest
scattered with min spacing); herd deer wander within a radius of
their herd center.

## Sim model

10 Hz logic tick, deterministic. Single thread. No heap in hot path.
Render every frame, capped by frame sleep. A* for pathfinding (heap
per call, freed on return).

## Rendering

One glyph per tile. Map fills terminal edge-to-edge. Top rows are
column headers (2-3 rows for wider maps). No row labels — coordinates
in the footer.

| Glyph | Thing      |
|-------|------------|
| ` `   | grass      |
| `T`   | tree       |
| `~`   | water      |
| `C`   | Town Center|
| `H`   | House      |
| `B`   | Barracks   |
| `F`   | Farm       |
| `P`   | Drop Pile  |
| `w`   | Worker     |
| `s`   | Soldier    |
| `d`   | Deer       |

Colors: player=cyan, enemy=red, neutral=brown. Selected unit and
cursor get owner-color background.

## UI layout

```text
  A
  B     <-- column headers (2-3 rows)
  C
7  ...map fills terminal edge-to-edge...   00:35
8  ...no row labels...                     Pop:2/5
9  ...full width...
----------------------------------------------------------
 Tile:Grass D14  Sel:Worker HP:50/50 gathering_wood
 Pop:2/5 W:2 S:0  Wood:340  Food:120             00:35
 ?=help
----------------------------------------------------------
```

Bottom rows: info footer (tile, selection, resources, current-mode
hint). The footer no longer carries a keybinding cheat sheet; press
`?` for a centered overlay that lists every key. The overlay is
non-modal — game keeps running while it's open. Footer expands for
build/training queues (milestone 4+).

## Risks

- **Pathfinding cost:** A* per unit is fine at 80x40 with tens of
  units. Switch to flow fields only if perf bites.
- **Input latency:** Depends on terminal. vaxis raw mode keeps it
  under ~50ms.
- **AI debugging:** Reactive AI is harder than scripted. Start with
  event-response table, test each trigger.
- **Tick rate:** 10 Hz is the sweet spot. If sluggish, raise to 15
  before changing architecture.
- **Grapheme rendering:** vaxis stores `[]const u8` slices, not
  copies. Stack temporaries get invalidated. Fixed with comptime
  ASCII lookup table.

## Module layout

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

**Principle:** anything reusable, no game knowledge, lives in `lib/`.
Game code calls `lib/` directly — no pass-through wrappers, no
re-export facades. Entity types use tagged-union variants (one file
per concrete type owns its data + behavior); adding a new unit/
building/resource = new file + one variant arm + switch arms in the
kind's dispatch methods. See [AGENTS.md](AGENTS.md) for the
convention and per-file responsibilities.

## Non-goals

No save/load. No map editor. No tech trees or civilizations. No mouse.
No sound. No animation beyond glyph state changes.
