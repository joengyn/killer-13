@tool
extends Node2D
class_name PlayerHand
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

## Emitted when a card is clicked in the hand
signal card_clicked(card_visual: Node)

## Emitted when any card drag starts (whether staying in hand or going to PlayZone)
## Used by GameScreen to coordinate drag state across components
signal card_drag_started(card_visual: Node)

## Emitted when the player manually reorders cards (disables auto-sort)
## Tells GameScreen that the player prefers their custom arrangement
signal auto_sort_disabled

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

## Whether auto-sort is enabled (disabled when player manually reorders cards)
var auto_sort_enabled: bool = true

## Reference to the CardDragHandler child node
var _card_drag_handler: CardDragHandler = null

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
			# Skip CardDragHandler if it already exists from scene
			if child is CardDragHandler:
				continue
			child.queue_free()

		# Set up CardDragHandler for runtime drag-and-drop
		_card_drag_handler = CardDragHandler.new()
		add_child(_card_drag_handler)

		# Connect CardDragHandler signals to PlayerHand signals for GameScreen coordination
		_card_drag_handler.card_dragged_out.connect(card_dragged_out.emit)
		_card_drag_handler.card_clicked.connect(card_clicked.emit)
		_card_drag_handler.card_drag_started.connect(card_drag_started.emit)
		_card_drag_handler.auto_sort_disabled.connect(auto_sort_disabled.emit)

func _exit_tree() -> void:
	## Clean up all resources when PlayerHand is freed
	# CardDragHandler child will handle its own cleanup
	# Just clear the internal card array
	_cards_in_hand.clear()

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
			interaction.set_interactive(false, false)
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

	# Remove all existing card nodes, but preserve CardDragHandler
	for child in get_children():
		# Skip CardDragHandler - it must persist throughout the game
		if child is CardDragHandler:
			continue
		child.queue_free()

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
				interaction.set_interactive(false, false)
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
					interaction.set_interactive(false, false)
				if interaction.has_method("update_base_position"):
					interaction.update_base_position()

			if card_visual.has_method("set_shadow_visible"):
				card_visual.set_shadow_visible(false)

			_cards_in_hand.append(card_visual) # Append for now, arrangement will handle position
			_connect_card_drag_listener(card_visual)

	# Update z indices and arrange
	_update_z_indices()
	_arrange_cards()

func set_cards_interactive(can_reorder: bool, can_play: bool) -> void:
	## Enable or disable interaction for all cards in hand
	##
	## Used to prevent player actions during CPU turns or when waiting for
	## game state transitions. When disabled, also cleans up any active drag state.
	##
	## @param can_reorder: Whether cards can be hovered and reordered.
	## @param can_play: Whether cards can be clicked or dragged out to be played.
	for card_visual in _cards_in_hand:
		var interaction = card_visual.get_node_or_null("Interaction")
		if interaction:
			interaction.set_interactive(can_reorder, can_play)

	# Also update drag state if interactions are disabled
	if not can_reorder:
		if _card_drag_handler:
			_card_drag_handler.reset_drag_state()
		_arrange_cards() # Re-arrange to remove any preview gaps

func clear_all_cards() -> void:
	## Removes all cards from the player's hand and resets internal state.
	##
	## This is a complete cleanup operation - typically used when starting a new game
	## or when the round ends. All cards are freed and internal tracking is reset.
	for card in _cards_in_hand:
		card.queue_free()
	_cards_in_hand.clear()

	# Reset drag state via CardDragHandler if it exists
	if _card_drag_handler:
		_card_drag_handler.reset_drag_state()

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

func get_hand_bounds() -> Rect2:
	## Public wrapper for hand bounds calculation (used by CardDragHandler)
	##
	## @return: Rect2 defining the hand's bounds in local coordinates
	return _get_hand_bounds()

func remove_card_visual(card_visual: Node) -> void:
	## Remove a card visual from the hand array (used by CardDragHandler during drag)
	##
	## @param card_visual: The card node to remove
	_cards_in_hand.erase(card_visual)

func insert_card_visual(card_visual: Node, index: int) -> void:
	## Insert a card visual at a specific index (used by CardDragHandler for reordering)
	##
	## @param card_visual: The card node to insert
	## @param index: The index where the card should be inserted
	if index >= 0 and index <= _cards_in_hand.size():
		_cards_in_hand.insert(index, card_visual)
	else:
		_cards_in_hand.append(card_visual)

func add_card_visual(card_visual: Node) -> void:
	## Add a card visual to the end of the hand (used by CardDragHandler)
	##
	## @param card_visual: The card node to add
	_cards_in_hand.append(card_visual)

func rearrange_cards_in_hand() -> void:
	## Recalculate positions and z-indices for all cards (used by CardDragHandler after reordering)
	##
	## This triggers the full arrangement pipeline: update z-indices, then arrange cards.
	_update_z_indices()
	_arrange_cards()

# ============================================================================
# CARD ARRANGEMENT AND ANIMATION
# ============================================================================
# Drag preview animations are now handled by CardDragHandler
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
	var card_width = GameConstants.CARD_WIDTH
	var card_height = GameConstants.CARD_HEIGHT

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
# SIGNAL LISTENERS - Card Drag Coordination
# ============================================================================

func _connect_card_drag_listener(card: Node):
	## Connect all interaction signals for a single card via CardDragHandler
	##
	## Delegates to CardDragHandler which manages all drag event handling:
	## - drag_started: Track which card is being dragged, remove from array temporarily
	## - drag_position_updated: Update preview animation during drag
	## - drag_ended: Finalize card position or detect play to PlayZone
	## - card_clicked: Handle click-to-play (shortcut for drag-to-PlayZone)
	##
	## @param card: The card node to connect signals for
	if _card_drag_handler:
		_card_drag_handler.connect_card_drag_listeners(card)

# ============================================================================
# EDITOR PREVIEW
# ============================================================================

func _setup_editor_preview() -> void:
	## Create default 13 cards in editor for layout preview
	##
	## In the Godot editor, this creates a visual representation of a full hand
	## so developers can see how the layout looks and make adjustments to spacing,
	## positioning, etc. Cards cycle through all ranks and suits for variety.

	# Clear any existing cards, but preserve CardDragHandler
	for child in get_children():
		# Skip CardDragHandler - it must persist throughout the game
		if child is CardDragHandler:
			continue
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
