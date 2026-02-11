# Project ISO - Development Roadmap

## ✅ COMPLETED - Core Systems Fixed (Feb 2026)

### Combat System
- [x] Fix attack delays - removed `await animation_finished` for instant response
- [x] Fix hit box timing - removed sound delays for immediate feedback
- [x] Combo system with escalating crit chance (5% + 1% per hit, max 65%)
- [x] Hit/Hurt box architecture working correctly
- [x] Damage text spawning and floating properly

### Movement System
- [x] Fix knockback tile alignment - snap to nearest tile after knockback
- [x] Fix animation direction mapping (W→NW, S→SE, A→SW, D→NE)
- [x] Isometric movement with smooth interpolation
- [x] Tile-based collision detection
- [x] Enemy pathfinding (basic tile-to-tile)
- [x] Direction updates from velocity for enemies

### Health System
- [x] Health tracking and signals working
- [x] Damage application through hurt boxes
- [x] Invincibility frames after taking damage
- [x] Visual feedback (red tint, damage numbers, camera shake)
- [x] Death sequences for player and enemies
- [x] Enemy respawn system

---

## 🚧 IN PROGRESS - Base Elements

### Terrain System (NOT STARTED)
- [ ] **Elevation/Height system**
  - [ ] Multi-level terrain (platforms, cliffs)
  - [ ] Use `elevation` variable (already in player/Ted)
  - [ ] Update z-index formula to account for elevation
  - [ ] Implement jump/fall between elevations
  - [ ] Visual indicators for elevation changes

- [ ] **Environmental Hazards**
  - [ ] Water tiles (slow movement, damage over time?)
  - [ ] Lava/fire tiles (high damage)
  - [ ] Ice tiles (reduced friction, sliding)
  - [ ] Grass/normal tiles (current implementation)

- [ ] **Interactive Terrain**
  - [ ] Breakable obstacles
  - [ ] Pushable blocks
  - [ ] Pressure plates/switches
  - [ ] Moving platforms

### Save/Checkpoint System (PARTIALLY IMPLEMENTED)
- [x] Save Statue scene exists (`Save Statue.tscn`)
- [ ] **Save State Implementation**
  - [ ] Save player position, health, inventory
  - [ ] Save world state (enemy deaths, collected items)
  - [ ] Save file format (JSON, binary, or Godot resource)
  - [ ] Multiple save slots support

- [ ] **Checkpoint System**
  - [ ] Save statue as spawn point
  - [ ] Respawn at last save statue on death (instead of game over?)
  - [ ] Activate save statue interaction (animation, sound)
  - [ ] Visual indicator for active checkpoint

- [ ] **Autosave**
  - [ ] Save on stage/dungeon completion
  - [ ] Save on checkpoint activation
  - [ ] Save on scene transitions

---

## 📋 PLANNED FEATURES - Future Systems

### Combat Enhancements
- [ ] **More Enemy Types**
  - [ ] Use `TileMovementController` as base for new enemies
  - [ ] Ranged enemies (archers, mages)
  - [ ] Flying enemies (different elevation)
  - [ ] Boss enemies with unique patterns
  - [ ] Enemy variants with different behaviors

- [ ] **Player Combat Expansion**
  - [ ] Special attacks/skills (use energy/mana)
  - [ ] Weapon types with different ranges/damage
  - [ ] Blocking/parrying system
  - [ ] Dodge roll with invincibility frames
  - [ ] Charge attacks

- [ ] **Status Effects**
  - [ ] Poison (damage over time)
  - [ ] Slow (reduced movement speed)
  - [ ] Burn (fire dissolve effect + damage)
  - [ ] Freeze (immobilize)
  - [ ] Status effect visual indicators

### Inventory & Items
- [ ] **Inventory System**
  - [ ] Inventory UI (grid-based or list)
  - [ ] Item pickup and storage
  - [ ] Item categories (weapons, consumables, key items)
  - [ ] Item stacking and limits

- [ ] **Consumable Items**
  - [ ] Health potions
  - [ ] Energy/mana potions
  - [ ] Status cure items
  - [ ] Temporary buff items

- [ ] **Equipment System**
  - [ ] Weapon swapping (different attack patterns)
  - [ ] Armor/defense equipment
  - [ ] Accessories (stat boosts)
  - [ ] Equipment stats and modifiers

### World & Level Design
- [ ] **Dungeon System**
  - [ ] Multiple dungeon levels
  - [ ] Procedural generation (optional)
  - [ ] Locked doors and keys
  - [ ] Treasure chests
  - [ ] Secret areas

- [ ] **Overworld**
  - [ ] Town/hub area
  - [ ] NPCs and dialogue system
  - [ ] Shop system for buying items
  - [ ] Quest board

- [ ] **Scene Transitions**
  - [ ] Door/portal system
  - [ ] Scene connection metadata
  - [ ] Load player state between scenes

