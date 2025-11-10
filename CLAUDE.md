# Killer 13 Card Game - Development Guide

## 📋 Project Overview
This is a digital implementation of **Killer 13** (based on Tiến Lên, Vietnamese card game "13"), built in **Godot 4.5**. The game is a shedding-style card game where players compete to be the first to rid themselves of all cards by playing valid card combinations.

For complete game rules, see [RULES.md](RULES.md).

---

## 🛠 Tech Stack
- **Engine:** Godot 4.5 (GL Compatibility renderer)
- **Language:** GDScript
- **Target Platforms:** Desktop (Windows, macOS, Linux)
- **Number of Players:** 2-4 (optimized for 4)

---

## 🎮 Game Architecture

### Core Systems
1. **Card System**
   - Card representation (rank, suit, visual asset)
   - Card ranking logic (comparison, sorting)
   - Deck management (shuffling, dealing)

2. **Hand Management**
   - Player hand storage and organization
   - Card selection/deselection UI
   - Hand validation (checking valid plays)

3. **Game State Management**
   - Current turn tracking
   - Active table combination
   - Player order (circular)
   - Win/loss conditions

4. **Combination Validation**
   - Single cards
   - Pairs, triples, four of a kind
   - Straights (4+ consecutive ranks)
   - Bombs (combinations that beat 2s)
   - Comparison logic (can a combination beat another?)

5. **Game Flow Logic**
   - Turn progression
   - Play validation and rejection
   - Pass handling
   - Round reset
   - Game end detection

### UI/UX Components
1. **Table View**
   - Player positions (0, 1, 2, 3 in clockwise order)
   - Current table play display
   - Player card counts
   - Current player indicator

2. **Hand UI**
   - Card display (fannable or linear)
   - Card selection/highlighting
   - Play button / Pass button
   - Hand organization (by rank, by suit)

3. **Game Status**
   - Turn indicator
   - Valid play feedback
   - Game result screen
   - Rankings/leaderboard

---

## 🚀 Development Roadmap

### Phase 1: Core Game Logic
- [ ] Create Card class/struct
- [ ] Implement Deck class with shuffling/dealing
- [ ] Create Hand class for player card management
- [ ] Implement card ranking and comparison system
- [ ] Build combination detection (singles, pairs, triples, straights)
- [ ] Implement bomb detection logic
- [ ] Create game state manager
- [ ] Test all combination validation logic

### Phase 2: Basic Game Flow
- [ ] Implement turn system and player cycling
- [ ] Build play validation (beats previous play)
- [ ] Implement pass functionality
- [ ] Add round reset logic
- [ ] Implement win/loss detection
- [ ] Add game end screen

### Phase 3: UI/UX (Single Player/Local)
- [ ] Create card sprite/assets (or use placeholders)
- [ ] Build table scene with player positions
- [ ] Implement hand display UI
- [ ] Add card selection mechanics
- [ ] Create play/pass buttons
- [ ] Display current table play
- [ ] Add turn indicators and feedback

### Phase 4: AI Players (Computer Opponents)
- [ ] Implement basic AI strategy
- [ ] Add medium difficulty AI
- [ ] Implement hard difficulty AI
- [ ] Test AI vs AI gameplay

### Phase 5: Polish & Features
- [ ] Add sound effects
- [ ] Add animations (card plays, dealing, etc.)
- [ ] Implement game settings/preferences
- [ ] Add game statistics tracking
- [ ] Improve visual feedback and UX
- [ ] Performance optimization

### Phase 6: Advanced Features (Optional)
- [ ] Multiplayer support (local network)
- [ ] Replay/undo functionality
- [ ] Custom themes/card designs
- [ ] Mobile adaptation

---

## 📁 Suggested Project Structure

```
tien-len/
├── scenes/
│   ├── main_game.tscn
│   ├── table.tscn
│   ├── player_hand.tscn
│   ├── card.tscn
│   └── ui/
│       ├── hud.tscn
│       ├── game_over_screen.tscn
│       └── buttons.tscn
├── scripts/
│   ├── card.gd
│   ├── deck.gd
│   ├── hand.gd
│   ├── game_manager.gd
│   ├── player.gd
│   ├── ai_player.gd
│   ├── validation/
│   │   ├── combination_validator.gd
│   │   ├── card_comparer.gd
│   │   └── bomb_detector.gd
│   └── ui/
│       ├── table_ui.gd
│       ├── hand_ui.gd
│       └── hud.gd
├── assets/
│   ├── sprites/
│   │   └── cards/ (card sprites)
│   ├── sounds/ (optional)
│   └── fonts/ (optional)
├── RULES.md (game rules reference)
└── CLAUDE.md (this file)
```

---

## 🎯 Implementation Tips

1. **Start with validation:** The core of the game is validating combinations and comparing plays. Get this right first.
2. **Separate concerns:** Keep UI, game logic, and AI separate for easier testing and iteration.
3. **Test combinations thoroughly:** Create unit tests for combination detection and card comparison.
4. **Use enums:** Leverage GDScript enums for suits, ranks, and game states.
5. **Prototype quickly:** Get a working prototype with placeholder graphics first, then enhance visuals.

---

## 🔗 References
- **Game Rules:** See [RULES.md](RULES.md) for complete gameplay mechanics
- **Godot Docs:** https://docs.godotengine.org/en/stable/index.html
- **GDScript Guide:** https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/index.html

---

**Status:** Project initialization - Ready to begin Phase 1 development.
