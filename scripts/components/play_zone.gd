@tool
extends Node2D
## PlayZone - Manages cards that have been played/placed down

## Emitted when an atk card is clicked to return to hand
signal atk_card_clicked(card_visual: Node)

## Emitted when an atk card is dragged out of bounds to return to hand
signal atk_card_dragged_out(card_visual: Node)

## Emitted when an atk card drag starts
signal atk_card_drag_started(card_visual: Node)

## ============================================================================
## CONFIGURATION - Adjustable via Godot Inspector
## ============================================================================

## Position offset of attack cards relative to set cards
@export var atk_offset: Vector2 = Vector2(-40, -60)
## Z-index for attack cards (shown above set cards)
@export var atk_z_index: int = 10
## Z-index for set cards (shown below attack cards)
@export var set_z_index_value: int = 1

## Tracks which player's cards are currently in the attack zone
var _current_atk_player_idx: int = -1

## ============================================================================
## DERIVED VALUES
## ============================================================================

var CARD_WIDTH: float:
	get: return Constants.CARD_WIDTH
var CARD_HEIGHT: float:
	get: return Constants.CARD_HEIGHT
var CARD_GAP: float:
	get: return Constants.PLAY_ZONE_CARD_GAP
var MAX_ZONE_WIDTH: float:
	get: return Constants.PLAY_ZONE_MAX_WIDTH
var CARD_SPACING: float:
	get: return CARD_WIDTH + CARD_GAP


func _ready() -> void:
	if Engine.is_editor_hint():
		# MODE 1: EDITOR PREVIEW
		_setup_editor_preview()
	else:
		# Runtime mode - clear preview cards
		# Remove any preview cards that may exist in the scene file
		for child in get_children():
			child.queue_free()


func _get_atk_offset_for_player(player_idx: int) -> Vector2:
	"""Return the offset vector based on which player is attacking.

	Offsets are 60 pixels in each direction relative to player position:
	- Player 0 (Human/Bottom): offset DOWN (0, +60)
	- Player 1 (CPU Left): offset LEFT (-60, 0)
	- Player 2 (CPU Top): offset UP (0, -60)
	- Player 3 (CPU Right): offset RIGHT (+60, 0)
	"""
	match player_idx:
		0: return Vector2(0, 60)      # Human player: offset down
		1: return Vector2(-60, 0)     # CPU Left: offset left
		2: return Vector2(0, -60)     # CPU Top: offset up
		3: return Vector2(60, 0)      # CPU Right: offset right
		_: return Vector2(-40, -60)   # Fallback to original offset


## Create sample set and attack cards in editor for preview
func _setup_editor_preview() -> void:
	# Clear any existing cards
	for child in get_children():
		child.queue_free()

	# Create 2 set cards (showing last played set)
	var set_cards = []
	for i in range(2):
		var rank = (i + 3) % 13  # Start from 5 (FIVE)
		var suit = i % 4  # Spades, Hearts
		set_cards.append(Card.new(rank as Card.Rank, suit as Card.Suit))

	# Create 2 attack cards (showing cards being thrown)
	var atk_cards = []
	for i in range(2):
		var rank = (i + 6) % 13  # Start from 8 (EIGHT)
		var suit = (i + 1) % 4  # Hearts, Diamonds
		atk_cards.append(Card.new(rank as Card.Rank, suit as Card.Suit))

	# Add set cards
	for card_data in set_cards:
		var card_visual = CardPool.get_card()
		add_child(card_visual)
		card_visual.add_to_group("play_zone_set")

		if card_visual.has_method("set_card"):
			card_visual.set_card(card_data)

		# Set cards are not interactive in editor
		var interaction = card_visual.get_node_or_null("Interaction")
		if interaction:
			interaction.is_player_card = false

		# Hide shadows
		if card_visual.has_method("set_shadow_visible"):
			card_visual.set_shadow_visible(false)

		card_visual.z_index = set_z_index_value

	# Add attack cards
	_current_atk_player_idx = 0  # Simulate human player attacking
	for card_data in atk_cards:
		var card_visual = CardPool.get_card()
		add_child(card_visual)
		card_visual.add_to_group("play_zone_atk")

		if card_visual.has_method("set_card"):
			card_visual.set_card(card_data)

		# Attack cards are not interactive in editor
		var interaction = card_visual.get_node_or_null("Interaction")
		if interaction:
			interaction.is_player_card = false

		# Hide shadows
		if card_visual.has_method("set_shadow_visible"):
			card_visual.set_shadow_visible(false)

		card_visual.z_index = atk_z_index

	# Arrange all cards
	_arrange_cards()


