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
## SPRITESHEET CONFIGURATION
## ============================================================================

## Number of columns in the card spritesheet (0=backs/blanks, 1-13=A through K)
const CARD_SPRITESHEET_COLUMNS: int = 14
## Number of rows in the card spritesheet (0-3=suits, 4-5=unused alternate colors)
const CARD_SPRITESHEET_ROWS: int = 6
