# lazyrts roadmap

Version: 0.1.0-alpha.1

## Milestones

### 1. Empty world
Map renders, cursor moves, Q quits.

**Done when:**
- [X] 80x40 map fills terminal with colored glyphs (grass, trees, water, TCs)
- [X] Cursor highlights tile under it (reverse video)
- [X] hjkl / arrow keys move cursor, clamped to map bounds
- [X] Q or Ctrl-C quits cleanly
- [X] Terminal restored on exit (alt screen, raw mode cleanup)
- [X] vaxis event loop: key_press and winsize handled
- [X] Unit tests: map.at bounds, map init, cursor clamping, Tile.glyph round-trip
- [X] Module layout matches spec: main, game, map, input, render

**Ships:** `zig build run` shows a map you can move around. Nothing else.

---

### 2. One worker
Place TC, spawn worker, walk to commanded tile via A*.

**Done when:**
- [X] Entities exist: Worker struct with position, owner, state (idle/moving)
- [X] TC spawns a Worker on press of T key
- [X] M key: move selected worker to cursor via A* pathfinding
- [X] Worker moves one tile per tick, follows path
- [X] Fixed 10 Hz logic tick, decoupled from render
- [X] A* implemented in pathfinding.zig, tested on known grids
- [X] Unit tests: pathfinding finds shortest path, handles obstacles, unreachable tile
- [X] Map fills full terminal width (row labels removed, coords shown in drawer)
- [X] Column headers remain at top for horizontal reference
- [X] Bottom info drawer: tile info, selected unit, resources, stats, cheat sheet
- [X] Coordinate labels (column headers + row numbers) and J-key cursor jump
- [X] Owner colors: player=blue, enemy=red for all units and buildings
- [X] Cluster-based map generator with forests, lakes, BFS path verification
- [X] Player TC on left, enemy TC on right, both vertically centered
- [X] Deer (neutral wandering animals) spawn scaled by map size
- [X] Starting workers: 2 per side at game start
- [X] Deer wander randomly, not controllable

**Ships:** Full-screen map with coordinate grid, bottom drawer, colored teams, cluster terrain, deer, starting workers. J+A5 jumps cursor.

---

### 3. Economy
Workers gather resources persistently, drop off at TC or Drop Pile, counters increment.

**Done when:**
- [ ] G key: selected worker enters gather mode at cursor target (tree, deer, farm)
- [ ] Shift+G: worker auto-finds nearest resource of type (wood/deer/farm menu)
- [ ] Grove gathering: worker moves to edge of tree cluster, chops tile by tile until grove depleted, then returns idle
- [ ] Deer hunting: worker hunts deer, continues hunting nearby deer until told to stop
- [ ] Farm gathering: one worker per farm, farms produce food until depleted, then go fallow
- [ ] Farm resow: R key resows a fallow farm for 60 wood, worker resumes gathering
- [ ] Drop Pile building: workers drop resources here instead of walking to TC
- [ ] Workers drop off at nearest owned depot (TC or Drop Pile)
- [ ] Persistent tasks: workers keep working until told otherwise (no micro per tree)
- [ ] J key: cursor jump (coordinate input mode)
- [ ] W key: select all idle workers
- [ ] Shift+Tab: cycle through player buildings
- [ ] Multiselect: Shift+direction adds units to selection
- [ ] Resource counters (food, wood) displayed in drawer
- [ ] Population / pop cap displayed in drawer
- [ ] Drawer expands to show selected group info (unit count, types)
- [ ] Unit tests: resource arithmetic, drop-off logic, persistent gather state, grove depletion, farm depletion/resow, drop pile routing

#### Resource Yields
| Source | Resource | Yield | Notes |
|--------|----------|-------|-------|
| Tree tile | Wood | 100 per tile | Grove = cluster, each tile depleted individually |
| Farm | Food | 250 total | Then goes fallow, resow for 60 wood |
| Deer | Food | 100 per deer | Worker keeps hunting nearby deer until told to stop |

**Ships:** You can gather wood, hunt deer, work farms. Workers are persistent — set and forget. Drop Piles shorten trips. The core economic loop works.

---

### 4. Buildings
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
- [ ] Buildings have build progress shown in drawer when selected
- [ ] Unit tests: pop cap arithmetic, building placement validation, construction progress, repair cost

**Ships:** You can build houses, farms, drop piles, and barracks. Workers construct and repair persistently. The economy has two resources now.

#### Cost Table
| Item | Food | Wood |
|------|------|------|
| Worker | 50 | 0 |
| Soldier | 60 | 20 |
| House | 0 | 30 | 2x2 |
| Barracks | 25 | 50 | 2x3 |
| Farm | 0 | 60 | 3x3 |
| Drop Pile | 0 | 50 | 1x1 |
| Farm resow | 0 | 60 | - |
| Repair | 0 | half original wood cost | - |

---

### 5. Military
Train Soldier from Barracks. Selection controls for combat units.

**Done when:**
- [ ] T key at Barracks trains a Soldier (costs 60 food + 20 wood)
- [ ] Soldier: moves, attacks, higher HP than worker
- [ ] Soldiers can't gather
- [ ] Training costs deducted from resources, training takes N ticks
- [ ] F key: select all idle fighters
- [ ] Shift+F: select all fighters (idle or not)
- [ ] Shift+W: select all workers (idle or not)
- [ ] Drawer shows training queue and progress for selected barracks
- [ ] Unit tests: cost deduction, training queue, unit type distinctions

**Ships:** You can train soldiers from barracks. Fighter and worker selection shortcuts work. The military layer exists.

---

### 6. Combat
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
| Unit | HP | Damage/tick | vs Building | Range |
|------|-----|------------|-------------|-------|
| Worker | 50 | 3 | 2 | melee |
| Soldier | 100 | 8 | 5 | melee |
| Deer | 25 | 0 | 0 | - |

**Ships:** You can order units to attack. Things die. The game has teeth.

---

### 7. Fog of War
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

### 8. AI
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

### 9. Win/lose

**Done when:**
- [ ] Game ends when either TC is destroyed
- [ ] Victory/defeat message rendered in terminal
- [ ] R key restarts the game (new map, fresh state)
- [ ] No crash on endgame, no softlock
- [ ] Unit tests: win condition detection (TC HP = 0)

**Ships:** The game has a beginning, middle, and end. Milestones 1-9 form a complete game.

---

### 10. Multiplayer
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