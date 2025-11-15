extends Node2D
## PlayZone - Manages cards that have been played/placed down

## Emitted when an atk card is clicked to return to hand
signal atk_card_clicked(card_visual: Node)

## Emitted when an atk card is dragged out of bounds to return to hand
signal atk_card_dragged_out(card_visual: Node)

## Emitted when an atk card drag starts
signal atk_card_drag_started(card_visual: Node)

var CARD_WIDTH: float:
	get: return Constants.CARD_WIDTH
var CARD_HEIGHT: float:
	get: return Constants.CARD_HEIGHT
const CARD_GAP: float = 20.0  # Gap between cards
var CARD_SPACING: float:
	get: return CARD_WIDTH + CARD_GAP

var _set_cards: Array[Node] = []  # Current active cards on the table
var _atk_cards: Array[Node] = []  # Cards player is attempting to play
var _player_hand: Node2D = null  # Reference to PlayerHand for returning cards

# Position offsets for atk cards relative to set cards
const ATK_OFFSET: Vector2 = Vector2(-40, -60)
const ATK_Z_INDEX: int = 10
const SET_Z_INDEX: int = 1


func _ready() -> void:
	# Find PlayerHand in parent
	var parent = get_parent()
	if parent:
		_player_hand = parent.get_node_or_null("PlayerHand")

	# Remove any preview cards that may exist in the scene file
	for child in get_children():
		child.queue_free()


func add_atk_card(card: Node) -> void:
	"""Add a card as an attack card to the play zone (floating above set cards)"""
	if _atk_cards.has(card):
		return  # Already in atk zone

	# Reparent card to PlayZone (will adjust global position to local)
	var old_global_pos = card.global_position
	var old_parent = card.get_parent()
	if old_parent:
		old_parent.remove_child(card)
	add_child(card)
	card.global_position = old_global_pos

	# Enable player card interactions (hover, click, drag) for atk cards
	var card_interaction = card.get_node_or_null("Interaction")
	if card_interaction:
		card_interaction.is_player_card = true
		# Update base position for hover animations
		if card_interaction.has_method("update_base_position"):
			card_interaction.update_base_position()

		# Connect to the card's interaction signals to detect clicks/drags
		_connect_atk_card_signals(card)

	_atk_cards.append(card)
	card.set_shadow_visible(true)
	card.z_index = ATK_Z_INDEX

	_sort_atk_cards()
	_arrange_cards()


func remove_atk_card(card: Node, new_parent: Node) -> void:
	"""Remove an atk card and return it to its parent"""
	if _atk_cards.has(card):
		_atk_cards.erase(card)

		# Disconnect card signals to prevent memory leaks
		_disconnect_atk_card_signals(card)

		# Reparent card back to original parent
		var old_global_pos = card.global_position
		remove_child(card)
		new_parent.add_child(card)
		card.global_position = old_global_pos

		_sort_atk_cards()
		_arrange_cards()


func _sort_atk_cards() -> void:
	"""Sort the attack cards by rank, then suit, using the static helper."""
	_atk_cards.sort_custom(Card.compare_card_nodes_lt)


func _connect_atk_card_signals(card: Node):
	"""Connect signals from atk card interactions"""
	var interaction = card.get_node_or_null("Interaction")
	if interaction:
		# Disconnect first to avoid duplicate connections
		if interaction.card_clicked.is_connected(_on_atk_card_clicked):
			interaction.card_clicked.disconnect(_on_atk_card_clicked)
		if interaction.drag_ended.is_connected(_on_atk_card_drag_ended):
			interaction.drag_ended.disconnect(_on_atk_card_drag_ended)
		if interaction.drag_started.is_connected(_on_atk_card_drag_started):
			interaction.drag_started.disconnect(_on_atk_card_drag_started)

		# Connect to PlayZone's handlers
		interaction.card_clicked.connect(_on_atk_card_clicked)
		interaction.drag_ended.connect(_on_atk_card_drag_ended)
		interaction.drag_started.connect(_on_atk_card_drag_started)


