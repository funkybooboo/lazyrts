# lazyrts roadmap

Version: 0.1.0-alpha.2

## Milestones

### 1. Empty world

Map renders, cursor moves, Q quits.

**Done when:**

- [x] 80x40 map fills terminal with colored glyphs (grass, trees, water, TCs)
- [x] Cursor highlights tile under it (reverse video)
- [x] hjkl / arrow keys move cursor, clamped to map bounds
- [x] Q or Ctrl-C quits cleanly
- [x] Terminal restored on exit (alt screen, raw mode cleanup)
- [x] vaxis event loop: key_press and winsize handled
- [x] Unit tests: map.at bounds, map init, cursor clamping, Tile.glyph round-trip
- [x] Module tree: main, config, lib/ (generic infra), ui/ (render+input), game/ (loop+world), units/ + buildings/ + resources/ (entity dirs, tagged-union variants). See AGENTS.md.

**Ships:** `zig build run` shows a map you can move around. Nothing else.

---

### 2. One worker

Place TC, spawn worker, walk to commanded tile via A\*.

**Done when:**

- [x] Entities exist: Worker struct with position, owner, state (idle/moving)
- [x] TC spawns a Worker on press of T key
- [x] M key: move selected worker to cursor via A\* pathfinding
- [x] Worker moves one tile per tick, follows path
- [x] Fixed 10 Hz logic tick, decoupled from render
- [x] A\* implemented (now in `lib/pathfinding.zig`, generic over a `Grid` type), tested on known grids
- [x] Unit tests: pathfinding finds shortest path, handles obstacles, unreachable tile
- [x] Map fills full terminal width (row labels removed, coords shown in footer)
- [x] Column headers remain at top for horizontal reference
- [x] Bottom info footer: tile info, selected unit, resources, stats (keybindings moved to the `?` help overlay)
- [x] Coordinate labels (column headers + row numbers) and J-key cursor jump
- [x] Owner colors: player=blue, enemy=red for all units and buildings
- [x] Cluster-based map generator with forests, lakes, BFS path verification
- [x] Player TC on left, enemy TC on right, both vertically centered
- [x] Deer (neutral wandering animals) spawn scaled by map size
- [x] Starting workers: 2 per side at game start
- [x] Deer wander randomly, not controllable

**Ships:** Full-screen map with coordinate grid, bottom footer, colored teams, cluster terrain, deer, starting workers. J+A5 jumps cursor.

---

### 3. Economy

Workers gather resources persistently, drop off at TC or Drop Pile, counters increment.

**Done when:**

- [x] G key: selected worker enters gather mode at cursor target (tree, deer, farm)
- [x] Shift+G: worker auto-finds nearest resource of type (wood/deer/farm menu)
- [x] Grove gathering: worker moves to edge of tree cluster, chops tile by tile until grove depleted, then returns idle
- [x] Deer hunting: worker hunts deer, continues hunting nearby deer until told to stop
- [x] Farm gathering: one worker per farm, farms produce food until depleted, then go fallow
- [x] Farm resow: R key resows a fallow farm for 60 wood, worker resumes gathering (also auto-resows on return if wood banked)
- [x] Workers drop off at nearest owned depot (TC or Drop Pile)
- [x] Persistent tasks: workers keep working until told otherwise (no micro per tree)
- [x] C key: cursor coordinate input mode
- [x] W key: select all idle workers
- [x] n / N keys: cycle through player buildings (Shift+Tab reclaimed for back-cycle units)
- [x] Multiselect: Shift+direction adds units to selection
- [x] Resource counters (food, wood) displayed in footer
- [x] Population / pop cap displayed in footer
- [x] Footer expands to show selected group info (unit count, types)
- [x] Resource depletion shown by tile color (tree/deer/farm lighten as drained, disappear when empty)
- [x] Unit tests: resource arithmetic, drop-off logic, persistent gather state, grove depletion, farm depletion/resow, drop pile routing

#### Resource Yields

| Source    | Resource | Yield        | Notes                                               |
| --------- | -------- | ------------ | --------------------------------------------------- |
| Tree tile | Wood     | 10/trip (100 total) | Grove = cluster, each tile depleted over 10 trips |
| Farm      | Food     | 10/trip (250 total)  | Then goes fallow, resow for 60 wood                |
| Deer      | Food     | 10/trip (100 total) | Worker keeps hunting nearby deer until told to stop |

