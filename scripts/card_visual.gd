extends Node2D
## CardVisual - Displays a card sprite and handles visual state

signal card_clicked(card: Card)

var card: Card  # Reference to the card data
var selected: bool = false
var _is_player_card: bool = false  # Only player cards are clickable
var original_position: Vector2 = Vector2.ZERO
var show_card_back: bool = false  # If true, show card back instead of face

var is_player_card: bool:
	get:
		return _is_player_card
	set(value):
		_is_player_card = value

@onready var sprite = $Sprite2D
@onready var click_area = $ClickArea
@onready var collision_shape = $ClickArea/CollisionShape2D

const SELECTION_Y_OFFSET = -20.0

func _ready():
	# Store original position for selection
	original_position = position

	# Initialize sprite if card is set
	if card:
		if show_card_back:
			set_card_back()
		else:
			_load_sprite()

func _input(event: InputEvent):
	"""Handle direct input on this card"""
	if not _is_player_card or not event is InputEventMouseButton:
		return

	if not (event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	# Get mouse position in global space
	var mouse_pos = get_global_mouse_position()

	# Get collision shape and check if mouse is within bounds
	if not collision_shape or not collision_shape.shape:
		return

	var rect_shape = collision_shape.shape as RectangleShape2D
	if not rect_shape:
		return

	# Calculate the shape bounds in global space
	var half_size = rect_shape.size / 2
	var shape_min = global_position - half_size
	var shape_max = global_position + half_size

	# Check if mouse is within the shape bounds
	if mouse_pos.x >= shape_min.x and mouse_pos.x <= shape_max.x and \
	   mouse_pos.y >= shape_min.y and mouse_pos.y <= shape_max.y:
		selected = !selected
		set_selected(selected)
		card_clicked.emit(card)
		get_tree().root.set_input_as_handled()

func set_card(new_card: Card):
	"""Set this visual to display a specific card"""
	card = new_card
	if is_node_ready() and sprite:
		_load_sprite()

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
		_update_collision_shape()
	else:
		push_error("CardVisual: get_card_sprite returned null for rank %d suit %d" % [card.rank, card.suit])

func set_card_back():
	"""Show card back instead of face"""
	if sprite:
		sprite.texture = CardLoader.get_card_back()
		_update_collision_shape()

func _update_collision_shape():
	"""Update collision shape to match the sprite texture dimensions"""
	if not sprite or not sprite.texture or not collision_shape:
		return

	var texture_size = sprite.texture.get_size()
	var scaled_size = texture_size * sprite.scale

	# Create a new collision shape instead of modifying the SubResource
	var new_shape = RectangleShape2D.new()
	new_shape.size = scaled_size
	collision_shape.shape = new_shape

func set_selected(is_selected: bool):
	"""Set selection state and update visuals"""
	selected = is_selected
	if selected:
		highlight()
	else:
		unhighlight()

func highlight():
	"""Add visual highlight to card (move up)"""
	position = original_position + Vector2(0, SELECTION_Y_OFFSET)

func unhighlight():
	"""Remove highlight"""
	position = original_position
