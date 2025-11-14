extends Node
## CardLoader - Singleton that loads and manages card sprites from spritesheet

# Sprite sheet layout:
# Column 0: Special (blanks, card backs, unused)
# Columns 1-13: A, 2, 3, 4, 5, 6, 7, 8, 9, 10, J, Q, K
# Row 0: Hearts, Row 1: Spades, Row 2: Diamonds, Row 3: Clubs
# Rows 4-5: Unused color sets (gold, blue)

var card_sprites = {}  # Store card atlases by rank+suit
var card_back_sprite: AtlasTexture
var texture: Texture2D

func _ready():
	load_sprites()

func load_sprites():
	texture = preload("res://assets/kerenel_Cards.png")
	if not texture:
		push_error("CardLoader: Failed to load spritesheet")
		return

	var card_width = float(texture.get_width()) / Constants.CARD_SPRITESHEET_COLUMNS
	var card_height = float(texture.get_height()) / Constants.CARD_SPRITESHEET_ROWS

	# Map Card rank enum values (0-12) to spritesheet column indices
	# Card.Rank enum: THREE=0, FOUR=1, FIVE=2, ..., QUEEN=9, KING=10, ACE=11, TWO=12
	# Spritesheet columns: 0=backs/blanks, 1=A, 2=2, 3=3, 4=4, ..., 13=K
	# Mapping: rank 0 (THREE) -> col 3, rank 1 (FOUR) -> col 4, ..., rank 11 (ACE) -> col 1, rank 12 (TWO) -> col 2
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

	# Map Card enum suit values to row indices
	# Suit enum: SPADES=0, CLUBS=1, DIAMONDS=2, HEARTS=3
	var suit_to_row = [
		1,   # SPADES (suit 0) -> row 1
		3,   # CLUBS (suit 1) -> row 3
		2,   # DIAMONDS (suit 2) -> row 2
		0,   # HEARTS (suit 3) -> row 0
	]

	# Load all 52 cards
	for rank in range(13):  # 0-12 (THREE to TWO)
		for suit in range(4):  # 0-3 (SPADES to HEARTS)
			var col = rank_to_col[rank]
			var row = suit_to_row[suit]

			var atlas = AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(col * card_width, row * card_height, card_width, card_height)

			# Create key from rank/suit enums
			var key = "%d_%d" % [rank, suit]
			card_sprites[key] = atlas

	# Load card back (column 0, row 2 - red card back)
	var back_atlas = AtlasTexture.new()
	back_atlas.atlas = texture
	back_atlas.region = Rect2(0, 2 * card_height, card_width, card_height)
	card_back_sprite = back_atlas


func get_card_sprite(rank: int, suit: int) -> AtlasTexture:
	"""Get sprite for a specific card by rank and suit enum values"""
	var key = "%d_%d" % [rank, suit]
	if key in card_sprites:
		return card_sprites[key]
	else:
		push_error("Card sprite not found: rank=%d, suit=%d" % [rank, suit])
		return null

func get_card_back() -> AtlasTexture:
	"""Get sprite for card back"""
	return card_back_sprite
