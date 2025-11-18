# Killer 13 Card Game

A digital implementation of **Killer 13** (based on Tiến Lên, the Vietnamese card game "13"), built in Godot 4.5. This is a 2-4 player strategic card game with AI opponents, featuring intuitive drag-and-drop gameplay and smooth animations.

## Game Rules

For complete game rules and mechanics, see [RULES.md](RULES.md).

Quick summary:
- Win by playing all your cards first
- Cards are ranked 3–15, suit-independent
- Valid plays: single cards, pairs, triples, sequences, and bombs
- Bombs are special patterns that force opponents to pass
- Defense: Respond to attacks with higher-ranked cards

## Quick Start

### How to Play

1. **Starting a Game**: Launch the game and click "New Game" from the main menu
2. **Your Turn**: When it's your turn, select cards from your hand and drag them to the play zone
3. **Playing Cards**:
   - Click cards to select/deselect them
   - Drag selected cards to the table
   - Click "Play" to submit your turn
4. **Passing**: Click "Pass" if you cannot or choose not to play
5. **Winning**: Be the first to play all your cards

## Development Setup

### Prerequisites

- **Godot 4.5+**: Download from [godotengine.org](https://godotengine.org)
- **GL Compatibility Renderer**: Ensure your Godot build includes GL compatibility support

### Building from Source

1. **Clone Repository**:
   ```bash
   git clone <repository-url>
   cd killer-13
   ```

2. **Open in Godot**:
   - Launch Godot 4.5
   - Click "Open Project"
   - Navigate to the `killer-13` folder
   - Click "Select Folder"

3. **Run the Game**:
   - Press `F5` in Godot editor to launch the game
   - Or click "Run" → "Play Scene"

## Project Structure

```
killer-13/
├── README.md                    # This file
├── RULES.md                     # Complete game rules
├── CLAUDE.md                    # Development guide and AI persona
├── scripts/                     # All GDScript source files
│   ├── core/                    # Core game logic
│   │   ├── constants.gd         # Global constants and enums
│   │   ├── game_state.gd        # Game state management
│   │   ├── combination.gd       # Card combination validation
│   │   ├── game_manager.gd      # Game orchestration (autoload singleton)
│   │   ├── simple_ai.gd         # CPU player decision logic
│   │   └── card_pool.gd         # Card pooling system
│   ├── card/                    # Card system
│   │   ├── card.gd              # Card data model
│   │   ├── card_visual.gd       # Card rendering and visuals
│   │   ├── card_interaction.gd  # Card interaction handling
│   │   └── card_loader.gd       # Card sprite loading
│   ├── components/              # UI components
│   │   ├── hand.gd              # Base hand class
│   │   ├── player_hand.gd       # Player's hand with drag-drop
│   │   ├── cpu_hand.gd          # CPU hand visualization
│   │   ├── deck.gd              # Deck management
│   │   ├── deck_visual.gd       # Deck animation and dealing
│   │   ├── play_zone.gd         # Attack/defense card zones
│   │   └── round_tracker.gd     # Round display UI
│   └── ui/                      # Main UI screens
│       ├── main_menu.gd         # Main menu controller
│       └── game_screen.gd       # Main game orchestration
├── scenes/                      # Godot scene files
├── assets/                      # Game assets (sprites, audio, etc.)
└── project.godot                # Godot project configuration
```

## Architecture Overview

- **Game Logic**: Core game rules and state management live in `scripts/core/`
- **Visuals & Interaction**: UI and card rendering handled by components
- **Separation of Concerns**: Game logic (GameManager) is independent from UI (GameScreen)
- **Signal-Based Communication**: Components communicate via Godot signals rather than direct coupling
- **Singleton Pattern**: GameManager is an autoload singleton managing overall game state
- **Object Pooling**: Card instances are reused via card pool system for performance

For detailed architecture documentation, see [CLAUDE.md](CLAUDE.md).

## Development Workflow

### Code Organization

- Each file has a clear responsibility (single responsibility principle)
- Methods are organized logically: lifecycle → public API → helpers → signal handlers
- Complex algorithms are documented with detailed inline comments
- All public methods include docstrings with @param/@return annotations

### Code Style

This project follows Godot 4.5 conventions:
- snake_case for variables and functions
- PascalCase for class names
- Signals named with past tense (e.g., `card_played`, `turn_started`)
- @export variables for designer-tunable parameters
- @onready for cached node references

### Testing

Manual testing is performed:
1. Play through complete game scenarios
2. Test AI decision making at various game states
3. Verify animations and visual feedback
4. Test edge cases (empty hands, single card plays, bombs, etc.)

## Known Limitations

- Currently supports 2-4 players only (no larger groups)
- Network multiplayer not implemented
- Sound/music system not yet added
- Advanced AI strategies not fully implemented

---

**Last Updated**: November 18, 2025
**Engine Version**: Godot 4.5
**Development Status**: Active
