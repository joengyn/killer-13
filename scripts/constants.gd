extends Node
## Constants - Centralized configuration for the Tiến Lên card game

# ============================================================================
# GAME RULES & MECHANICS
# ============================================================================

const NUM_PLAYERS = 4
const CARDS_PER_PLAYER = 13
const TOTAL_CARDS = 52
const MAX_TURNS = 1000  # Safety limit to prevent infinite loops in game simulator

# ============================================================================
# UI LAYOUT - Player Positions
# ============================================================================

# Player position offsets from viewport edges (for 4-player layout)
const PLAYER_0_Y_OFFSET = -100        # Bottom center player
const PLAYER_1_X_OFFSET = 80          # Left center player
const PLAYER_2_Y_OFFSET = 100         # Top center player
const PLAYER_3_X_OFFSET = 80          # Right center player (calculated from right edge)

# ============================================================================
# UI LAYOUT - Card Spacing
# ============================================================================

const CARD_SPACING_NORMAL = 12.0      # Pixels between cards for players 1, 2, 3
const CARD_SPACING_PLAYER_0 = 60.0    # Wider spacing for player 0 (bottom) for readability

# ============================================================================
# UI LAYOUT - Table Display
# ============================================================================

const TABLE_CARD_START_X = -50.0      # X offset for first card on table
const TABLE_CARD_SPACING = 40.0       # X spacing between table cards

# ============================================================================
# UI LAYOUT - Buttons
# ============================================================================

const BUTTON_SIZE = Vector2(80, 40)
const BUTTON_SPACING = 10              # Pixels between buttons
const BUTTON_MARGIN = 20               # Margin from viewport edge

# ============================================================================
# UI LAYOUT - Victory Overlay
# ============================================================================

const VICTORY_OVERLAY_SIZE = Vector2(200, 150)
const VICTORY_OVERLAY_PADDING = 20                # Padding on left/right edges
const VICTORY_LABEL_FONT_SIZE = 40
const VICTORY_BUTTON_SIZE = Vector2(180, 60)
const VICTORY_LABEL_SIZE = Vector2(150, 60)
const VICTORY_LABEL_MARGIN = 20

# ============================================================================
# TIMING & ANIMATIONS
# ============================================================================

const TURN_TIMER_WAIT_TIME = 0.01     # Delay between AI turns (milliseconds)
const CARD_ANIMATION_DURATION = 0.5   # Duration of card tween animation (seconds)
const VICTORY_DELAY = 1.0              # Delay before showing victory screen (seconds)

# ============================================================================
# SPRITESHEET CONFIGURATION
# ============================================================================

const CARD_SPRITESHEET_PATH = "res://assets/kerenel_Cards.png"
const CARD_SPRITESHEET_COLUMNS = 14   # 14 columns (column 0 is blank/back, 1-13 are A-K)
const CARD_SPRITESHEET_ROWS = 6       # 6 rows (rows 0-3 are used, 4-5 unused color sets)

# ============================================================================
# CARD RANKS & SUITS (matching Card.gd enums)
# ============================================================================

enum CardRank { THREE, FOUR, FIVE, SIX, SEVEN, EIGHT, NINE, TEN, JACK, QUEEN, KING, ACE, TWO }
enum CardSuit { SPADES, CLUBS, DIAMONDS, HEARTS }
