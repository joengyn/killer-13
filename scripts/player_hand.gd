@tool
extends Node2D
## PlayerHand - Manages the player's hand of cards

## Emitted when a card is dragged out of the hand bounds
signal card_dragged_out(card_visual: Node)

## Emitted when a card drag starts
signal card_drag_started(card_visual: Node)

const CARD_SPACING: float = 115.0  # Horizontal spacing between cards
const PREVIEW_CARD_SPACING: float = 195.0  # Larger spacing for preview gap during drag
const THRESHOLD_PADDING: float = 20.0  # Extra padding around hand bounds for threshold
const HAND_Z_INDEX_BASE: int = 20  # Base z-index for hand cards (above PlayZone cards)

var _cards_in_hand: Array[Node] = []  # Track which cards are still in the hand

# Flag to indicate that this PlayerHand version handles bounds checking
var handles_bounds_checking: bool = true

# Drag preview state tracking
var _dragged_card: Node = null
var _preview_insert_index: int = -1
var _preview_tween: Tween = null


func _ready() -> void:
	if Engine.is_editor_hint():
		# MODE 1: EDITOR PREVIEW
		# Visual preview only - cards visible but not truly interactive (just for layout)
		_setup_editor_preview()
	else:
		# Runtime mode - full game
		# Part of larger game - clear preview cards, wait for game to populate real cards
		for child in get_children():
			child.queue_free()

	# Set up drag monitoring if we're not in editor mode
	if not Engine.is_editor_hint():
		# Connect to card drag events to detect when cards are dragged out of bounds
		_setup_drag_listeners()


func _setup_drag_listeners():
	# Connect drag ended signals for all current cards
	for card in _cards_in_hand:
		_connect_card_drag_listener(card)

	# Note: For cards added later, we need to ensure they also get connected
	# This is handled in the methods that add cards


func _connect_card_drag_listener(card: Node):
	var interaction = card.get_node_or_null("Interaction")
	if interaction:
		# Connect drag signals
		if interaction.has_signal("drag_ended"):
			# Disconnect first to avoid duplicate connections
			if interaction.drag_ended.is_connected(_on_card_drag_ended):
				interaction.drag_ended.disconnect(_on_card_drag_ended)
			interaction.drag_ended.connect(_on_card_drag_ended)

		# Connect click signals
		if interaction.has_signal("card_clicked"):
			# Disconnect first to avoid duplicate connections
			if interaction.card_clicked.is_connected(_on_card_clicked):
				interaction.card_clicked.disconnect(_on_card_clicked)
			interaction.card_clicked.connect(_on_card_clicked)

		# Connect drag started signals
		if interaction.has_signal("drag_started"):
			# Disconnect first to avoid duplicate connections
			if interaction.drag_started.is_connected(_on_card_drag_started):
				interaction.drag_started.disconnect(_on_card_drag_started)
			interaction.drag_started.connect(_on_card_drag_started)

		# Connect drag position updated signals
		if interaction.has_signal("drag_position_updated"):
			# Disconnect first to avoid duplicate connections
			if interaction.drag_position_updated.is_connected(_on_card_drag_position_updated):
				interaction.drag_position_updated.disconnect(_on_card_drag_position_updated)
			interaction.drag_position_updated.connect(_on_card_drag_position_updated)


