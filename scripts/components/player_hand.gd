@tool
extends Node2D
## PlayerHand - Interactive card hand management for the human player
##
## This component manages the player's hand of cards with sophisticated drag-and-drop
## functionality, visual preview animations, and automatic card arrangement. It handles
## all interactions between the player and their cards, including:
##
## - Card selection and reordering via drag-and-drop
## - Live preview animations that "part the sea" to show insertion points
## - Bounds checking to detect when cards are played (dragged outside hand)
## - Auto-sort toggle that preserves visual order when disabled
## - Editor preview mode for layout visualization
##
## The hand uses a "midpoint detection" algorithm for insertion index calculation,
## which creates intuitive drop zones that match visual card boundaries rather than
## just comparing against card centers. This makes reordering feel natural and responsive.
##
## Integration: Works closely with GameScreen for card lifecycle management and
## PlayZone for card movement between hand and play area.

# ============================================================================
# SIGNALS
# ============================================================================

## Emitted when a card is dragged or clicked out of the hand bounds
## GameScreen listens to this to move cards from hand to PlayZone
signal card_dragged_out(card_visual: Node)

## Emitted when any card drag starts (whether staying in hand or going to PlayZone)
## Used by GameScreen to coordinate drag state across components
signal card_drag_started(card_visual: Node)

## Emitted when the player manually reorders cards (disables auto-sort)
## Tells GameScreen that the player prefers their custom arrangement
signal auto_sort_disabled

# ============================================================================
# EXPORTS - Tunable Parameters
# ============================================================================

## Interval between drag preview updates (lower = smoother but more CPU intensive)
## At 0.05s (20fps), provides smooth visual feedback without excessive processing
@export var preview_update_interval: float = 0.05

# ============================================================================
# CONSTANTS
# ============================================================================

## Base z-index for hand cards - must be above PlayZone cards (which use z-index 1-10)
## Cards within hand get incremented z-indices (HAND_Z_INDEX_BASE + position)
const HAND_Z_INDEX_BASE: int = 20

# ============================================================================
# STATE VARIABLES
# ============================================================================

## Internal array tracking which cards are currently in the hand
## Cards are removed from this array when dragged to PlayZone
var _cards_in_hand: Array[Node] = []

## Flag indicating this component handles bounds checking (for GameScreen coordination)
var handles_bounds_checking: bool = true

## Currently dragged card reference (null when no drag in progress)
var _dragged_card: Node = null

## Preview insertion index (-1 when no preview active)
## This is where the dragged card will be inserted if dropped at current position
var _preview_insert_index: int = -1

## Active tween for preview animations (null when no animation running)
var _preview_tween: Tween = null

## Timestamp of last preview update (for throttling updates)
var _last_preview_update: float = 0.0

## Whether auto-sort is enabled (disabled when player manually reorders cards)
var auto_sort_enabled: bool = true

# ============================================================================
# LIFECYCLE METHODS
# ============================================================================

func _ready() -> void:
	if Engine.is_editor_hint():
		# MODE 1: EDITOR PREVIEW
		# Creates a visual preview with 13 sample cards for layout testing
		# Cards are visible but not truly interactive (just for design/layout work)
		_setup_editor_preview()
	else:
		# MODE 2: RUNTIME
		# Part of the actual game - clear any preview cards from the scene file
		# Real cards will be added later during the dealing phase
		for child in get_children():
			child.queue_free()

	# Set up drag monitoring for runtime (not needed in editor)
	if not Engine.is_editor_hint():
		_setup_drag_listeners()

func _exit_tree() -> void:
	## Clean up all resources when PlayerHand is freed
	# Disconnect all card drag listeners to prevent memory leaks
	for card in _cards_in_hand:
		var interaction = card.get_node_or_null("Interaction")
		if interaction:
			if interaction.has_signal("drag_ended") and interaction.drag_ended.is_connected(_on_card_drag_ended):
				interaction.drag_ended.disconnect(_on_card_drag_ended)
			if interaction.has_signal("card_clicked") and interaction.card_clicked.is_connected(_on_card_clicked):
				interaction.card_clicked.disconnect(_on_card_clicked)
			if interaction.has_signal("drag_started") and interaction.drag_started.is_connected(_on_card_drag_started):
				interaction.drag_started.disconnect(_on_card_drag_started)
			if interaction.has_signal("drag_position_updated") and interaction.drag_position_updated.is_connected(_on_card_drag_position_updated):
				interaction.drag_position_updated.disconnect(_on_card_drag_position_updated)

	# Kill any active preview tween
	if _preview_tween:
		_preview_tween.kill()
		_preview_tween = null

	# Clear internal state
	_cards_in_hand.clear()
	_dragged_card = null
	_preview_insert_index = -1