func _disconnect_atk_card_signals(card: Node):
	"""Disconnect signals from atk card interactions"""
	var interaction = card.get_node_or_null("Interaction")
	if interaction:
		if interaction.card_clicked.is_connected(_on_atk_card_clicked):
			interaction.card_clicked.disconnect(_on_atk_card_clicked)
		if interaction.drag_ended.is_connected(_on_atk_card_drag_ended):
			interaction.drag_ended.disconnect(_on_atk_card_drag_ended)
		if interaction.drag_started.is_connected(_on_atk_card_drag_started):
			interaction.drag_started.disconnect(_on_atk_card_drag_started)


func _on_atk_card_clicked(card: Node):
	"""Handle when an atk card is clicked - return it to the hand"""
	# Emit signal to notify GameScreen that atk card was clicked
	atk_card_clicked.emit(card)


func _on_atk_card_drag_started(card: Node):
	"""Handle when an atk card drag starts"""
	# Emit signal to notify GameScreen
	atk_card_drag_started.emit(card)


func _on_atk_card_drag_ended(card: Node):
	"""Handle when an atk card drag ends - check if it's outside play zone bounds"""
	# Check if the card is outside the play zone bounds
	var card_local_pos = card.global_position - global_position
	var play_zone_bounds = _get_bounds_rect()

	if not play_zone_bounds.has_point(card_local_pos):
		# Card was dragged outside play zone bounds - return to hand
		atk_card_dragged_out.emit(card)
	else:
		# Card was dropped inside the play zone - just rearrange to snap it back
		_arrange_cards()


func _arrange_cards() -> void:
	"""Arrange set cards in a line, and atk cards offset above them"""
	# Arrange set cards
	_arrange_set_cards()
	# Arrange atk cards
	_arrange_atk_cards()


func _arrange_set_cards() -> void:
	"""Arrange set cards in a straight horizontal line, centered"""
	if _set_cards.size() == 0:
		return

	var card_count = _set_cards.size()
	# Calculate total width and center offset
	var total_width = (card_count - 1) * CARD_SPACING
	var start_x = -total_width / 2.0

	for idx in range(card_count):
		var child = _set_cards[idx]
		var x = start_x + (idx * CARD_SPACING)
		child.position = Vector2(x, 0)
		child.z_index = SET_Z_INDEX


func _arrange_atk_cards() -> void:
	"""Arrange atk cards offset above the set cards"""
	if _atk_cards.size() == 0:
		return

	var card_count = _atk_cards.size()
	# Calculate total width and center offset (same as set cards)
	var total_width = (card_count - 1) * CARD_SPACING
	var start_x = -total_width / 2.0

	for idx in range(card_count):
		var child = _atk_cards[idx]
		var x = start_x + (idx * CARD_SPACING)
		# Position offset up and to the left
		child.position = Vector2(x, 0) + ATK_OFFSET
		# z_index increases with index (later cards render on top)
		child.z_index = ATK_Z_INDEX + idx

		# Update base position for hover animations
		var interaction = child.get_node_or_null("Interaction")
		if interaction and interaction.has_method("update_base_position"):
			interaction.update_base_position()

		# Reset hover state to prevent stale hover effects when z-indices change
		if interaction and interaction.has_method("reset_hover_state"):
			interaction.reset_hover_state()


func _get_bounds_rect() -> Rect2:
	"""Calculate the bounding rectangle of the play zone (includes both set and atk cards)"""
	var total_cards = _set_cards.size() + _atk_cards.size()

	if total_cards == 0:
		# Return a default empty bounds centered at origin
		return Rect2(Vector2(-CARD_WIDTH / 2.0, -CARD_HEIGHT / 2.0), Vector2(CARD_WIDTH, CARD_HEIGHT))

	# Use the larger count for width calculation
	var card_count = max(_set_cards.size(), _atk_cards.size())

	# Total width of the cards in play
	var total_width = (card_count - 1) * CARD_SPACING + CARD_WIDTH
	var half_width = total_width / 2.0

	# Account for atk card offset (they extend upward and leftward)
	var atk_offset_y = ATK_OFFSET.y if _atk_cards.size() > 0 else 0.0

	# Create bounds rect centered at origin with padding for interaction
	var bounds = Rect2(
		Vector2(-half_width, atk_offset_y - CARD_HEIGHT / 2.0),
		Vector2(total_width, CARD_HEIGHT * 2)  # Extra height to account for atk cards above
	)

	return bounds