func add_atk_card(card: Node, player_idx: int = -1) -> void:
	"""Add a card as an attack card to the play zone (floating above set cards)"""
	if card.is_in_group("play_zone_atk"):
		return  # Already in atk zone

	# Store the player index when adding the first attack card
	if get_atk_cards().is_empty() and player_idx >= 0:
		_current_atk_player_idx = player_idx

	# Reparent card to PlayZone (preserves global position automatically)
	card.reparent(self)

	# Reset rotation to ensure all cards entering play zone are unrotated
	card.rotation = 0.0

	# Enable player card interactions (hover, click, drag) for atk cards
	var card_interaction = card.get_node_or_null("Interaction")
	if card_interaction:
		card_interaction.is_player_card = true
		# Update base position for hover animations
		if card_interaction.has_method("update_base_position"):
			card_interaction.update_base_position()

		# Connect to the card's interaction signals to detect clicks/drags
		_connect_atk_card_signals(card)

	card.add_to_group("play_zone_atk")
	card.set_shadow_visible(true)
	card.z_index = atk_z_index

	_arrange_cards()


func remove_atk_card(card: Node, new_parent: Node) -> void:
	"""Remove an atk card and return it to its parent"""
	if card.is_in_group("play_zone_atk"):
		card.remove_from_group("play_zone_atk")

		# Disconnect card signals to prevent memory leaks
		_disconnect_atk_card_signals(card)

		# Reparent card back to original parent
		var old_global_pos = card.global_position
		remove_child(card)
		new_parent.add_child(card)
		card.global_position = old_global_pos

		_arrange_cards()


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


func _get_card_arrangement_params(card_list: Array[Node]) -> Dictionary:
	var card_count = card_list.size()
	var card_width = CARD_WIDTH

	var effective_card_spacing: float
	if card_count == 1:
		effective_card_spacing = 0.0
	else:
		var default_total_width = (card_count - 1) * CARD_SPACING + card_width
		if default_total_width > MAX_ZONE_WIDTH:
			effective_card_spacing = (MAX_ZONE_WIDTH - card_width) / (card_count - 1)
		else:
			effective_card_spacing = CARD_SPACING

	var total_width = (card_count - 1) * effective_card_spacing + card_width
	var start_x = -(total_width / 2.0) + (card_width / 2.0)

	return {
		"effective_card_spacing": effective_card_spacing,
		"total_width": total_width,
		"start_x": start_x
	}


func _arrange_set_cards() -> void:
	"""Arrange set cards in a straight horizontal line, centered with responsive spacing"""
	var set_cards = get_set_cards()
	if set_cards.is_empty():
		return

	var params = _get_card_arrangement_params(set_cards)
	var start_x = params.start_x
	var effective_card_spacing = params.effective_card_spacing

	for idx in range(set_cards.size()):
		var child = set_cards[idx]
		var x = start_x + (idx * effective_card_spacing)
		child.position = Vector2(x, 0)
		child.z_index = set_z_index_value