# ============================================================================
# PUBLIC API - Card Management
# ============================================================================

func add_card(card_data: Card) -> Node:
	## Add a single card to the hand (used during dealing phase)
	##
	## Creates a new card visual from the CardPool, configures it for player interaction,
	## and adds it to the hand. The card will be arranged in the next available position.
	##
	## @param card_data: Card data (rank and suit) for the new card
	## @return: The created card visual node
	var card_visual = CardPool.get_card()
	add_child(card_visual)

	# Set the card data
	if card_visual.has_method("set_card"):
		card_visual.set_card(card_data)

	# Set up interaction component for player control
	var interaction = card_visual.get_node_or_null("Interaction")
	if interaction:
		# Verify this is actually a CardInteraction node before setting properties
		if interaction.get_script() and str(interaction.get_script().resource_path).ends_with("card_interaction.gd"):
			interaction.is_player_card = true
		# Update base position for hover animations
		if interaction.has_method("update_base_position"):
			interaction.update_base_position()

	# Hide shadows (hands don't use shadows, only PlayZone cards do)
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
	## Remove all child cards and populate with new Card data (used at game start)
	##
	## This is a full reset operation - all existing cards are destroyed and replaced
	## with a fresh set based on the provided card data array.
	##
	## @param cards: Array of Card data to populate the hand with

	# Remove all existing card nodes
	for card in get_children():
		card.queue_free()

	_cards_in_hand.clear()

	# Create new CardVisual nodes for each card data
	for idx in range(cards.size()):
		var card_data = cards[idx]
		var card_visual = CardPool.get_card()
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

func update_visual_cards_after_play(new_logical_cards: Array[Card]) -> void:
	## Updates the visual cards in the hand after a play, without re-sorting the visual order.
	##
	## This is crucial for preserving the player's custom card arrangement when auto-sort
	## is disabled. It removes played cards and adds any new cards, but maintains the
	## relative order of unplayed cards exactly as the player arranged them.
	##
	## Algorithm:
	## 1. Build list of current logical cards from visual nodes
	## 2. Remove visual cards that are no longer in new_logical_cards (these were played)
	## 3. Add visual cards for new logical cards that weren't in the hand before
	## 4. Maintain original positions for cards that remain
	##
	## @param new_logical_cards: The updated array of Card data after the play
	var current_logical_cards: Array[Card] = []

	# Build a list of current logical cards from visual nodes
	for card_visual in _cards_in_hand:
		if card_visual.has_method("get_card"):
			current_logical_cards.append(card_visual.get_card())

	# Identify visual cards to remove (those no longer in new_logical_cards)
	for i in range(_cards_in_hand.size() - 1, -1, -1): # Iterate backwards to safely remove
		var card_visual = _cards_in_hand[i]
		if card_visual.has_method("get_card"):
			var logical_card = card_visual.get_card()
			var found = false
			for new_card in new_logical_cards:
				if new_card.equals(logical_card):
					found = true
					break
			if not found:
				_cards_in_hand.remove_at(i)
				card_visual.queue_free()
		else: # If card_visual doesn't have get_card, remove it as it's likely an invalid state
			_cards_in_hand.remove_at(i)
			card_visual.queue_free()

	# Identify logical cards to add (those in new_logical_cards but not in current visual hand)
	for new_card_data in new_logical_cards:
		var found_visual = false
		for card_visual in _cards_in_hand:
			if card_visual.has_method("get_card") and card_visual.get_card().equals(new_card_data):
				found_visual = true
				break
		if not found_visual:
			# Create new visual card and add it
			var card_visual = CardPool.get_card()
			add_child(card_visual)
			if card_visual.has_method("set_card"):
				card_visual.set_card(new_card_data)

			var interaction = card_visual.get_node_or_null("Interaction")
			if interaction:
				if interaction.get_script() and str(interaction.get_script().resource_path).ends_with("card_interaction.gd"):
					interaction.is_player_card = true
				if interaction.has_method("update_base_position"):
					interaction.update_base_position()

			if card_visual.has_method("set_shadow_visible"):
				card_visual.set_shadow_visible(false)

			_cards_in_hand.append(card_visual) # Append for now, arrangement will handle position
			_connect_card_drag_listener(card_visual)

	# Update z indices and arrange
	_update_z_indices()
	_arrange_cards()