**Ships:** You can gather wood, hunt deer, work farms. Workers are persistent — set and forget. Drop Piles shorten trips. The core economic loop works.

---

### 4. Performance & concurrency

Comprehensive performance overhaul: multithreaded tick architecture, algorithmic improvements, and rendering optimizations. Fix the bottlenecks before adding more entities.

**Profiling:**

- [ ] Tick timing instrumentation: per-stage timing visible (movement, gathering, pathfinding, render)
- [ ] Identify hotspots with real data before optimizing

**Algorithmic improvements:**

- [ ] Spatial hash grid: O(1) entity lookup by position instead of O(n) linear scan
- [ ] Path caching: don't recompute A* every tick for same destination; invalidate on obstacle change
- [ ] Dirty rect rendering: only redraw changed cells, not entire map every frame
- [ ] Batch spatial queries: collect entities in radius with grid lookup, not brute-force scan

**Concurrency architecture:**

- [ ] Command queue: user input (move, gather, attack, build) produced on main thread, consumed by sim thread — decouples input from tick
- [ ] Unit update queue: units batched into jobs, processed by worker threads, results merged back
- [ ] Wildlife update queue: deer/wildlife behavior processed as independent jobs
- [ ] Render queue: final state snapshot pushed to render thread after sim tick completes
- [ ] Generic producer-consumer primitives: lock-free ring buffers or bounded MPSC queues in lib/
- [ ] Job scheduler: typed jobs enqueued with explicit dependencies, pulled by thread pool
- [ ] Tick decomposed into independent stages (input → command drain → movement → gathering → combat → wildlife → render)
- [ ] State partitioning: entity data sharded by position or owner to minimize contention between worker threads
- [ ] Main thread owns render + input production; worker threads own sim job consumption
- [ ] Deterministic: same inputs produce same output regardless of thread scheduling

**Validation:**

- [ ] Profiling harness: per-queue depth, per-job timing, thread utilization visible
- [ ] Unit tests: queue ordering, producer-consumer correctness under concurrency, dependency resolution, deterministic output
- [ ] Benchmark: 100 units tick time < 5ms (currently ~Xms, measure first)

**Ships:** Tick runs as a pipeline of queues feeding worker threads. Spatial queries O(1). Pathfinding cached. Render dirty. Single-threaded fallback still works. Codebase scales to 200+ entities without frame drops.

---

### 5. Buildings

Build House, Farm, Barracks, Drop Pile. Workers construct and repair persistently.

**Done when:**

- [ ] B key opens build menu: H for House, F for Farm, D for Drop Pile, R for Barracks (if enough resources)
- [ ] Building placed at cursor position (must be on grass, adjacent to own TC or building)
- [ ] House increases pop cap by 5
- [ ] Farm is a food source (max 1 worker, depletes after ~250 food, resow for 60 wood)
- [ ] Drop Pile: resource depot, workers drop off here instead of walking to TC
- [ ] Construction: worker builds, keeps building while buildings need construction or until told to stop
- [ ] E key: repair selected damaged building (costs 1/2 original wood cost to fully repair)
- [ ] Buildings have HP, displayed when selected
- [ ] Buildings have build progress shown in footer when selected
- [ ] Unit tests: pop cap arithmetic, building placement validation, construction progress, repair cost

**Ships:** You can build houses, farms, drop piles, and barracks. Workers construct and repair persistently. The economy has two resources now.

#### Cost Table

| Item       | Food | Wood                    | Size |
| ---------- | ---- | ----------------------- | ---- |
| Worker     | 50   | 0                       | -    |
| Soldier    | 60   | 20                      | -    |
| House      | 0    | 30                      | 2x2  |
| Barracks   | 25   | 50                      | 2x3  |
| Farm       | 0    | 60                      | 3x3  |
| Drop Pile  | 0    | 50                      | 1x1  |
| Farm resow | 0    | 60                      | -    |
| Repair     | 0    | half original wood cost | -    |

---

### 6. Military

Train Soldier from Barracks. Selection controls for combat units.

