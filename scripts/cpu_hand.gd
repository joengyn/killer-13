extends Node2D
## CPUHand - Displays opponent cards (all face-down, no interaction)

## ============================================================================
## CONFIGURATION - Adjustable via Godot Inspector
## ============================================================================

## Duration for animating hand to center
@export var animate_to_center_duration: float = 0.3
## Scale multiplier when hand is animated to center
@export var center_scale_multiplier: float = 1.1
## Duration for animating hand back to original position
@export var animate_to_original_duration: float = 0.3
## Offset amount when moving toward center (in pixels)
@export var center_offset_amount: float = 100.0

## ============================================================================
## DERIVED VALUES
## ============================================================================

var CARD_SPACING: float:
	get: return Constants.CPU_HAND_CARD_SPACING

var _cards: Array[Node] = []  # Track current cards in hand
var _original_position: Vector2 # Store the original position of the hand

func _ready() -> void:
	# Store the original position of the hand
	_original_position = position
	# At runtime, remove any preview cards that may exist in the scene
	for card in get_children():
		card.queue_free()


func _arrange_cards() -> void:
	"""Arrange cards in a straight horizontal line with tighter spacing for more overlap"""
	if _cards.size() == 0:
		return

	var card_count = _cards.size()
	# Calculate total width and center offset (same as PlayerHand logic)
	var total_width = (card_count - 1) * CARD_SPACING
	var start_x = -total_width / 2.0

	for idx in range(card_count):
		var card = _cards[idx]
		var x = start_x + (idx * CARD_SPACING)
		card.position = Vector2(x, 0)


func add_card() -> void:
	"""Add a single card back to the hand (used during dealing)"""
	var card_visual = CardPool.get_card()
	add_child(card_visual)

	# Set to show back
	if card_visual.has_method("set_show_back"):
		card_visual.set_show_back(true)

	# Hide shadows
	if card_visual.has_method("set_shadow_visible"):
		card_visual.set_shadow_visible(false)

	var shadow_sprite = card_visual.get_node_or_null("ShadowSprite")
	if shadow_sprite:
		shadow_sprite.visible = false

	# Track the new card
	_cards.append(card_visual)

	# Disable interaction for CPU cards
	var interaction = card_visual.get_node_or_null("Interaction")
	if interaction:
		interaction.is_player_card = false

	# Rearrange cards to accommodate the new one
	_arrange_cards()


func clear_and_set_count(count: int) -> void:
	"""Remove all child cards and create exact number of card backs (runtime use)"""
	# Clear the tracking array immediately (fixes centering bug)
	_cards.clear()

	# Remove all existing card nodes
	for card in get_children():
		card.queue_free()

	# Create new card back visuals
	for idx in range(count):
		var card_visual = CardPool.get_card()
		add_child(card_visual)

		# Set to show back
		if card_visual.has_method("set_show_back"):
			card_visual.set_show_back(true)

		# Hide shadows
		if card_visual.has_method("set_shadow_visible"):
			card_visual.set_shadow_visible(false)

		var shadow_sprite = card_visual.get_node_or_null("ShadowSprite")
		if shadow_sprite:
			shadow_sprite.visible = false

		# Track the new card
		_cards.append(card_visual)

		# Disable interaction for CPU cards
		var interaction = card_visual.get_node_or_null("Interaction")
		if interaction:
			interaction.is_player_card = false

	# Arrange cards
	_arrange_cards()


func animate_to_center(duration: float = -1.0) -> void:
	"""Animates the CPU hand towards the center of the screen."""
	if duration < 0:
		duration = animate_to_center_duration

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)

	# Calculate target position: move towards the center of the screen
	# Assuming screen center is (960, 540) for a 1920x1080 resolution
	var screen_center = Vector2(960, 540)
	var direction_to_center = (screen_center - global_position).normalized()

	var target_position = _original_position + direction_to_center * center_offset_amount

	tween.tween_property(self, "position", target_position, duration)
	tween.tween_property(self, "scale", Vector2(center_scale_multiplier, center_scale_multiplier), duration)


func animate_to_original_position(duration: float = -1.0) -> void:
	"""Animates the CPU hand back to its original position."""
	if duration < 0:
		duration = animate_to_original_duration

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "position", _original_position, duration)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), duration)

func clear_all_cards() -> void:
	"""Removes all cards from the CPU hand."""
	for card in _cards:
		card.queue_free()
	_cards.clear()


func _exit_tree() -> void:
	"""Clean up all resources when CPUHand is freed"""
	# Clear all cards
	for card in _cards:
		if is_instance_valid(card):
			card.queue_free()
	_cards.clear()