func set_cards_interactive(interactive: bool) -> void:
	## Enable or disable interaction for all cards in hand
	##
	## Used to prevent player actions during CPU turns or when waiting for
	## game state transitions. When disabled, also cleans up any active drag state.
	##
	## @param interactive: Whether cards should respond to clicks and drags
	for card_visual in _cards_in_hand:
		var interaction = card_visual.get_node_or_null("Interaction")
		if interaction:
			interaction.set_interactive(interactive, interactive)

	# Also update drag state if interactions are disabled
	if not interactive:
		_dragged_card = null
		if _preview_tween:
			_preview_tween.kill()
			_preview_tween = null
		_preview_insert_index = -1
		_arrange_cards() # Re-arrange to remove any preview gaps

func clear_all_cards() -> void:
	## Removes all cards from the player's hand and resets internal state.
	##
	## This is a complete cleanup operation - typically used when starting a new game
	## or when the round ends. All cards are freed and internal tracking is reset.
	for card in _cards_in_hand:
		card.queue_free()
	_cards_in_hand.clear()
	_dragged_card = null
	_preview_insert_index = -1
	if _preview_tween:
		_preview_tween.kill()
		_preview_tween = null

func has_card(card_visual: Node) -> bool:
	## Checks if the given visual card is currently in this hand.
	##
	## @param card_visual: The card node to check for
	## @return: True if the card is in the hand, false otherwise
	return card_visual in _cards_in_hand

func get_cards() -> Array[Node]:
	## Returns the array of visual card nodes currently in the hand.
	##
	## @return: Array of card visual nodes (in current display order)
	return _cards_in_hand

# ============================================================================
# DRAG PREVIEW SYSTEM - "Parting the Sea" Animation
# ============================================================================
# This system creates a live preview of where a dragged card will be inserted.
# As the player drags a card over the hand, other cards smoothly animate apart
# to create a gap, showing exactly where the card will land if dropped.
# ============================================================================

func _on_card_drag_position_updated(card: Node) -> void:
	## Throttled callback for drag position updates
	##
	## This is called frequently during drag, so we throttle it based on
	## preview_update_interval to prevent excessive processing.
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_preview_update < preview_update_interval:
		return
	_last_preview_update = now
	_update_drag_preview(card)

func _update_drag_preview(card: Node) -> void:
	## Update the preview of where the card will be inserted during drag
	##
	## This is the core of the "parts the sea" effect. It continuously monitors
	## the dragged card's position and updates the gap in the hand to show where
	## the card will be inserted if dropped at the current location.
	##
	## Behavior:
	## - When card is over the hand: creates/updates gap at insertion point
	## - When card leaves hand bounds: collapses the gap back to normal spacing
	##
	## @param card: The card being dragged

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
		# Calculate insertion index using midpoint-based overlap detection
		# This uses the same method as _calculate_insertion_index for consistency
		var preview_idx = _calculate_insertion_index(card)

		# Only update if the insertion index changed (prevents redundant animations)
		if preview_idx != _preview_insert_index:
			_preview_insert_index = preview_idx
			_animate_cards_to_preview(preview_idx)

