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

Performance overhaul: profiling instrumentation + algorithmic improvements.
The concurrency architecture (thread pool, queues) is **deferred** until
profiling proves the single-threaded tick is the bottleneck — the sim is
intentionally single-threaded and deterministic (required for milestone
11 lockstep multiplayer), so threading is premature without measured
need and would fight determinism. Fix the algorithmic bottlenecks first.

**Profiling:**

- [x] Tick timing instrumentation: per-stage timing visible (units, wildlife, training, render) via the `` ` `` perf overlay (`game/perf.zig`)
- [x] Identify hotspots with real data before optimizing (overlay shows avg/max per stage + A* calls/tick)

**Algorithmic improvements:**

- [x] Spatial index: O(1) entity lookup by tile instead of O(n) linear scan (`game/queries.zig` `Index`, flat `tile -> ?usize` per kind; one-entity-per-tile rule means no hash buckets). Used by `occupied`, `board.draw` (was 3 linear scans per tile), and movement blocked checks.
- [x] Path caching / throttled re-pathing: blocked-step re-paths go through `movement.repathBlocked` with a cooldown (`config.timing.repath_cooldown_ticks`) so a blocked unit waits instead of re-pathing every tick; hunt re-paths only on destination drift > `config.economy.hunt_drift_repath` (not every 1-tile deer move).
- [x] A* heap-allocation removal: `lib/pathfinding.Scratch` (persistent g/f score, came_from, open heap, closed buffers) owned by `State.path_scratch`, sized once to map w*h — zero heap allocation per A* call (previously 5 mallocs per call).
- [x] A* open-list: binary min-heap (O(log n) pop) replacing the O(open_len) linear min-f scan.
- [ ] Dirty rect rendering: only redraw changed cells, not entire map every frame (deferred — measure with perf overlay first; vaxis may already diff internally)
- [ ] Batch radius spatial queries: `findNearestDropoff`/`Tree`/`Deer` still linear (not hot — only on gather-start/dropoff, not per-tick-per-unit). Convert to index bucket scan only if profiling shows it matters.

**Concurrency architecture (DEFERRED — gated on profiling):**

- [ ] Command queue, unit/wildlife/render update queues, job scheduler, tick-stage pipeline, state sharding, deterministic-under-threading. Only revisit if the perf overlay shows the single-threaded tick exceeding the frame budget at the target entity count. Threading conflicts with the deterministic lockstep model milestone 11 needs.

**Validation:**

- [x] Unit tests: Scratch lifecycle, heap optimality, repath cooldown, spatial index rebuild/move/remove, Ctx index-vs-linear fallback
- [ ] Benchmark: 100 units tick time < 5ms (measure with the perf overlay; current single-threaded baseline TBD)

**Ships:** Single-threaded sim with O(1) position queries, zero-alloc A*, throttled re-pathing, and a live perf overlay. Scales further on the same deterministic architecture. Concurrency explicitly deferred until measured need.

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
