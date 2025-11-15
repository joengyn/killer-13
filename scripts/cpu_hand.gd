extends Node2D
## CPUHand - Displays opponent cards (all face-down, no interaction)

const CARD_SPACING: float = 60.0  # Horizontal spacing between cards

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
	var card_visual = preload("res://scenes/card.tscn").instantiate() as Node
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
		var card_visual = preload("res://scenes/card.tscn").instantiate() as Node
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

	# Arrange cards
	_arrange_cards()


func animate_to_center(duration: float = 0.3) -> void:
	"""Animates the CPU hand towards the center of the screen."""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)

	# Calculate target position: move towards the center of the screen
	# Assuming screen center is (960, 540) for a 1920x1080 resolution
	var screen_center = Vector2(960, 540)
	var direction_to_center = (screen_center - global_position).normalized()
	var offset_amount = 50 # Pixels to offset

	var target_position = _original_position + direction_to_center * offset_amount
	
	tween.tween_property(self, "position", target_position, duration)


func animate_to_original_position(duration: float = 0.3) -> void:
	"""Animates the CPU hand back to its original position."""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "position", _original_position, duration)