func _animate_cards_to_preview(preview_index: int) -> void:
	## Animate cards to their preview positions with a gap for the dragged card
	##
	## The "parts the sea" effect: Creates a gap at the insertion point while
	## maintaining constant total hand width by adjusting all card positions.
	##
	## How it works:
	## 1. If preview_index is -1: collapse to normal spacing (card left bounds)
	## 2. Otherwise: calculate positions with HAND_PREVIEW_GAP at insertion point
	## 3. All cards are repositioned to maintain centered alignment
	## 4. Animation is smooth and responsive (0.15s duration)
	##
	## Visual example (preview_index = 2):
	##   Before: [A][B][C][D][E]
	##   After:  [A][B]  gap  [C][D][E]
	##                ↑ dragged card will land here
	##
	## @param preview_index: Index where the gap should appear (-1 to collapse gap)

	# Kill existing tween to prevent conflicts
	if _preview_tween:
		_preview_tween.kill()

	if preview_index < 0:
		# COLLAPSE MODE: Return to normal spacing (used when card leaves bounds)
		var card_count = _cards_in_hand.size()
		var total_width = (card_count - 1) * GameConstants.HAND_CARD_SPACING
		var start_x = -total_width / 2.0

		_preview_tween = create_tween()
		_preview_tween.set_trans(Tween.TRANS_QUAD)
		_preview_tween.set_ease(Tween.EASE_OUT)
		_preview_tween.set_parallel(true)

		for idx in range(card_count):
			var target_x = start_x + (idx * GameConstants.HAND_CARD_SPACING)
			_preview_tween.tween_property(_cards_in_hand[idx], "position:x", target_x, 0.15)
		return

	# PREVIEW MODE: "Parts the sea" spacing with gap at insertion point
	#
	# Algorithm:
	# 1. Calculate total width including the gap (HAND_PREVIEW_GAP vs HAND_CARD_SPACING)
	# 2. Cards before insertion point: normal spacing from start
	# 3. Cards at/after insertion point: normal spacing but shifted by extra gap amount
	# 4. Result: Gap appears exactly where dragged card will be inserted

	_preview_tween = create_tween()
	_preview_tween.set_trans(Tween.TRANS_QUAD)
	_preview_tween.set_ease(Tween.EASE_OUT)
	_preview_tween.set_parallel(true)

	var total_cards = _cards_in_hand.size()
	var current_card_offset_idx = 0

	# Calculate total width with the gap
	# The gap adds GameConstants.HAND_PREVIEW_GAP instead of GameConstants.HAND_CARD_SPACING
	var total_width_with_gap = (total_cards - 1) * GameConstants.HAND_CARD_SPACING + (GameConstants.HAND_PREVIEW_GAP - GameConstants.HAND_CARD_SPACING)
	var start_x_with_gap = -total_width_with_gap / 2.0

	for idx in range(total_cards):
		var target_x = start_x_with_gap + (current_card_offset_idx * GameConstants.HAND_CARD_SPACING)
		if idx == preview_index:
			# At the insertion point - add the extra spacing for the gap
			target_x += (GameConstants.HAND_PREVIEW_GAP - GameConstants.HAND_CARD_SPACING)

		_preview_tween.tween_property(_cards_in_hand[idx], "position:x", target_x, 0.15)
		current_card_offset_idx += 1

# ============================================================================
# CARD ARRANGEMENT AND ANIMATION
# ============================================================================

func _arrange_cards() -> void:
	## Arrange cards in a straight horizontal line, centered
	##
	## This is the base card layout algorithm. Cards are evenly spaced using
	## HAND_CARD_SPACING and centered around the hand's origin (position 0).
	##
	## Layout calculation:
	## - Total width = (card_count - 1) * spacing (gaps between cards)
	## - Start X = -total_width / 2 (to center the arrangement)
	## - Each card at: start_x + (index * spacing)
	if _cards_in_hand.size() == 0:
		return

	var card_count = _cards_in_hand.size()
	# Calculate total width and center offset
	var total_width = (card_count - 1) * GameConstants.HAND_CARD_SPACING
	var start_x = -total_width / 2.0

	for idx in range(card_count):
		var child = _cards_in_hand[idx]
		var x = start_x + (idx * GameConstants.HAND_CARD_SPACING)
		child.position = Vector2(x, 0)

		# Update base position for hover animation
		var interaction = child.get_node_or_null("Interaction")
		if interaction and interaction.has_method("update_base_position"):
			interaction.update_base_position()