func _on_card_drag_ended(card_visual: Node):
	# Reset drag preview state
	if _preview_tween:
		_preview_tween.kill()
		_preview_tween = null

	var was_dragged_card = (_dragged_card == card_visual)
	_dragged_card = null
	var final_preview_index = _preview_insert_index
	_preview_insert_index = -1

	# Check if this card (which was in the hand) was dragged outside hand bounds
	# Need to check if card was temporarily removed from array during drag
	var card_in_hand = card_visual in _cards_in_hand
	if card_in_hand or was_dragged_card:
		var card_local_pos = card_visual.global_position - global_position
		var hand_bounds = _get_hand_bounds()

		if not hand_bounds.has_point(card_local_pos):
			# Card was in hand and is now outside hand bounds - handle drag-out
			# First, ensure it's back in the array if it was removed during drag
			if was_dragged_card and not card_in_hand:
				if final_preview_index >= 0 and final_preview_index <= _cards_in_hand.size():
					_cards_in_hand.insert(final_preview_index, card_visual)
				else:
					_cards_in_hand.append(card_visual)
			_handle_card_dragged_out(card_visual)
		else:
			# Card ended drag within hand bounds - recalculate final position and finalize
			# Log for debugging z-index issue
			# print("Dragging %s within hand bounds, will reorder" % _get_card_description(card_visual))

			if was_dragged_card and not card_in_hand:
				# Re-insert at the preview position first (temporary placement)
				if final_preview_index >= 0 and final_preview_index <= _cards_in_hand.size():
					_cards_in_hand.insert(final_preview_index, card_visual)
				else:
					_cards_in_hand.append(card_visual)

			# Now recalculate the final position based on actual card position (not preview midpoints)
			# This ensures the card ends up in the correct spot after drag ends
			_reorder_card_in_hand(card_visual)
	else:
		# Card was not in hand (must be in play zone)
		# Do nothing here, as PlayZone handles drags for atk cards
		# This prevents double-processing of drag events
		pass


func _on_card_clicked(card_visual: Node):
	# Clicking a card in hand sends it to play zone
	if card_visual in _cards_in_hand:
		# Card is in hand, so send it to play zone (like dragging it out)
		# This emits the card_dragged_out signal, which GameScreen handles
		_handle_card_dragged_out(card_visual)
	# else: Card is not in hand (probably in play zone)
	# Do nothing here, as PlayZone handles clicks for atk cards
	# This prevents double-processing of click events


func _on_card_drag_started(card_visual: Node):
	# Store the dragged card and temporarily remove from hand array
	if card_visual in _cards_in_hand:
		_dragged_card = card_visual
		_cards_in_hand.erase(card_visual)

	# Forward card drag start to GameScreen
	card_drag_started.emit(card_visual)


func _handle_card_dragged_out(card_visual: Node):
	# Emit signal that a card was dragged out
	# GameScreen handles the card movement and hand adjustment
	card_dragged_out.emit(card_visual)




## Get a human-readable description of a card
## @param card_visual: The card visual node
## @return: String description of the card (rank and suit)
func _get_card_description(card_visual: Node) -> String:
	if card_visual.has_method("get_card"):
		var card_data = card_visual.get_card()
		if card_data and card_data.has_method("to_string"):
			return card_data.to_string()
		elif card_data:
			# Try to get rank and suit manually if to_string doesn't exist
			var rank_str = "Unknown"
			if card_data.rank != null:
				rank_str = str(card_data.rank)
			var suit_str = "Unknown"
			if card_data.suit != null:
				suit_str = str(card_data.suit)
			return rank_str + " of " + suit_str
	var card_name = "Unknown"
	if card_visual.name != "":
		card_name = card_visual.name
	return card_name


## Get card description for console logging with action type
## @param card_visual: The card visual node
## @param action_type: The type of action ("Clicked" or "Dragged")
## @return: Formatted string with card and action
func _get_card_action_description(card_visual: Node, action_type: String) -> String:
	var card_description = _get_card_description(card_visual)
	return action_type + " - " + card_description


