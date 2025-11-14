extends Node
## Constants - Centralized configuration for the Tiến Lên card game

# ============================================================================
# CARD DISPLAY CONFIGURATION
# ============================================================================

const CARD_SCALE: float = 4.0         # Visual scale multiplier for cards (base 56x80 pixels)
const CARD_BASE_WIDTH: float = 56.0   # Base card width in pixels (before scaling)
const CARD_BASE_HEIGHT: float = 80.0  # Base card height in pixels (before scaling)

# Derived constants (calculated from scale)
const CARD_WIDTH: float = CARD_BASE_WIDTH * CARD_SCALE
const CARD_HEIGHT: float = CARD_BASE_HEIGHT * CARD_SCALE

# ============================================================================
# SPRITESHEET CONFIGURATION
# ============================================================================

const CARD_SPRITESHEET_COLUMNS = 14   # 14 columns (column 0 is blank/back, 1-13 are A-K)
const CARD_SPRITESHEET_ROWS = 6       # 6 rows (rows 0-3 are used, 4-5 unused color sets)
