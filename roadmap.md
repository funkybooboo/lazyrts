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
- [ ] Entities exist: Worker struct with position, owner, state (idle/moving)
- [ ] TC spawns a Worker on press of T key
- [ ] M key: move selected worker to cursor via A* pathfinding
- [ ] Worker moves one tile per tick, follows path
- [ ] Fixed 10 Hz logic tick, decoupled from render
- [ ] A* implemented in pathfinding.zig, tested on known grids
- [ ] Unit tests: pathfinding finds shortest path, handles obstacles, unreachable tile

**Ships:** You can press T to spawn a worker, then M to tell it to walk somewhere. It pathfinds around obstacles.

---

### 3. Economy
Trees -> worker chops -> drops at TC -> wood counter increments.

**Done when:**
- [ ] G key: worker gathers from tree/farm under cursor
- [ ] Worker walks to resource, chops for N ticks, carries resource
- [ ] Worker walks back to TC, drops off, counter increments
- [ ] Resource counters (food, wood) displayed in sidebar
- [ ] Population / pop cap displayed
- [ ] Unit tests: resource arithmetic, drop-off logic, carry capacity

**Ships:** You can gather wood and see the counter go up. The core economic loop works.

---

### 4. Buildings
Build House (pop cap) and Farm (food source).

**Done when:**
- [ ] B key opens build menu: H for House, F for Farm (if enough wood)
- [ ] Building placed at cursor position (must be on grass, adjacent to own TC or building)
- [ ] House increases pop cap by N
- [ ] Farm is a food source workers can gather from
- [ ] Buildings have HP, displayed when selected
- [ ] Unit tests: pop cap arithmetic, building placement validation

**Ships:** You can build houses to get more pop and farms to get food. The economy has two resources now.

---

### 5. Military
Build Barracks, train Soldier.

**Done when:**
- [ ] Barracks building (B key from build menu)
- [ ] T key at Barracks trains a Soldier (costs food + wood)
- [ ] Soldier: moves, attacks, higher HP than worker
- [ ] Soldiers can't gather
- [ ] Training costs deducted from resources, training takes N ticks
- [ ] Unit tests: cost deduction, training queue, unit type distinctions

**Ships:** You can build a barracks and train soldiers. The military layer exists.

---

### 6. Combat
Two armies fight (manual control of both sides).

**Done when:**
- [ ] A key: attack-move selected unit to cursor
- [ ] Units attack adjacent enemies once per tick, dealing damage
- [ ] Units die when HP reaches 0, removed from game
- [ ] Buildings can be attacked and destroyed
- [ ] Combat math: N damage per tick, workers weaker than soldiers
- [ ] Unit tests: damage calculation, death removal, building destruction

**Ships:** You can order units to attack. Things die. The game has teeth.

---

### 7. AI
Scripted opponent with a fixed build order.

**Done when:**
- [ ] AI owns enemy (orange/red) units and buildings
- [ ] AI follows a fixed build order: worker, house, worker, barracks, soldiers
- [ ] AI sends attack groups periodically
- [ ] AI rebuilds workers if population allows
- [ ] AI does not cheat: same rules, same costs
- [ ] Unit tests: AI state transitions (build order progression, attack triggers)

**Ships:** You have an opponent. It's dumb but functional. The game is playable 1v1.

---

### 8. Win/lose
Detect TC destruction, show result, restart prompt.

**Done when:**
- [ ] Game ends when either TC is destroyed
- [ ] Victory/defeat message rendered in terminal
- [ ] R key restarts the game (new map, fresh state)
- [ ] No crash on endgame, no softlock
- [ ] Unit tests: win condition detection (TC HP = 0)

**Ships:** The game has a beginning, middle, and end. Milestone 1 through 8 is a complete game.