## Create default 13 cards in editor for preview
func _setup_editor_preview() -> void:
	# Clear any existing cards
	for child in get_children():
		child.queue_free()

	_cards_in_hand.clear()

	# Create 13 default cards for editor preview (ranks 3 through 2 in different suits)
	var default_cards = []
	for i in range(13):
		var rank = i % 13  # 0-12 (THREE to TWO)
		var suit = int(i / 4.0) % 4  # 0-3 (SPADES to HEARTS) - cycling through suits
		default_cards.append(Card.new(rank as Card.Rank, suit as Card.Suit))

	# Populate the hand with default cards
	for idx in range(default_cards.size()):
		var card_data = default_cards[idx]
		var card_visual = preload("res://scenes/card.tscn").instantiate() as Node
		add_child(card_visual)

		# Set the card data
		if card_visual.has_method("set_card"):
			card_visual.set_card(card_data)

		# Set up interaction - make them interactive based on mode
		var interaction = card_visual.get_node_or_null("Interaction")
		if interaction:
			# Verify this is actually a CardInteraction node before setting properties
			if interaction.get_script() and str(interaction.get_script().resource_path).ends_with("card_interaction.gd"):
				if Engine.is_editor_hint():
					# In editor: cards visible but not truly interactive (just for layout)
					interaction.is_player_card = false
				else:
					# In runtime: make them interactive
					interaction.is_player_card = true
			# Update base position for hover animations
			if interaction.has_method("update_base_position"):
				interaction.update_base_position()

		# Hide shadows by default in editor (like runtime)
		if card_visual.has_method("set_shadow_visible"):
			card_visual.set_shadow_visible(false)

		# Track the card
		_cards_in_hand.append(card_visual)

		# Connect drag listener for this card (only in runtime, not in editor)
		if not Engine.is_editor_hint():
			_connect_card_drag_listener(card_visual)

	# Update z indices and arrange
	_update_z_indices()
	_arrange_cards()


func _arrange_cards() -> void:
	"""Arrange cards in a straight horizontal line, centered (only in-hand cards)"""
	if _cards_in_hand.size() == 0:
		return

	var card_count = _cards_in_hand.size()
	# Calculate total width and center offset
	var total_width = (card_count - 1) * CARD_SPACING
	var start_x = -total_width / 2.0

	for idx in range(card_count):
		var child = _cards_in_hand[idx]
		var x = start_x + (idx * CARD_SPACING)
		child.position = Vector2(x, 0)

		# Update base position for hover animation
		var interaction = child.get_node_or_null("Interaction")
		if interaction and interaction.has_method("update_base_position"):
			interaction.update_base_position()




func _get_hand_bounds() -> Rect2:
	"""Calculate the bounding rectangle of the hand with padding"""
	var card_width = Constants.CARD_WIDTH
	var card_height = Constants.CARD_HEIGHT

	if _cards_in_hand.size() == 0:
		return Rect2(Vector2.ZERO, Vector2(card_width, card_height))

	var card_count = _cards_in_hand.size()

	# Total width of the hand
	var total_width = (card_count - 1) * CARD_SPACING + card_width
	var half_width = total_width / 2.0

	# Create bounds rect centered at origin with padding
	var bounds = Rect2(
		Vector2(-half_width - THRESHOLD_PADDING, -card_height / 2.0 - THRESHOLD_PADDING),
		Vector2(total_width + THRESHOLD_PADDING * 2, card_height + THRESHOLD_PADDING * 2)
	)

	return bounds


func _calculate_insertion_index(card_visual: Node) -> int:
	"""Calculate where a card should be inserted based on its current position

	Uses midpoints between adjacent cards to determine insertion point, which
	effectively detects when the dragged card begins overlapping adjacent cards.

	@param card_visual: The card node to calculate insertion index for
	@return: Index where the card should be inserted (0 to _cards_in_hand.size())
	"""
	# Empty hand - insert at position 0
	if _cards_in_hand.size() == 0:
		return 0

	# Convert card's global position to local hand coordinates
	var card_local_x = card_visual.global_position.x - global_position.x

	# Single card case
	if _cards_in_hand.size() == 1:
		var first_card_x = _cards_in_hand[0].position.x
		# If dragged card is left of first card's center, insert at 0, otherwise at 1
		if card_local_x < first_card_x:
			return 0
		else:
			return 1

	# Multiple cards - use midpoint thresholds between adjacent cards to detect overlap
	for idx in range(_cards_in_hand.size() - 1):
		var current_card_x = _cards_in_hand[idx].position.x
		var next_card_x = _cards_in_hand[idx + 1].position.x

		# Calculate midpoint between current and next card
		var midpoint_x = (current_card_x + next_card_x) / 2.0

		# If dragged card is to the left of this midpoint, insert after current card
		if card_local_x < midpoint_x:
			# Special case: first card - check if dragged card is left of first midpoint
			if idx == 0:
				return 0
			return idx + 1

	# Card is to the right of all midpoints - insert at the end
	return _cards_in_hand.size()