func _update_z_indices() -> void:
	## Recalculate z_indices for all cards based on their position
	##
	## Cards get progressively higher z-indices from left to right, ensuring
	## proper overlap rendering (rightmost cards appear on top).
	for idx in range(_cards_in_hand.size()):
		_cards_in_hand[idx].z_index = HAND_Z_INDEX_BASE + idx

func _reorder_card_in_hand(card_visual: Node) -> void:
	## Reorder a card in the hand based on its current position
	##
	## This is called when a card is dragged within the hand and dropped.
	## It calculates the final insertion position and updates the card order.
	##
	## Why this disables auto-sort:
	## When a player manually reorders their cards, it shows they want a specific
	## arrangement (e.g., grouping pairs, organizing by suit). Auto-sort would
	## immediately undo this, so we disable it to respect the player's intent.
	##
	## @param card_visual: The card node to reorder

	# Disable auto-sort because player is manually organizing their hand
	auto_sort_disabled.emit()

	# Validate and remove from current position
	if card_visual not in _cards_in_hand:
		return

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
	## Add a card back to the hand based on its current position
	##
	## Used when a card is returned from PlayZone back to the hand.
	## The card is inserted at the sorted position to maintain card value order.
	##
	## Why this also disables auto-sort:
	## Even when adding a card back, we use the sorted insertion to maintain
	## consistency, but we still disable auto-sort to indicate the hand state
	## has been modified outside of normal auto-sort flow.
	##
	## @param card: The card node to add back

	auto_sort_disabled.emit()

	# Safety check: don't add if already in hand
	if card in _cards_in_hand:
		return

	# Calculate insertion position based on card value (maintains sorted order)
	var insert_pos = _find_sorted_insertion_index(card)

	# Insert at the sorted location
	_cards_in_hand.insert(insert_pos, card)

	# Connect drag listener for this card if not already connected
	_connect_card_drag_listener(card)

	# Update visual arrangement
	_update_z_indices()
	_arrange_cards()

# ============================================================================
# INSERTION INDEX CALCULATION - Midpoint Detection Algorithm
# ============================================================================
# This algorithm determines where a dragged card should be inserted based on
# its position. It uses "midpoint thresholds" between adjacent cards, which
# creates intuitive drop zones that trigger when the dragged card begins
# overlapping its neighbors - much more natural than center-based comparison.
# ============================================================================

func _calculate_insertion_index(card_visual: Node) -> int:
	## Calculate where a card should be inserted based on its current position
	##
	## MIDPOINT DETECTION ALGORITHM:
	## Instead of comparing the dragged card's position to card centers, we use
	## the midpoints between adjacent cards as threshold boundaries. This creates
	## "hit zones" that match visual card overlap rather than abstract distances.
	##
	## Visual example (cards at positions 0, 100, 200):
	##   Midpoints at: 50, 150
	##   Drop zones:
	##     x < 50   → insert at 0 (before first card)
	##     50-150   → insert at 1 (between first and second)
	##     150-250  → insert at 2 (between second and third)
	##     x > 150  → insert at 3 (after last card)
	##
	## This feels natural because the insertion point changes exactly when the
	## dragged card starts overlapping its neighbors.
	##
	## @param card_visual: The card node to calculate insertion index for
	## @return: Index where the card should be inserted (0 to _cards_in_hand.size())

	# Empty hand - insert at position 0
	if _cards_in_hand.size() == 0:
		return 0

	# Convert card's global position to local hand coordinates
	var card_local_x = card_visual.global_position.x - global_position.x

	# Single card case - simple left/right comparison
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

		# If dragged card is to the left of this midpoint, insert after current card
		if card_local_x < midpoint_x:
			# Special case: first card - check if dragged card is left of first midpoint
			if idx == 0:
				return 0
			return idx + 1

	# Card is to the right of all midpoints - insert at the end
	return _cards_in_hand.size()

func _find_sorted_insertion_index(new_card_visual: Node) -> int:
	## Finds the correct index to insert a card to maintain sorted order by card value
	##
	## Uses Card.compare_card_nodes_lt to compare card values (rank and suit).
	## This maintains the hand in ascending order: 3, 4, 5... J, Q, K, A, 2
	##
	## @param new_card_visual: The card node to find insertion position for
	## @return: Index where card should be inserted to maintain sort order
	for i in range(_cards_in_hand.size()):
		var existing_card_visual = _cards_in_hand[i]
		if Card.compare_card_nodes_lt(new_card_visual, existing_card_visual):
			return i
	return _cards_in_hand.size() # Insert at the end if it's the largest