func _arrange_atk_cards() -> void:
	"""Arrange atk cards offset above the set cards with responsive spacing"""
	var atk_cards = get_atk_cards()
	if atk_cards.is_empty():
		return

	var params = _get_card_arrangement_params(atk_cards)
	var start_x = params.start_x
	var effective_card_spacing = params.effective_card_spacing

	# Get the offset for the current attacking player
	var current_offset = _get_atk_offset_for_player(_current_atk_player_idx)

	for idx in range(atk_cards.size()):
		var child = atk_cards[idx]
		var x = start_x + (idx * effective_card_spacing)
		# Position offset based on the attacking player
		child.position = Vector2(x, 0) + current_offset
		# z_index increases with index (later cards render on top)
		child.z_index = atk_z_index + idx

		# Update base position for hover animations
		var interaction = child.get_node_or_null("Interaction")
		if interaction and interaction.has_method("update_base_position"):
			interaction.update_base_position()

		# Reset hover state to prevent stale hover effects when z-indices change
		if interaction and interaction.has_method("reset_hover_state"):
			interaction.reset_hover_state()


func _get_bounds_rect() -> Rect2:
	"""Calculate the bounding rectangle of the play zone (includes both set and atk cards)"""
	# The play zone's width is defined by MAX_ZONE_WIDTH, centered around the PlayZone's origin.
	var zone_width = MAX_ZONE_WIDTH
	var half_zone_width = zone_width / 2.0

	# The height needs to accommodate both set cards (at y=0) and atk cards (offset based on attacking player)
	# Assuming set cards are centered vertically at y=0, their range is -CARD_HEIGHT/2 to CARD_HEIGHT/2
	# Atk cards are offset based on the current attacking player, so we need to account for all possible offsets
	var set_card_min_y = -CARD_HEIGHT / 2.0
	var set_card_max_y = CARD_HEIGHT / 2.0

	# Get the current atk offset based on attacking player
	var current_offset = _get_atk_offset_for_player(_current_atk_player_idx)
	var atk_card_min_y = current_offset.y - CARD_HEIGHT / 2.0
	var atk_card_max_y = current_offset.y + CARD_HEIGHT / 2.0

	var min_y = min(set_card_min_y, atk_card_min_y)
	var max_y = max(set_card_max_y, atk_card_max_y)
	var zone_height = max_y - min_y

	# Account for horizontal offsets as well
	var atk_card_min_x = current_offset.x - CARD_WIDTH / 2.0
	var atk_card_max_x = current_offset.x + CARD_WIDTH / 2.0
	var set_card_min_x = -CARD_WIDTH / 2.0
	var set_card_max_x = CARD_WIDTH / 2.0

	var min_x = min(set_card_min_x, atk_card_min_x)
	var max_x = max(set_card_max_x, atk_card_max_x)
	var _zone_width_adjusted = max_x - min_x

	# Create bounds rect centered at origin
	var bounds = Rect2(
		Vector2(-half_zone_width, min_y),
		Vector2(zone_width, zone_height)
	)

	return bounds


func get_atk_cards() -> Array[Node]:
	var cards: Array[Node] = []
	cards.assign(get_tree().get_nodes_in_group("play_zone_atk"))
	cards.sort_custom(Card.compare_card_nodes_lt)
	return cards

func get_set_cards() -> Array[Node]:
	"""Return an array of set cards"""
	var cards: Array[Node] = []
	cards.assign(get_tree().get_nodes_in_group("play_zone_set"))
	return get_tree().get_nodes_in_group("play_zone_set")


func has_atk_card(card_visual: Node) -> bool:
	"""Checks if the given visual card is currently in the attack zone."""
	return card_visual.is_in_group("play_zone_atk")


func clear_atk_cards() -> void:
	"""Clear all atk cards from the zone"""
	var atk_cards = get_atk_cards()
	for card in atk_cards:
		card.remove_from_group("play_zone_atk")
		card.queue_free()
	_current_atk_player_idx = -1
	_arrange_cards()


func set_set_cards(cards: Array[Node]) -> void:
	"""Set the current set cards on the table"""
	# Clear existing set cards
	for old_card in get_set_cards():
		old_card.remove_from_group("play_zone_set")
		old_card.queue_free()
	
	# Add new cards
	for card in cards:
		card.add_to_group("play_zone_set")
		card.z_index = set_z_index_value
		# Set cards are not interactive (can't be clicked/dragged)
		var card_interaction = card.get_node_or_null("Interaction")
		if card_interaction:
			card_interaction.is_player_card = false
	_arrange_cards()