func _find_sorted_insertion_index(new_card_visual: Node) -> int:
	"""Finds the correct index to insert a new card visual to maintain sorted order by card value."""
	for i in range(_cards_in_hand.size()):
		var existing_card_visual = _cards_in_hand[i]
		if Card.compare_card_nodes_lt(new_card_visual, existing_card_visual):
			return i
	return _cards_in_hand.size() # Insert at the end if it's the largest


func _reorder_card_in_hand(card_visual: Node) -> void:
	"""Reorder a card in the hand based on its current position

	Takes a card that's being dragged within the hand and repositions it
	based on where it was dropped relative to other cards.

	@param card_visual: The card node to reorder
	"""
	# Validate and remove
	if card_visual not in _cards_in_hand:
		return


	# Remove from current position
	_cards_in_hand.erase(card_visual)

	# Calculate new position and insert
	var new_idx = _calculate_insertion_index(card_visual)
	_cards_in_hand.insert(new_idx, card_visual)

	# Reset card's interaction state (shadow, hover) FIRST before rearranging
	# This prevents any interaction-based z-index changes from interfering
	var interaction = card_visual.get_node_or_null("Interaction")
	if interaction:
		# Reset the dragging state in the interaction component immediately
		if interaction.has_method("reset_hover_state"):
			interaction.reset_hover_state()

	# Note: z_index is already reset in CardInteraction._end_drag()
	# Just recalculate final z-indices and positions for all cards
	_update_z_indices()
	_arrange_cards()



func _add_card_back(card: Node) -> void:
	"""Add a card back to the hand based on its current position"""
	# Safety check: don't add if already in hand
	if card in _cards_in_hand:
		return

	# Calculate insertion position based on card's current global position
	var insert_pos = _find_sorted_insertion_index(card)

	# Insert at the position-based location
	_cards_in_hand.insert(insert_pos, card)

	# Connect drag listener for this card if not already connected
	_connect_card_drag_listener(card)

	# Update visual arrangement
	_update_z_indices()
	_arrange_cards()


func _update_z_indices() -> void:
	"""Recalculate z_indices for remaining in-hand cards"""
	for idx in range(_cards_in_hand.size()):
		_cards_in_hand[idx].z_index = HAND_Z_INDEX_BASE + idx




func _on_card_drag_position_updated(card: Node) -> void:
	"""Called when a card's position is updated during drag"""
	if _dragged_card == card:
		_update_drag_preview(card)


func _calculate_preview_index(drag_x_position: float) -> int:
	"""Calculate where a dragged card should be inserted based on its x position

	Uses midpoint-based detection between adjacent cards to determine insertion thresholds.
	This creates intuitive "hit zones" that match visual card boundaries rather than
	just comparing against card centers.

	@param drag_x_position: The card's global x position
	@return: Index where the card should be inserted (0 to _cards_in_hand.size())
	"""
	# Empty hand - insert at position 0
	if _cards_in_hand.size() == 0:
		return 0

	# Convert card's global position to local hand coordinates
	var card_local_x = drag_x_position - global_position.x

	# Single card case - use midpoint logic
	if _cards_in_hand.size() == 1:
		var first_card_x = _cards_in_hand[0].position.x
		# If dragged card is left of first card's center, insert at 0, otherwise at 1
		if card_local_x < first_card_x:
			return 0
		else:
			return 1

	# Multiple cards - use midpoint thresholds between adjacent cards
	for idx in range(_cards_in_hand.size() - 1):
		var current_card_x = _cards_in_hand[idx].position.x
		var next_card_x = _cards_in_hand[idx + 1].position.x

		# Calculate midpoint between current and next card
		var midpoint_x = (current_card_x + next_card_x) / 2.0

		# Special case: first card - check if dragged card is left of first midpoint
		if idx == 0 and card_local_x < midpoint_x:
			return 0

		# If dragged card is between this midpoint and the next, insert after current card
		if card_local_x < midpoint_x:
			return idx + 1

	# Card is to the right of all midpoints - insert at the end
	return _cards_in_hand.size()


