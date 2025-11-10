extends Node2D
## CardVisual - Displays a card sprite and handles visual state

var card: Card  # Reference to the card data
@onready var sprite = $Sprite2D

func _ready():
	# Initialize sprite if card is set
	if card:
		_load_sprite()

func set_card(new_card: Card):
	"""Set this visual to display a specific card"""
	card = new_card
	if is_node_ready() and sprite:
		_load_sprite()
	# If not ready yet, _ready() will handle it

func _load_sprite():
	"""Load the card sprite"""
	if not card:
		push_error("CardVisual: No card set")
		return
	if not sprite:
		push_error("CardVisual: Sprite2D not found at $Sprite2D")
		return

	var sprite_texture = CardLoader.get_card_sprite(card.rank, card.suit)
	if sprite_texture:
		sprite.texture = sprite_texture
	else:
		push_error("CardVisual: get_card_sprite returned null for rank %d suit %d" % [card.rank, card.suit])

func set_card_back():
	"""Show card back instead of face"""
	if sprite:
		sprite.texture = CardLoader.get_card_back()

func set_selected(selected: bool):
	"""Highlight/unhighlight the card"""
	if selected:
		highlight()
	else:
		unhighlight()

func highlight():
	"""Add visual highlight to card"""
	modulate = Color(1.3, 1.3, 1.3)  # Brighten slightly

func unhighlight():
	"""Remove highlight"""
	modulate = Color.WHITE