**Done when:**

- [ ] T key at Barracks trains a Soldier (costs 60 food + 20 wood)
- [ ] Soldier: moves, attacks, higher HP than worker
- [ ] Soldiers can't gather
- [ ] Training costs deducted from resources, training takes N ticks
- [ ] F key: select all idle fighters
- [ ] Shift+F: select all fighters (idle or not)
- [ ] Shift+W: select all workers (idle or not)
- [ ] Footer shows training queue and progress for selected barracks
- [ ] Unit tests: cost deduction, training queue, unit type distinctions

**Ships:** You can train soldiers from barracks. Fighter and worker selection shortcuts work. The military layer exists.

---

### 7. Combat

Two armies fight (manual control of both sides).

**Done when:**

- [ ] A key: attack-move selected unit (any unit) to cursor
- [ ] All units can fight, including workers (3 dmg/tick melee)
- [ ] Soldiers deal 8 dmg/tick melee, workers deal 3 dmg/tick melee
- [ ] Buildings take reduced melee damage: worker 2, soldier 5
- [ ] Units attack adjacent enemies once per tick
- [ ] Units die when HP reaches 0, removed from game
- [ ] Buildings can be attacked and destroyed
- [ ] Units heal over time: 1 HP per 30 ticks (3 sec), pauses for 5 ticks after taking damage
- [ ] Unit tests: damage calculation, death removal, building destruction, unit regeneration

#### Combat Stats

| Unit    | HP  | Damage/tick | vs Building | Range |
| ------- | --- | ----------- | ----------- | ----- |
| Worker  | 50  | 3           | 2           | melee |
| Soldier | 100 | 8           | 5           | melee |
| Deer    | 25  | 0           | 0           | -     |

**Ships:** You can order units to attack. Things die. The game has teeth.

---

### 8. Fog of War

Unexplored tiles hidden, explored tiles stay visible permanently.

**Done when:**

- [ ] Unexplored tiles render as unknown (black/empty glyph)
- [ ] Explored tiles show terrain permanently once seen (no re-fogging)
- [ ] Enemy units only visible when in vision range of owned units/buildings
- [ ] Vision range: 6 tiles from owned units, 8 tiles from TC/buildings
- [ ] AI scouts with workers early game, same vision rules
- [ ] Unit tests: visibility calculation, explored tile tracking, vision range edge cases

**Ships:** Map starts hidden. Scouting matters. Explored terrain stays revealed.

---

### 9. AI

Reactive opponent that adapts to player actions and game events.

**Done when:**

- [ ] AI owns enemy units and buildings, same rules as player
- [ ] AI follows a default build order but pauses to defend when attacked
- [ ] AI rebuilds lost workers if population allows
- [ ] AI switches strategies based on player behavior:
  - Defends/produces defenses against rushes
  - Expands/booms if player turtles
  - Adapts unit composition (more soldiers vs more workers) based on what it scouts
- [ ] AI responds to events: unit lost, building destroyed, resource thresholds, military proximity
- [ ] AI does not cheat: same rules, same costs, same vision limitations
- [ ] Multiple AI personality archetypes selectable or randomized per game
- [ ] Unit tests: AI state transitions, event response triggers, strategy selection logic

**Ships:** You have an opponent that reacts, adapts, and varies strategy. No two games play the same.

---

### 10. Win/lose

**Done when:**

- [ ] Game ends when either TC is destroyed
- [ ] Victory/defeat message rendered in terminal
- [ ] R key restarts the game (new map, fresh state)
- [ ] No crash on endgame, no softlock
- [ ] Unit tests: win condition detection (TC HP = 0)

**Ships:** The game has a beginning, middle, and end. Milestones 1-10 form a complete game.

---

### 11. Multiplayer

Human vs human over network.

**Done when:**

- [ ] Two players can connect and play over a network connection
- [ ] Game state synchronized between players at each tick
- [ ] Deterministic simulation: both players compute same state from same inputs
- [ ] Input latency handling with client-side prediction or delay
- [ ] Host/join flow from terminal UI
- [ ] AI still available as opponent option
- [ ] No desyncs under normal play for 30+ minute games

**Ships:** Two humans can play against each other. The game is multiplayer.
