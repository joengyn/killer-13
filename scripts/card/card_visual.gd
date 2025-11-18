@tool
extends Node2D
## CardVisual - Renders a playing card with face/back display and shadow effects
##
## Manages the visual representation of a Card, including sprite loading, viewport rendering,
## and dynamic shadow positioning based on screen position. Supports @tool mode for editor preview.

## ============================================================================
## STATE
## ============================================================================

## The Card data this visual represents (rank + suit)
var card: Card
## Whether to display the card back instead of the face
var show_back: bool = false

## ============================================================================
## CONFIGURATION - Adjustable via Godot Inspector
## ============================================================================

## Shadow sprite vertical offset for perspective effect
@export var shadow_vertical_offset: float = 10.0
## Shadow sprite maximum horizontal offset from card center
@export var shadow_max_horizontal_offset: float = 12.0

## ============================================================================
## SCENE REFERENCES
## ============================================================================

@onready var inner_sprite = $Viewport/InnerSprite
@onready var outer_sprite = $OuterSprite
@onready var shadow_sprite = $ShadowSprite

## Cache last global position to avoid redundant shadow calculations
var _last_shadow_update_pos: Vector2 = Vector2.ZERO

## ============================================================================
## LIFECYCLE
## ============================================================================


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

## ============================================================================
## PUBLIC API
## ============================================================================

## Set which card this visual should display and reload the sprite
## @param new_card: The Card data (rank + suit) to display
func set_card(new_card: Card) -> void:
	card = new_card
	if is_node_ready() and inner_sprite:
		_load_sprite()

## Get the card data this visual represents
## @return: The Card object (rank + suit) being displayed
func get_card() -> Card:
	return card

## Toggle between showing the card's face or back
## @param back: If true, shows card back; if false, shows card face
func set_show_back(back: bool) -> void:
	show_back = back
	if is_node_ready() and inner_sprite:
		_load_sprite()

## Control shadow visibility (used for hover effects and card location)
## @param show_shadow: If true, shadow is visible; if false, it's hidden
func set_shadow_visible(show_shadow: bool) -> void:
	var shadow = _get_shadow_sprite()
	if shadow:
		shadow.visible = show_shadow

## ============================================================================
## HELPERS
## ============================================================================

## Get the inner sprite node (handles @tool mode where @onready may not execute)
## @return: The inner Sprite2D that displays the card texture
func _get_inner_sprite() -> Sprite2D:
	return inner_sprite if inner_sprite else get_node_or_null("Viewport/InnerSprite")

## Get the outer sprite node (handles @tool mode where @onready may not execute)
## @return: The outer Sprite2D that applies shader effects
func _get_outer_sprite() -> Sprite2D:
	return outer_sprite if outer_sprite else get_node_or_null("OuterSprite")


## Load and apply the appropriate sprite texture to the inner sprite
## Fetches the sprite from CardLoader singleton based on card data and show_back flag
func _load_sprite() -> void:
	if not card and not show_back:
		return

	var spr = _get_inner_sprite()
	if not spr:
		return

	# Get or create card loader (always have one available)
	var card_loader = CardLoader
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

## ============================================================================
## PROCESS
## ============================================================================

## Update shadow position each frame if card has moved
## Only recalculates when position changes to optimize performance
func _process(_delta: float) -> void:
	var shadow = _get_shadow_sprite()
	if not shadow or not shadow.visible:
		return

	# Only update shadow if card position has changed
	if global_position != _last_shadow_update_pos:
		_update_shadow_position()
		_last_shadow_update_pos = global_position


## Calculate and apply dynamic shadow offset to create perspective depth illusion
##
## Shadow shifts horizontally based on card's distance from screen center:
## - Cards on the left have shadow shifted left (negative offset)
## - Cards on the right have shadow shifted right (positive offset)
## - Cards in center have minimal horizontal shadow shift
## Vertical offset remains constant to maintain consistent lighting direction
func _update_shadow_position() -> void:
	var shadow = _get_shadow_sprite()
	if not shadow or not is_visible_in_tree():
		return

	var screen_center = get_viewport_rect().size / 2.0
	# Convert card's global position to screen space to account for camera transforms
	var screen_pos = get_canvas_transform() * global_position
	var distance_from_center = screen_pos.x - screen_center.x

	# Calculate horizontal offset: shifts shadow away from center as card moves away
	# When card is left of center (distance < 0), shadow shifts left (negative)
	# When card is right of center (distance > 0), shadow shifts right (positive)
	var horizontal_offset = lerp(
		0.0,
		-sign(distance_from_center) * shadow_max_horizontal_offset,
		abs(distance_from_center / screen_center.x)
	)

	# Apply offsets: constant vertical offset + calculated horizontal offset
	shadow.offset = Vector2(horizontal_offset, shadow_vertical_offset)


## Get the shadow sprite node (handles @tool mode where @onready may not execute)
## @return: The Sprite2D that renders the card's drop shadow
func _get_shadow_sprite() -> Sprite2D:
	return shadow_sprite if shadow_sprite else get_node_or_null("ShadowSprite")