func _update_drag_preview(card: Node) -> void:
	"""Update the preview of where the card will be inserted during drag

	Finds which two cards the dragged card is covering and pushes them apart
	to create a gap. If the card moves outside hand bounds, the preview gap collapses.

	@param card: The card being dragged
	"""
	# Check if card is within hand bounds
	var card_local_pos = card.global_position - global_position
	var hand_bounds = _get_hand_bounds()
	var is_in_bounds = hand_bounds.has_point(card_local_pos)

	if not is_in_bounds:
		# Card is outside hand bounds - collapse preview gap if it exists
		if _preview_insert_index >= 0:
			_preview_insert_index = -1
			# Animate cards back to normal layout (no gap)
			_animate_cards_to_preview(-1)
	else:
		# Calculate insertion index using the same method as _calculate_insertion_index
		# This uses midpoints between adjacent cards for proper overlap detection
		var preview_idx = _calculate_insertion_index(card)

		# Only update if the insertion index changed
		if preview_idx != _preview_insert_index:
			_preview_insert_index = preview_idx
			_animate_cards_to_preview(preview_idx)


func _animate_cards_to_preview(preview_index: int) -> void:
	"""Animate cards to their preview positions with a gap for the dragged card

	The dragged card "parts the sea" - creates a gap at its insertion point while
	cards on both sides compress to maintain constant total hand width.
	If preview_index is -1, animates cards back to normal spacing (used when card leaves bounds).

	@param preview_index: Index where the gap should appear (-1 to collapse gap)
	"""
	# Kill existing tween to prevent conflicts
	if _preview_tween:
		_preview_tween.kill()

	if preview_index < 0:
		# Collapse mode: return to normal spacing
		var card_count = _cards_in_hand.size()
		var total_width = (card_count - 1) * CARD_SPACING
		var start_x = -total_width / 2.0

		_preview_tween = create_tween()
		_preview_tween.set_trans(Tween.TRANS_QUAD)
		_preview_tween.set_ease(Tween.EASE_OUT)
		_preview_tween.set_parallel(true)

		for idx in range(card_count):
			var target_x = start_x + (idx * CARD_SPACING)
			_preview_tween.tween_property(_cards_in_hand[idx], "position:x", target_x, 0.15)
		return

	# Preview mode: "parts the sea" spacing - systematic offset method with fixed endpoints
	# Cards at insertion point (preview_index-1 and preview_index) get the largest offset
	# But first and last cards stay fixed in position to prevent hand shifting

	_preview_tween = create_tween()
	_preview_tween.set_trans(Tween.TRANS_QUAD)
	_preview_tween.set_ease(Tween.EASE_OUT)
	_preview_tween.set_parallel(true)

	var total_cards = _cards_in_hand.size()
	var current_card_offset_idx = 0 # This will track the index for spacing calculation, accounting for the gap

	# Calculate total width with the gap
	# The gap adds PREVIEW_CARD_SPACING instead of CARD_SPACING at the insertion point
	var total_width_with_gap = (total_cards - 1) * CARD_SPACING + (PREVIEW_CARD_SPACING - CARD_SPACING)
	var start_x = -total_width_with_gap / 2.0

	for idx in range(total_cards):
		var target_x = start_x + (current_card_offset_idx * CARD_SPACING)
		if idx == preview_index:
			# If we are at the insertion point, add the extra spacing for the gap
			target_x += (PREVIEW_CARD_SPACING - CARD_SPACING)

		_preview_tween.tween_property(_cards_in_hand[idx], "position:x", target_x, 0.15)
		current_card_offset_idx += 1