### UI/UX Improvements
- [ ] **HUD Elements**
  - [ ] Health bar (current implementation: signals exist)
  - [ ] Energy/mana bar
  - [ ] Mini-map
  - [ ] Item quick-slots
  - [ ] Status effect indicators

- [ ] **Menus**
  - [ ] Pause menu (inventory, stats, save/load)
  - [ ] Settings menu (audio, controls, graphics)
  - [ ] Death menu (retry, return to checkpoint, quit)

- [ ] **Tutorial System**
  - [ ] On-screen prompts for controls
  - [ ] Tutorial messages for new mechanics
  - [ ] Skip tutorial option

### Audio & Polish
- [ ] **Music System**
  - [ ] Background music per area
  - [ ] Combat music transitions
  - [ ] Boss music
  - [ ] Music crossfading

- [ ] **Sound Effects**
  - [ ] More varied enemy sounds
  - [ ] Environmental sounds (water, fire, wind)
  - [ ] UI sounds (menu navigation, item pickup)
  - [ ] Footstep variations by terrain type

- [ ] **Visual Effects**
  - [ ] Particle effects for abilities
  - [ ] Hit effects (sparks, blood, impact)
  - [ ] Environmental effects (rain, fog, lighting)
  - [ ] Post-processing (color grading, vignette)

### Advanced AI
- [ ] **Pathfinding Improvements**
  - [ ] Implement A* pathfinding (`astar_pathfinding.gd` exists)
  - [ ] Dynamic obstacle avoidance
  - [ ] Group coordination (enemies surround player)

- [ ] **AI Behaviors**
  - [ ] Patrol routes
  - [ ] Alert/search states
  - [ ] Flee when low health
  - [ ] Call for reinforcements

### Progression Systems
- [ ] **Experience & Leveling**
  - [ ] XP from defeating enemies
  - [ ] Level up system
  - [ ] Stat increases on level up
  - [ ] Skill tree or ability unlocks

- [ ] **Quest System**
  - [ ] Main story quests
  - [ ] Side quests
  - [ ] Quest tracking UI
  - [ ] Quest rewards

- [ ] **Achievements**
  - [ ] Achievement definitions
  - [ ] Achievement tracking
  - [ ] Achievement notifications

---

## 🐛 KNOWN ISSUES & TECHNICAL DEBT

### High Priority
- [ ] **Ted's hit box integration** - Currently uses direct damage call instead of hit box system
- [ ] **Tile reservation cleanup** - Ensure tiles are released properly on death/scene change
- [ ] **Animation frame-perfect timing** - Some attack animations may need frame-by-frame adjustment

### Medium Priority
- [ ] **Camera bounds** - Camera can show outside playable area
- [ ] **Memory management** - Ensure damage text nodes are properly freed
- [ ] **Audio overlap** - Multiple footstep sounds can overlap when moving quickly

### Low Priority
- [ ] **Code organization** - Consider splitting large scripts (player.gd is 520 lines)
- [ ] **Magic numbers** - Extract more constants to top of files
- [ ] **Error handling** - Add more null checks and error messages

---

## 🎯 IMMEDIATE NEXT STEPS

1. **Terrain System Foundation** (Week 1-2)
   - Implement elevation system
   - Add height-based collision
   - Create multi-level test scene

2. **Save System MVP** (Week 2-3)
   - Implement basic save/load to JSON
   - Save statue interaction
   - Respawn at checkpoint on death

3. **Basic Inventory** (Week 3-4)
   - Inventory data structure
   - Simple UI (list view)
   - Health potion pickup and use

4. **More Enemy Types** (Week 4-5)
   - Create 2-3 new enemy variants using TileMovementController
   - Different AI behaviors (ranged, fast, tank)
   - Test combat balance

5. **First Complete Dungeon** (Week 5-6)
   - Design 3-5 room dungeon
   - Place enemies and items
   - Add save statue at end
   - Create simple boss encounter

---

## 📝 NOTES

### Architecture Decisions
- Using tile-based movement for grid alignment (8x4 tiles)
- Hit/Hurt box pattern for all combat interactions
- Signal-based health/state changes for UI updates
- SceneTransition singleton for all scene changes

### Performance Considerations
- Keep entity count reasonable (<50 enemies on screen)
- Limit particle effects in combat
- Use object pooling for damage text if needed
- Optimize pathfinding with caching

### Design Philosophy
- Responsive combat (instant feedback)
- Clear visual communication (damage numbers, effects)
- Grid-based precision (tile snapping)
- Gradual difficulty progression

### Testing Checklist for New Features
- [ ] Works with existing combat system
- [ ] Maintains tile alignment
- [ ] Animations face correct direction
- [ ] Proper cleanup on death/scene change
- [ ] No memory leaks
- [ ] Signals emit correctly
- [ ] Sound effects play without overlap