# ============================================================================
# HELPERS
# ============================================================================

func _get_hand_bounds() -> Rect2:
	## Calculate the bounding rectangle of the hand with padding
	##
	## This defines the "hot zone" for the hand. Cards dragged outside this
	## rectangle are considered to be played (moved to PlayZone).
	##
	## Geometry:
	## - Width: Total hand width + 2 * HAND_BOUNDS_PADDING
	## - Height: Card height + 2 * HAND_BOUNDS_PADDING
	## - Position: Centered around hand origin
	##
	## Padding gives a small buffer zone so cards don't accidentally trigger
	## play detection from minor drag movements.
	##
	## @return: Rect2 defining the hand's bounds in local coordinates
	var card_width = Constants.CARD_WIDTH
	var card_height = Constants.CARD_HEIGHT

	if _cards_in_hand.size() == 0:
		return Rect2(Vector2.ZERO, Vector2(card_width, card_height))

	var card_count = _cards_in_hand.size()

	# Total width of the hand
	var total_width = (card_count - 1) * GameConstants.HAND_CARD_SPACING + card_width
	var half_width = total_width / 2.0

	# Create bounds rect centered at origin with padding
	var bounds = Rect2(
		Vector2(-half_width - GameConstants.HAND_BOUNDS_PADDING, -card_height / 2.0 - GameConstants.HAND_BOUNDS_PADDING),
		Vector2(total_width + GameConstants.HAND_BOUNDS_PADDING * 2, card_height + GameConstants.HAND_BOUNDS_PADDING * 2)
	)

	return bounds

func _get_card_description(card_visual: Node) -> String:
	## Get a human-readable description of a card for logging/debugging
	##
	## @param card_visual: The card visual node
	## @return: String description of the card (e.g., "7 of Hearts")
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

func _get_card_action_description(card_visual: Node, action_type: String) -> String:
	## Get formatted card description with action type for console logging
	##
	## @param card_visual: The card visual node
	## @param action_type: The type of action (e.g., "Clicked", "Dragged")
	## @return: Formatted string like "Clicked - 7 of Hearts"
	var card_description = _get_card_description(card_visual)
	return action_type + " - " + card_description

# ============================================================================
# SIGNAL HANDLERS - Drag Events
# ============================================================================

func _setup_drag_listeners():
	## Connect drag ended signals for all current cards
	##
	## This is called during _ready() to set up initial signal connections.
	## For cards added later (during dealing), connections are made in add_card().
	for card in _cards_in_hand:
		_connect_card_drag_listener(card)

func _connect_card_drag_listener(card: Node):
	## Connect all interaction signals for a single card
	##
	## Sets up listeners for:
	## - drag_started: Track which card is being dragged, remove from array temporarily
	## - drag_position_updated: Update preview animation during drag
	## - drag_ended: Finalize card position or detect play to PlayZone
	## - card_clicked: Handle click-to-play (shortcut for drag-to-PlayZone)
	##
	## @param card: The card node to connect signals for
	var interaction = card.get_node_or_null("Interaction")
	if interaction:
		# Disconnect first to avoid duplicate connections (safety measure)

		# Connect drag ended
		if interaction.has_signal("drag_ended"):
			if interaction.drag_ended.is_connected(_on_card_drag_ended):
				interaction.drag_ended.disconnect(_on_card_drag_ended)
			interaction.drag_ended.connect(_on_card_drag_ended)

		# Connect click
		if interaction.has_signal("card_clicked"):
			if interaction.card_clicked.is_connected(_on_card_clicked):
				interaction.card_clicked.disconnect(_on_card_clicked)
			interaction.card_clicked.connect(_on_card_clicked)

		# Connect drag started
		if interaction.has_signal("drag_started"):
			if interaction.drag_started.is_connected(_on_card_drag_started):
				interaction.drag_started.disconnect(_on_card_drag_started)
			interaction.drag_started.connect(_on_card_drag_started)

		# Connect drag position updated
		if interaction.has_signal("drag_position_updated"):
			if interaction.drag_position_updated.is_connected(_on_card_drag_position_updated):
				interaction.drag_position_updated.disconnect(_on_card_drag_position_updated)
			interaction.drag_position_updated.connect(_on_card_drag_position_updated)

