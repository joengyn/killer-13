@tool
extends Node2D
## CardVisual - Displays a card sprite

var card: Card
var show_back: bool = false  # Whether to display card back instead of card face

@onready var inner_sprite = $Viewport/InnerSprite
@onready var outer_sprite = $OuterSprite
@onready var shadow_sprite = $ShadowSprite

# Shadow effect constants
const SHADOW_VERTICAL_OFFSET: float = 10.0  # pixels (constant)
const SHADOW_MAX_HORIZONTAL_OFFSET: float = 12.0  # pixels (max)

var _last_shadow_update_pos: Vector2 = Vector2.ZERO  # Track last position to avoid redundant updates


func _ready():
	# Duplicate the shader material so each card instance has its own
	if not Engine.is_editor_hint():
		var outer = _get_outer_sprite()
		if outer and outer.material:
			outer.material = outer.material.duplicate()

	# Create default card for editor preview if needed
	if not card and Engine.is_editor_hint():
		card = Card.new(Card.Rank.ACE, Card.Suit.SPADES)

	# Always load sprite (card back or face)
	_load_sprite()


func set_card(new_card: Card):
	"""Set this visual to display a specific card"""
	card = new_card
	if is_node_ready() and inner_sprite:
		_load_sprite()


func set_show_back(back: bool) -> void:
	"""Toggle between showing card back or front face"""
	show_back = back
	if is_node_ready() and inner_sprite:
		_load_sprite()


func set_shadow_visible(show_shadow: bool) -> void:
	"""Show or hide the shadow effect"""
	var shadow = _get_shadow_sprite()
	if shadow:
		shadow.visible = show_shadow


func _get_inner_sprite() -> Sprite2D:
	"""Get inner sprite, handling @tool where @onready might not be ready"""
	return inner_sprite if inner_sprite else get_node_or_null("Viewport/InnerSprite")


func _get_outer_sprite() -> Sprite2D:
	"""Get outer sprite, handling @tool where @onready might not be ready"""
	return outer_sprite if outer_sprite else get_node_or_null("OuterSprite")


func _load_sprite():
	"""Load the card sprite (front face or back based on show_back property)"""
	if not card and not show_back:
		return

	var spr = _get_inner_sprite()
	if not spr:
		return

	# Get or create card loader (always have one available)
	var card_loader = get_node_or_null("/root/CardLoader")
	if not card_loader:
		var CardLoaderScript = load("res://scripts/card/card_loader.gd")
		if CardLoaderScript:
			card_loader = CardLoaderScript.new()
			card_loader.load_sprites()

	if not card_loader:
		push_error("CardVisual: Failed to create card loader")
		return

	# Load back or front face based on show_back property
	var sprite_texture: AtlasTexture
	if show_back:
		sprite_texture = card_loader.get_card_back()
	else:
		if not card:
			return
		sprite_texture = card_loader.get_card_sprite(card.rank, card.suit)

	if sprite_texture:
		spr.texture = sprite_texture


func _process(_delta: float) -> void:
	"""Update shadow position based on card's screen position (only if visible and position changed)"""
	var shadow = _get_shadow_sprite()
	if not shadow or not shadow.visible:
		return

	# Only update shadow if card position has changed
	if global_position != _last_shadow_update_pos:
		_update_shadow_position()
		_last_shadow_update_pos = global_position


func _update_shadow_position() -> void:
	"""Calculate and apply shadow offset based on card's distance from screen center.

	Creates perspective illusion: shadow shifts horizontally away from center as card
	moves left/right, giving appearance of floating/tilting card. Vertical offset fixed.
	"""
	var shadow = _get_shadow_sprite()
	if not shadow or not is_visible_in_tree():
		return

	var screen_center = get_viewport_rect().size / 2.0
	var card_global_pos = global_position
	var distance_from_center = card_global_pos.x - screen_center.x

	# Calculate horizontal offset: shifts shadow away from center as card moves away
	# When card is left of center (distance < 0), shadow shifts left (negative)
	# When card is right of center (distance > 0), shadow shifts right (positive)
	var horizontal_offset = lerp(
		0.0,
		-sign(distance_from_center) * SHADOW_MAX_HORIZONTAL_OFFSET,
		abs(distance_from_center / screen_center.x)
	)

	# Apply offsets: constant vertical offset + calculated horizontal offset
	shadow.offset = Vector2(horizontal_offset, SHADOW_VERTICAL_OFFSET)


func _get_shadow_sprite() -> Sprite2D:
	"""Get shadow sprite, handling @tool where @onready might not be ready"""
	return shadow_sprite if shadow_sprite else get_node_or_null("ShadowSprite")
