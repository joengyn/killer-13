@tool
extends Node
## CardLoader - Singleton autoload that manages card sprite atlases from spritesheet
##
## Loads the card spritesheet on _ready() and creates AtlasTexture regions for all 52 cards
## plus the card back. Provides lookup methods to retrieve sprites by rank and suit.
##
## Spritesheet Layout (colored-cards.png):
## - Column 0: Card back
## - Columns 1: Ace
## - Columns 2-9: Cards 2-9
## - Columns 10: 10
## - Columns 11-13: Jack, Queen, King
## - Rows 0-3: Light mode (Heart, Spade, Diamond, Club)
## - Rows 4-7: Dark mode (Heart, Spade, Diamond, Club) - DEFAULT

## Dictionary mapping "rank_suit" keys to AtlasTexture sprites (e.g., "0_1" = THREE of CLUBS)
var card_sprites: Dictionary = {}
## AtlasTexture for the card back (column 0, dark mode)
var card_back_sprite: AtlasTexture
## The loaded spritesheet texture
var texture: Texture2D
## Whether to use dark mode (true) or light mode (false) for cards
var use_dark_mode: bool = true

func _ready() -> void:
	load_sprites()

## Load all card sprites from the spritesheet and populate the card_sprites dictionary
func load_sprites() -> void:
	texture = preload("res://assets/colored-cards.png")
	if not texture:
		push_error("CardLoader: Failed to load spritesheet")
		return

	var card_width = float(texture.get_width()) / Constants.CARD_SPRITESHEET_COLUMNS
	var card_height = float(texture.get_height()) / Constants.CARD_SPRITESHEET_ROWS

	# Map Card rank enum values (0-12) to spritesheet column indices
	# Card.Rank enum: THREE=0, FOUR=1, FIVE=2, ..., QUEEN=9, KING=10, ACE=11, TWO=12
	# Spritesheet columns: 0=back, 1=A, 2=2, 3=3, 4=4, ..., 13=K
	var rank_to_col = [
		3,   # THREE (rank 0) -> column 3
		4,   # FOUR (rank 1) -> column 4
		5,   # FIVE (rank 2) -> column 5
		6,   # SIX (rank 3) -> column 6
		7,   # SEVEN (rank 4) -> column 7
		8,   # EIGHT (rank 5) -> column 8
		9,   # NINE (rank 6) -> column 9
		10,  # TEN (rank 7) -> column 10
		11,  # JACK (rank 8) -> column 11
		12,  # QUEEN (rank 9) -> column 12
		13,  # KING (rank 10) -> column 13
		1,   # ACE (rank 11) -> column 1
		2,   # TWO (rank 12) -> column 2
	]

	# Map Card enum suit values to row offsets (before theme offset is applied)
	# Suit enum: SPADES=0, CLUBS=1, DIAMONDS=2, HEARTS=3
	# Base rows (0-3): Light mode
	# Base rows + 4: Dark mode (default)
	var suit_to_row_base = [
		1,   # SPADES (suit 0) -> row 1 (light) or 5 (dark)
		3,   # CLUBS (suit 1) -> row 3 (light) or 7 (dark)
		2,   # DIAMONDS (suit 2) -> row 2 (light) or 6 (dark)
		0,   # HEARTS (suit 3) -> row 0 (light) or 4 (dark)
	]

	# Determine theme offset
	var theme_offset = Constants.CARD_THEME_DARK_MODE_ROW_OFFSET if use_dark_mode else Constants.CARD_THEME_LIGHT_MODE_ROW_OFFSET

	# Load all 52 cards
	for rank in range(13):  # 0-12 (THREE to TWO)
		for suit in range(4):  # 0-3 (SPADES to HEARTS)
			var col = rank_to_col[rank]
			var row = suit_to_row_base[suit] + theme_offset

			var atlas = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * card_width, row * card_height, card_width, card_height)

			# Create key from rank/suit enums
			var key = "%d_%d" % [rank, suit]
			card_sprites[key] = atlas

	# Load card back (column 0, dark mode)
	var back_atlas = AtlasTexture.new()
	back_atlas.atlas = texture
	back_atlas.region = Rect2(0, (4 * card_height), card_width, card_height)
	card_back_sprite = back_atlas


## Get the sprite atlas for a specific card
## @param rank: Card.Rank enum value (0-12, where THREE=0, TWO=12)
## @param suit: Card.Suit enum value (0-3, where SPADES=0, HEARTS=3)
## @return: AtlasTexture for the requested card, or null if not found
func get_card_sprite(rank: int, suit: int) -> AtlasTexture:
	var key = "%d_%d" % [rank, suit]
	if key in card_sprites:
		return card_sprites[key]
	else:
		push_error("Card sprite not found: rank=%d, suit=%d" % [rank, suit])
		return null

## Get the card back sprite atlas
## @return: AtlasTexture for the red card back design
func get_card_back() -> AtlasTexture:
	return card_back_sprite