func _on_card_drag_started(card_visual: Node):
	## Handle when a card drag starts
	##
	## Temporarily remove the card from the hand array so it doesn't interfere
	## with preview calculations. The card will be re-inserted when drag ends.
	##
	## @param card_visual: The card being dragged
	if card_visual in _cards_in_hand:
		_dragged_card = card_visual
		_cards_in_hand.erase(card_visual)

	# Forward card drag start to GameScreen
	card_drag_started.emit(card_visual)

func _on_card_drag_ended(card_visual: Node):
	## Handle when a card drag ends - determine if card stays in hand or goes to PlayZone
	##
	## This is the core decision point for card movement. Based on where the card
	## was dropped (inside or outside hand bounds), we either:
	## 1. Reorder it within the hand (inside bounds)
	## 2. Send it to PlayZone (outside bounds)
	##
	## The algorithm carefully handles temporary array removal (from drag_started)
	## and preview state to ensure cards always end up in the correct position.
	##
	## @param card_visual: The card that was dragged

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
			# CASE 1: Card was dragged OUTSIDE hand bounds
			# This means the player wants to play this card

			# First, ensure it's back in the array if it was removed during drag
			if was_dragged_card and not card_in_hand:
				if final_preview_index >= 0 and final_preview_index <= _cards_in_hand.size():
					_cards_in_hand.insert(final_preview_index, card_visual)
				else:
					_cards_in_hand.append(card_visual)
			_handle_card_dragged_out(card_visual)
		else:
			# CASE 2: Card was dragged WITHIN hand bounds
			# This means the player is reordering their hand

			if was_dragged_card and not card_in_hand:
				# Re-insert at the preview position first (temporary placement)
				if final_preview_index >= 0 and final_preview_index <= _cards_in_hand.size():
					_cards_in_hand.insert(final_preview_index, card_visual)
				else:
					_cards_in_hand.append(card_visual)

			# Now recalculate the final position based on actual card position
			# This ensures the card ends up in the correct spot after drag ends
			_reorder_card_in_hand(card_visual)
	else:
		# Card was not in hand (must be in PlayZone)
		# Do nothing here, as PlayZone handles drags for atk cards
		# This prevents double-processing of drag events
		pass

func _on_card_clicked(card_visual: Node):
	## Handle when a card in hand is clicked - shortcut for playing the card
	##
	## Clicking a card is equivalent to dragging it out of the hand. This provides
	## a quick way for players to play cards without needing to drag.
	##
	## @param card_visual: The card that was clicked
	if card_visual in _cards_in_hand:
		# Card is in hand, so send it to PlayZone (like dragging it out)
		_handle_card_dragged_out(card_visual)
	# else: Card is not in hand (probably in PlayZone already)
	# Do nothing here, as PlayZone handles clicks for atk cards

func _handle_card_dragged_out(card_visual: Node):
	## Emit signal that a card was dragged/clicked out of the hand
	##
	## GameScreen listens to this signal and handles the actual card movement
	## from hand to PlayZone, including all game logic validation.
	##
	## @param card_visual: The card being moved out of hand
	card_dragged_out.emit(card_visual)

# ============================================================================
# EDITOR PREVIEW
# ============================================================================

func _setup_editor_preview() -> void:
	## Create default 13 cards in editor for layout preview
	##
	## In the Godot editor, this creates a visual representation of a full hand
	## so developers can see how the layout looks and make adjustments to spacing,
	## positioning, etc. Cards cycle through all ranks and suits for variety.

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
		var card_visual = CardPool.get_card()
		add_child(card_visual)

		# Set the card data
		if card_visual.has_method("set_card"):
			card_visual.set_card(card_data)

		# Set up interaction - make them non-interactive in editor
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

		# Hide shadows by default (like runtime)
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