func commit_atk_to_set() -> void:
	"""Commit atk cards to become new set cards (called when Play is pressed and validated)"""
	var atk_cards = get_atk_cards()
	if atk_cards.is_empty():
		return

	# Add 0.5s delay for CPU players before animating to set position
	if _current_atk_player_idx > 0:
		await get_tree().create_timer(0.5).timeout

	# Animate atk cards to set positions
	for i in range(atk_cards.size()):
		var atk_card = atk_cards[i]
		var target_pos = _get_set_position(i, atk_cards)

		# Create tween to animate position
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(atk_card, "position", target_pos, 0.3)

	# After animation completes, finalize the transition
	await get_tree().create_timer(0.35).timeout

	# Remove old set cards from scene
	for card in get_set_cards():
		card.remove_from_group("play_zone_set")
		card.queue_free()

	# Move atk cards to set cards group
	for card in atk_cards:
		card.remove_from_group("play_zone_atk")
		card.add_to_group("play_zone_set")
		card.z_index = set_z_index_value
		var card_interaction = card.get_node_or_null("Interaction")
		if card_interaction:
			card_interaction.is_player_card = false

	# Rearrange (set cards are now in final position)
	_arrange_cards()


func _get_set_position(index: int, card_list: Array[Node]) -> Vector2:
	"""Calculate the position for a set card at the given index"""
	if card_list.is_empty():
		return Vector2.ZERO

	var params = _get_card_arrangement_params(card_list)
	var start_x = params.start_x
	var effective_card_spacing = params.effective_card_spacing

	var x = start_x + (index * effective_card_spacing)
	return Vector2(x, 0)


func reset_to_placeholder() -> void:
	"""Reset the play zone to show only a face-down placeholder card"""
	var set_cards = get_set_cards()
	# Keep one set card and flip it face-down, delete the rest
	if set_cards.size() > 0:
		# Keep the first card as placeholder
		var placeholder = set_cards[0]

		# Delete all other set cards
		for i in range(1, set_cards.size()):
			var card_to_remove = set_cards[i]
			card_to_remove.remove_from_group("play_zone_set")
			card_to_remove.queue_free()

		# Flip it to face-down
		if placeholder.has_method("set_show_back"):
			placeholder.set_show_back(true)

		placeholder.z_index = set_z_index_value

		# Ensure interactions are disabled
		var card_interaction = placeholder.get_node_or_null("Interaction")
		if card_interaction:
			card_interaction.is_player_card = false
	
	# Clear atk cards
	for card in get_atk_cards():
		card.remove_from_group("play_zone_atk")
		card.queue_free()
	_current_atk_player_idx = -1

	_arrange_cards()


func shake_atk_cards() -> void:
	"""Applies a shaking animation to all cards currently in the attack zone."""
	var atk_cards = get_atk_cards()
	var shake_strength = 10 # Pixels
	var shake_duration = 0.05 # Seconds per shake segment
	var num_shakes = 3 # Number of back-and-forth shakes

	for card in atk_cards:
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

func set_cards_interactive(interactive: bool) -> void:
	for card_visual in get_atk_cards():
		var interaction = card_visual.get_node_or_null("Interaction")
		if interaction:
			# Atk cards should be fully interactive (reorderable and movable) when 'interactive' is true
			interaction.set_interactive(interactive, interactive)
	for card_visual in get_set_cards():
		var interaction = card_visual.get_node_or_null("Interaction")
		if interaction:
			# Set cards are never interactive for the player
			interaction.set_interactive(false, false)

func clear_all_cards() -> void:
	"""Removes all cards (set and attack) from the play zone."""
	for card in get_set_cards():
		card.remove_from_group("play_zone_set")
		card.queue_free()

	for card in get_atk_cards():
		card.remove_from_group("play_zone_atk")
		card.queue_free()
	_current_atk_player_idx = -1


func _exit_tree() -> void:
	"""Clean up all signal connections when PlayZone is freed"""
	# Disconnect all atk card signals
	for card in get_atk_cards():
		_disconnect_atk_card_signals(card)