func add_card(card_data: Card) -> Node:
	"""Add a single card to the hand (used during dealing). Returns the created card visual node."""
	var card_visual = preload("res://scenes/card.tscn").instantiate() as Node
	add_child(card_visual)

	# Set the card data
	if card_visual.has_method("set_card"):
		card_visual.set_card(card_data)

	# Set up interaction
	var interaction = card_visual.get_node_or_null("Interaction")
	if interaction:
		# Verify this is actually a CardInteraction node before setting properties
		if interaction.get_script() and str(interaction.get_script().resource_path).ends_with("card_interaction.gd"):
			interaction.is_player_card = true
		# Update base position for hover animations
		if interaction.has_method("update_base_position"):
			interaction.update_base_position()

	# Hide shadows
	if card_visual.has_method("set_shadow_visible"):
		card_visual.set_shadow_visible(false)

	# Track the card
	_cards_in_hand.append(card_visual)

	# Connect drag listener for this new card
	_connect_card_drag_listener(card_visual)

	# Update z indices and arrange
	_update_z_indices()
	_arrange_cards()

	return card_visual


func clear_and_populate(cards: Array[Card]) -> void:
	"""Remove all child cards and populate with new Card data (runtime use)"""
	# Remove all existing card nodes
	for card in get_children():
		card.queue_free()

	_cards_in_hand.clear()

	# Create new CardVisual nodes for each card data
	for idx in range(cards.size()):
		var card_data = cards[idx]
		var card_visual = preload("res://scenes/card.tscn").instantiate() as Node
		add_child(card_visual)

		# Set the card data
		if card_visual.has_method("set_card"):
			card_visual.set_card(card_data)

		# Set up interaction
		var interaction = card_visual.get_node_or_null("Interaction")
		if interaction:
			# Verify this is actually a CardInteraction node before setting properties
			if interaction.get_script() and str(interaction.get_script().resource_path).ends_with("card_interaction.gd"):
				interaction.is_player_card = true
			# Update base position for hover animations
			if interaction.has_method("update_base_position"):
				interaction.update_base_position()

		# Track the card
		_cards_in_hand.append(card_visual)

		# Connect drag listener for this card
		_connect_card_drag_listener(card_visual)

		# Hide shadows
		if card_visual.has_method("set_shadow_visible"):
			card_visual.set_shadow_visible(false)

	# Update z indices and arrange
	_update_z_indices()
	_arrange_cards()

func set_cards_interactive(interactive: bool) -> void:
	for card_visual in _cards_in_hand:
		var interaction = card_visual.get_node_or_null("Interaction")
		if interaction:
			interaction.set_interactive(true, interactive)
	# Also update drag state if interactions are disabled
	if not interactive:
		_dragged_card = null
		if _preview_tween:
			_preview_tween.kill()
			_preview_tween = null
		_preview_insert_index = -1
		_arrange_cards() # Re-arrange to remove any preview gaps


func clear_all_cards() -> void:
	"""Removes all cards from the player's hand and resets internal state."""
	for card in _cards_in_hand:
		card.queue_free()
	_cards_in_hand.clear()
	_dragged_card = null
	_preview_insert_index = -1
	if _preview_tween:
		_preview_tween.kill()
		_preview_tween = null

func has_card(card_visual: Node) -> bool:
	"""Checks if the given visual card is currently in this hand."""
	return card_visual in _cards_in_hand

func get_cards() -> Array[Node]:
	"""Returns the array of visual card nodes currently in the hand."""
	return _cards_in_hand