func get_atk_cards() -> Array[Node]:
	"""Return array of atk cards"""
	return _atk_cards.duplicate()


func clear_atk_cards() -> void:
	"""Clear all atk cards from the zone"""
	_atk_cards.clear()
	_arrange_cards()


func set_set_cards(cards: Array[Node]) -> void:
	"""Set the current set cards on the table"""
	_set_cards = cards.duplicate()
	for card in _set_cards:
		card.z_index = SET_Z_INDEX
		# Set cards are not interactive (can't be clicked/dragged)
		var card_interaction = card.get_node_or_null("Interaction")
		if card_interaction:
			card_interaction.is_player_card = false
	_arrange_cards()


func commit_atk_to_set() -> void:
	"""Commit atk cards to become new set cards (called when Play is pressed and validated)"""
	if _atk_cards.is_empty():
		return

	# Animate atk cards to set positions
	for i in range(_atk_cards.size()):
		var atk_card = _atk_cards[i]
		var target_pos = _get_set_position(i)

		# Create tween to animate position
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(atk_card, "position", target_pos, 0.3)

	# After animation completes, finalize the transition
	await get_tree().create_timer(0.35).timeout

	# Remove old set cards from scene (includes face-down placeholder if present)
	for card in _set_cards:
		card.queue_free()

	# Move atk cards to set cards
	_set_cards = _atk_cards.duplicate()
	_atk_cards.clear()

	# Disable interactions for new set cards
	for card in _set_cards:
		card.z_index = SET_Z_INDEX
		var card_interaction = card.get_node_or_null("Interaction")
		if card_interaction:
			card_interaction.is_player_card = false

	# Rearrange (set cards are now in final position)
	_arrange_cards()


func _get_set_position(index: int) -> Vector2:
	"""Calculate the position for a set card at the given index"""
	if _set_cards.size() == 0 and _atk_cards.size() == 0:
		return Vector2.ZERO

	# Use the count from atk cards (they're about to become set cards)
	var card_count = _atk_cards.size()
	var total_width = (card_count - 1) * CARD_SPACING
	var start_x = -total_width / 2.0

	var x = start_x + (index * CARD_SPACING)
	return Vector2(x, 0)


func reset_to_placeholder() -> void:
	"""Reset the play zone to show only a face-down placeholder card"""
	# Keep one set card and flip it face-down, delete the rest
	if _set_cards.size() > 0:
		# Keep the first card as placeholder
		var placeholder = _set_cards[0]

		# Delete all other set cards
		for i in range(1, _set_cards.size()):
			_set_cards[i].queue_free()

		# Clear array and keep only the placeholder
		_set_cards.clear()
		_set_cards.append(placeholder)

		# Flip it to face-down
		if placeholder.has_method("set_show_back"):
			placeholder.set_show_back(true)

		# Position in center
		placeholder.position = Vector2(0, 0)
		placeholder.z_index = SET_Z_INDEX

		# Ensure interactions are disabled
		var card_interaction = placeholder.get_node_or_null("Interaction")
		if card_interaction:
			card_interaction.is_player_card = false

	# Clear atk cards (shouldn't have any, but just in case)
	_atk_cards.clear()


func shake_atk_cards() -> void:
	"""Applies a shaking animation to all cards currently in the attack zone."""
	var shake_strength = 10 # Pixels
	var shake_duration = 0.05 # Seconds per shake segment
	var num_shakes = 3 # Number of back-and-forth shakes

	for card in _atk_cards:
		var original_pos = card.position
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_ease(Tween.EASE_IN_OUT)

		for i in range(num_shakes):
			var target_pos_x = original_pos.x + (randf_range(-1.0, 1.0) * shake_strength)
			var target_pos_y = original_pos.y + (randf_range(-1.0, 1.0) * shake_strength)
			tween.tween_property(card, "position", Vector2(target_pos_x, target_pos_y), shake_duration)
		
		# Return to original position
		tween.tween_property(card, "position", original_pos, shake_duration)
