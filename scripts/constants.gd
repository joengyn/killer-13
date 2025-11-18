extends Node
class_name GameConstants
## Constants - Global configuration values for Tiến Lên card game
##
## Centralizes all magic numbers and configuration values for easy tuning.
## All values are const and accessible throughout the codebase via Constants.VARIABLE_NAME

## ============================================================================
## CARD DISPLAY CONFIGURATION
## ============================================================================

## Visual scale multiplier applied to card sprites (base 56x80 → scaled 224x320)
const CARD_SCALE: float = 4.0
## Base width of card sprite in pixels (before CARD_SCALE applied)
const CARD_BASE_WIDTH: float = 56.0
## Base height of card sprite in pixels (before CARD_SCALE applied)
const CARD_BASE_HEIGHT: float = 80.0

## Derived: Final displayed width of cards (CARD_BASE_WIDTH * CARD_SCALE)
const CARD_WIDTH: float = CARD_BASE_WIDTH * CARD_SCALE
## Derived: Final displayed height of cards (CARD_BASE_HEIGHT * CARD_SCALE)
const CARD_HEIGHT: float = CARD_BASE_HEIGHT * CARD_SCALE

## ============================================================================
## HAND DISPLAY CONFIGURATION
## ============================================================================

const HAND_CARD_SPACING: float = 115.0
const HAND_PREVIEW_GAP: float = 195.0
const HAND_BOUNDS_PADDING: float = 20.0

## ============================================================================
## PLAY ZONE CONFIGURATION
## ============================================================================

## Gap between cards in the play zone
const PLAY_ZONE_CARD_GAP: float = 20.0
## Maximum width for cards in the play zone (based on 13 cards)
const PLAY_ZONE_MAX_WIDTH: float = 1604.0

## ============================================================================
## CPU HAND CONFIGURATION
## ============================================================================

## Horizontal spacing between CPU hand cards
const CPU_HAND_CARD_SPACING: float = 60.0

## ============================================================================
## CARD INTERACTION CONFIGURATION
## ============================================================================

## Cooldown frames for click detection to prevent rapid clicks
const CARD_CLICK_COOLDOWN_FRAMES: int = 10

## ============================================================================
## CARD VISUAL CONFIGURATION
## ============================================================================

## Shadow sprite vertical offset for perspective effect
const CARD_SHADOW_VERTICAL_OFFSET: float = 10.0
## Shadow sprite maximum horizontal offset from card center
const CARD_SHADOW_MAX_HORIZONTAL_OFFSET: float = 12.0

## ============================================================================
## DEALING CONFIGURATION
## ============================================================================

## Card count threshold for card dealing (last 5 cards pop from deck, first 47 are instantiated)
const DEALING_INSTANTIATE_THRESHOLD: int = 47
## Delay between card deals in seconds (for animation pacing)
const DEAL_CARD_INTERVAL: float = 0.015

## ============================================================================
## SPRITESHEET CONFIGURATION
## ============================================================================

## Number of columns in the card spritesheet (0=backs/blanks, 1-13=A through K)
const CARD_SPRITESHEET_COLUMNS: int = 14
## Number of rows in the card spritesheet (0-3=suits, 4-5=unused alternate colors)
const CARD_SPRITESHEET_ROWS: int = 6
