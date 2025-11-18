@tool
extends Node2D
## PlayZone - Dual-zone card management for attack and set cards
##
## This component manages the central play area where cards are placed after being
## played from hands. It maintains two distinct zones with different behaviors:
##
## 1. SET ZONE (set_cards):
##    - Shows the current "set" on the table (the last valid play that was committed)
##    - Cards are non-interactive - players can't click or drag them
##    - Positioned at the center of the PlayZone (y=0)
##    - Only one set exists at a time (previous set is replaced when new plays commit)
##
## 2. ATTACK ZONE (atk_cards):
##    - Shows cards currently being assembled for a play (before validation)
##    - Cards are interactive - players can click/drag them back to hand
##    - Offset from set cards based on which player is attacking (dynamic positioning)
##    - Cleared when play is committed or passed
##
## The dual-zone system allows players to see both the current table state (set_cards)
## and their pending play (atk_cards) simultaneously, with visual separation making
## the distinction clear.
##
## Integration: Works with GameScreen for game logic, PlayerHand for card movement,
## and uses player-specific offsets for multi-player positioning.

# ============================================================================
# SIGNALS
# ============================================================================

## Emitted when an atk card is clicked to return it to hand
## GameScreen listens to move the card back to the player's hand
signal atk_card_clicked(card_visual: Node)

## Emitted when an atk card is dragged out of PlayZone bounds to return to hand
## Provides alternative to clicking for returning cards
signal atk_card_dragged_out(card_visual: Node)

## Emitted when an atk card drag starts
## Used by GameScreen to coordinate drag state
signal atk_card_drag_started(card_visual: Node)

# ============================================================================
# EXPORTS - Tunable Parameters
# ============================================================================

## Position offset of attack cards relative to set cards
## Default: (-40, -60) positions atk cards up and left of set cards
## This is overridden by player-specific offsets in _get_atk_offset_for_player()
@export var atk_offset: Vector2 = Vector2(-40, -60)

## Z-index for attack cards (shown above set cards for visual priority)
@export var atk_z_index: int = 10

## Z-index for set cards (shown below attack cards)
@export var set_z_index_value: int = 1

# ============================================================================
# STATE VARIABLES
# ============================================================================

## Tracks which player's cards are currently in the attack zone
## Used to determine offset direction (different for each player position)
## -1 when no attack cards present
var _current_atk_player_idx: int = -1

# ============================================================================
# DERIVED VALUES - Cached Constants
# ============================================================================

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

# ============================================================================
# LIFECYCLE METHODS
# ============================================================================

func _ready() -> void:
	if Engine.is_editor_hint():
		# MODE 1: EDITOR PREVIEW
		# Shows sample set and attack cards for layout visualization
		_setup_editor_preview()
	else:
		# MODE 2: RUNTIME
		# Clear preview cards - real cards will be added during gameplay
		for child in get_children():
			child.queue_free()

func _exit_tree() -> void:
	## Clean up all signal connections when PlayZone is freed
	# Disconnect all atk card signals to prevent memory leaks
	for card in get_atk_cards():
		_disconnect_atk_card_signals(card)

# ============================================================================
# PUBLIC API - Attack Zone Management
# ============================================================================

func add_atk_card(card: Node, player_idx: int = -1) -> void:
	## Add a card to the attack zone (cards being assembled for a play)
	##
	## Attack cards are interactive - players can click or drag them back to their hand.
	## The first attack card added determines the player offset for the entire attack group.
	##
	## @param card: The card visual node to add
	## @param player_idx: Which player owns this card (0=human, 1-3=CPU) - used for positioning

	if card.is_in_group("play_zone_atk"):
		return  # Already in atk zone - don't add twice

	# Store the player index when adding the first attack card
	# This determines the offset direction for the entire attack group
	if get_atk_cards().is_empty() and player_idx >= 0:
		_current_atk_player_idx = player_idx

	# Reparent card to PlayZone (Godot 4 automatically preserves global position)
	card.reparent(self)

	# Reset rotation to ensure all cards entering play zone are upright
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

	# Mark card as part of attack zone and enable shadow
	card.add_to_group("play_zone_atk")
	card.set_shadow_visible(true)
	card.z_index = atk_z_index

	# Rearrange all cards to accommodate the new attack card
	_arrange_cards()

func remove_atk_card(card: Node, new_parent: Node) -> void:
	## Remove an attack card and return it to its original parent (typically PlayerHand)
	##
	## This is used when a player drags/clicks an attack card back to their hand,
	## effectively "undoing" their card placement before committing the play.
	##
	## @param card: The card visual node to remove
	## @param new_parent: The parent node to reparent the card to (usually PlayerHand)

	if card.is_in_group("play_zone_atk"):
		card.remove_from_group("play_zone_atk")

		# Disconnect card signals to prevent memory leaks
		_disconnect_atk_card_signals(card)

		# Reparent card back to original parent, preserving global position
		var old_global_pos = card.global_position
		remove_child(card)
		new_parent.add_child(card)
		card.global_position = old_global_pos

		# Rearrange remaining cards
		_arrange_cards()

func clear_atk_cards() -> void:
	## Clear all attack cards from the zone (used when play is committed or passed)
	##
	## This completely removes all attack cards and resets the player index.
	## The attack zone becomes empty and ready for the next play.
	var atk_cards = get_atk_cards()
	for card in atk_cards:
		card.remove_from_group("play_zone_atk")
		card.queue_free()
	_current_atk_player_idx = -1
	_arrange_cards()

func get_atk_cards() -> Array[Node]:
	## Get all cards currently in the attack zone, sorted by card value
	##
	## @return: Array of card visual nodes in the attack zone, sorted lowest to highest
	var cards: Array[Node] = []
	cards.assign(get_tree().get_nodes_in_group("play_zone_atk"))
	cards.sort_custom(Card.compare_card_nodes_lt)
	return cards

func has_atk_card(card_visual: Node) -> bool:
	## Checks if the given visual card is currently in the attack zone
	##
	## @param card_visual: The card node to check
	## @return: True if card is in attack zone, false otherwise
	return card_visual.is_in_group("play_zone_atk")

# ============================================================================
# PUBLIC API - Set Zone Management
# ============================================================================

func set_set_cards(cards: Array[Node]) -> void:
	## Set the current set cards on the table (replaces any existing set)
	##
	## Set cards represent the last committed play. They are non-interactive
	## and serve as a reference point for what needs to be beaten.
	##
	## This method completely replaces the current set - the old set is freed.
	##
	## @param cards: Array of card visual nodes to become the new set

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

func get_set_cards() -> Array[Node]:
	## Get all cards currently in the set zone
	##
	## @return: Array of card visual nodes in the set zone
	var cards: Array[Node] = []
	cards.assign(get_tree().get_nodes_in_group("play_zone_set"))
	return get_tree().get_nodes_in_group("play_zone_set")

func commit_atk_to_set() -> void:
	## Commit attack cards to become the new set cards
	##
	## This is called when a play is validated and accepted. The attack cards
	## smoothly animate to the set position, then replace the old set.
	##
	## Animation sequence:
	## 1. Optional 0.5s delay for CPU players (gives visual feedback time)
	## 2. Animate atk cards to set positions (0.3s smooth transition)
	## 3. Wait for animation to complete
	## 4. Convert atk cards to set cards (change groups, disable interaction)
	## 5. Free old set cards

	var atk_cards = get_atk_cards()
	if atk_cards.is_empty():
		return

	# Add delay for CPU players to see their play before it commits
	if _current_atk_player_idx > 0:
		await get_tree().create_timer(0.5).timeout

	# Animate atk cards to set positions
	for i in range(atk_cards.size()):
		var atk_card = atk_cards[i]
		var target_pos = _get_set_position(i, atk_cards)

		# Create tween to animate position smoothly
		var tween = create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(atk_card, "position", target_pos, 0.3)

	# Wait for animation to complete (0.35s = 0.3s animation + 0.05s buffer)
	await get_tree().create_timer(0.35).timeout

	# Remove old set cards from scene
	for card in get_set_cards():
		card.remove_from_group("play_zone_set")
		card.queue_free()

	# Convert atk cards to set cards
	for card in atk_cards:
		card.remove_from_group("play_zone_atk")
		card.add_to_group("play_zone_set")
		card.z_index = set_z_index_value
		# Disable interaction - set cards can't be dragged/clicked
		var card_interaction = card.get_node_or_null("Interaction")
		if card_interaction:
			card_interaction.is_player_card = false

	# Rearrange (set cards are now in final position)
	_arrange_cards()

func reset_to_placeholder() -> void:
	## Reset the play zone to show only a face-down placeholder card
	##
	## Used at the start of a new round when there's no committed set yet.
	## The placeholder gives a visual reference point for the PlayZone without
	## representing an actual card that needs to be beaten.

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

		# Flip placeholder to face-down
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

func clear_all_cards() -> void:
	## Removes all cards (set and attack) from the play zone
	##
	## Complete reset operation - used when starting a new game.
	for card in get_set_cards():
		card.remove_from_group("play_zone_set")
		card.queue_free()

	for card in get_atk_cards():
		card.remove_from_group("play_zone_atk")
		card.queue_free()
	_current_atk_player_idx = -1

# ============================================================================
# PUBLIC API - Animation and Feedback
# ============================================================================

func shake_atk_cards() -> void:
	## Applies a shaking animation to all cards in the attack zone
	##
	## Used to provide visual feedback when a play is invalid.
	## The shake draws attention to the attack cards and indicates rejection.
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
	## Enable or disable interaction for all cards in the play zone
	##
	## When interactive is false: prevents player from clicking/dragging cards
	## Used during CPU turns or when waiting for game state transitions.
	##
	## Note: Set cards are ALWAYS non-interactive regardless of this setting.
	## Only attack cards can be made interactive.
	##
	## @param interactive: Whether attack cards should respond to input
	for card_visual in get_atk_cards():
		var interaction = card_visual.get_node_or_null("Interaction")
		if interaction:
			# Atk cards should be fully interactive (reorderable and movable) when enabled
			interaction.set_interactive(interactive, interactive)

	for card_visual in get_set_cards():
		var interaction = card_visual.get_node_or_null("Interaction")
		if interaction:
			# Set cards are NEVER interactive for the player
			interaction.set_interactive(false, false)

# ============================================================================
# ARRANGEMENT AND LAYOUT - Responsive Card Positioning
# ============================================================================

func _arrange_cards() -> void:
	## Arrange both set and attack cards in their respective positions
	##
	## This is the master arrangement function that delegates to zone-specific
	## arrangement methods. Called whenever cards are added, removed, or committed.
	_arrange_set_cards()
	_arrange_atk_cards()

func _arrange_set_cards() -> void:
	## Arrange set cards in a straight horizontal line, centered
	##
	## Set cards are always positioned at y=0 (center of PlayZone) with
	## responsive spacing that compresses if the set is too wide.
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
	## Arrange attack cards offset from set cards based on attacking player
	##
	## Attack cards use the same horizontal arrangement as set cards but are
	## offset in a direction determined by which player is attacking:
	## - Player 0 (Human/Bottom): offset DOWN
	## - Player 1 (CPU Left): offset LEFT
	## - Player 2 (CPU Top): offset UP
	## - Player 3 (CPU Right): offset RIGHT
	##
	## This creates visual separation and makes it clear which player is attacking.
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

func _get_card_arrangement_params(card_list: Array[Node]) -> Dictionary:
	## Calculate responsive spacing parameters for a list of cards
	##
	## This is the core layout algorithm that handles both normal and compressed spacing.
	##
	## Logic:
	## 1. If single card: no spacing needed
	## 2. Calculate total width with default spacing (CARD_SPACING)
	## 3. If total width exceeds MAX_ZONE_WIDTH: compress spacing proportionally
	## 4. Otherwise: use default spacing
	##
	## Result maintains centered alignment regardless of spacing compression.
	##
	## @param card_list: Array of cards to arrange
	## @return: Dictionary with keys: effective_card_spacing, total_width, start_x
	var card_count = card_list.size()
	var card_width = CARD_WIDTH

	var effective_card_spacing: float
	if card_count == 1:
		# Single card: no spacing needed
		effective_card_spacing = 0.0
	else:
		# Calculate default total width
		var default_total_width = (card_count - 1) * CARD_SPACING + card_width
		if default_total_width > MAX_ZONE_WIDTH:
			# Too wide - compress spacing to fit within MAX_ZONE_WIDTH
			effective_card_spacing = (MAX_ZONE_WIDTH - card_width) / (card_count - 1)
		else:
			# Fits comfortably - use default spacing
			effective_card_spacing = CARD_SPACING

	var total_width = (card_count - 1) * effective_card_spacing + card_width
	var start_x = -(total_width / 2.0) + (card_width / 2.0)

	return {
		"effective_card_spacing": effective_card_spacing,
		"total_width": total_width,
		"start_x": start_x
	}

func _get_set_position(index: int, card_list: Array[Node]) -> Vector2:
	## Calculate the position for a set card at the given index
	##
	## Used during commit_atk_to_set animation to determine target positions.
	##
	## @param index: Index of the card in the list
	## @param card_list: Array of cards to calculate position within
	## @return: Vector2 position for the card at the given index
	if card_list.is_empty():
		return Vector2.ZERO

	var params = _get_card_arrangement_params(card_list)
	var start_x = params.start_x
	var effective_card_spacing = params.effective_card_spacing

	var x = start_x + (index * effective_card_spacing)
	return Vector2(x, 0)

func _get_atk_offset_for_player(player_idx: int) -> Vector2:
	## Return the offset vector based on which player is attacking
	##
	## Player-specific offset system creates visual distinction for multi-player games.
	## Each player position gets a unique offset direction (60 pixels in cardinal directions).
	##
	## Offset directions:
	## - Player 0 (Human/Bottom): offset DOWN (0, +60) - cards appear below set
	## - Player 1 (CPU Left): offset LEFT (-60, 0) - cards appear to the left
	## - Player 2 (CPU Top): offset UP (0, -60) - cards appear above set
	## - Player 3 (CPU Right): offset RIGHT (+60, 0) - cards appear to the right
	##
	## This makes it immediately clear which player is making a play just by
	## looking at the attack card positions relative to the set.
	##
	## @param player_idx: Index of the attacking player (0-3)
	## @return: Vector2 offset to apply to attack cards
	match player_idx:
		0: return Vector2(0, 60)      # Human player: offset down
		1: return Vector2(-60, 0)     # CPU Left: offset left
		2: return Vector2(0, -60)     # CPU Top: offset up
		3: return Vector2(60, 0)      # CPU Right: offset right
		_: return Vector2(-40, -60)   # Fallback to original offset

# ============================================================================
# HELPERS - Geometry and Bounds
# ============================================================================

func _get_bounds_rect() -> Rect2:
	## Calculate the bounding rectangle of the play zone (includes both set and atk cards)
	##
	## This is used for bounds checking when dragging attack cards. Cards dragged
	## outside this rectangle are returned to the player's hand.
	##
	## Geometry calculation:
	## 1. Width: MAX_ZONE_WIDTH (fixed horizontal extent)
	## 2. Height: Encompasses both set cards (at y=0) and atk cards (offset by player)
	## 3. Accounts for card dimensions and player-specific offsets
	##
	## @return: Rect2 defining the PlayZone bounds in local coordinates

	# The play zone's width is defined by MAX_ZONE_WIDTH, centered around origin
	var zone_width = MAX_ZONE_WIDTH
	var half_zone_width = zone_width / 2.0

	# The height needs to accommodate both set cards (at y=0) and atk cards (offset)
	# Set cards are centered vertically at y=0, so range is -CARD_HEIGHT/2 to CARD_HEIGHT/2
	var set_card_min_y = -CARD_HEIGHT / 2.0
	var set_card_max_y = CARD_HEIGHT / 2.0

	# Get the current atk offset based on attacking player
	var current_offset = _get_atk_offset_for_player(_current_atk_player_idx)
	var atk_card_min_y = current_offset.y - CARD_HEIGHT / 2.0
	var atk_card_max_y = current_offset.y + CARD_HEIGHT / 2.0

	# Calculate overall vertical extent (min and max of both zones)
	var min_y = min(set_card_min_y, atk_card_min_y)
	var max_y = max(set_card_max_y, atk_card_max_y)
	var zone_height = max_y - min_y

	# Account for horizontal offsets as well (for left/right players)
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

# ============================================================================
# SIGNAL HANDLERS - Attack Card Interactions
# ============================================================================

func _connect_atk_card_signals(card: Node):
	## Connect interaction signals from an attack card
	##
	## Sets up listeners for click and drag events on attack cards.
	## These allow players to return cards to their hand before committing.
	##
	## @param card: The card node to connect signals for
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
	## Disconnect interaction signals from an attack card
	##
	## Called when removing cards to prevent memory leaks.
	##
	## @param card: The card node to disconnect signals from
	var interaction = card.get_node_or_null("Interaction")
	if interaction:
		if interaction.card_clicked.is_connected(_on_atk_card_clicked):
			interaction.card_clicked.disconnect(_on_atk_card_clicked)
		if interaction.drag_ended.is_connected(_on_atk_card_drag_ended):
			interaction.drag_ended.disconnect(_on_atk_card_drag_ended)
		if interaction.drag_started.is_connected(_on_atk_card_drag_started):
			interaction.drag_started.disconnect(_on_atk_card_drag_started)

func _on_atk_card_clicked(card: Node):
	## Handle when an attack card is clicked - return it to the hand
	##
	## Clicking an attack card is a shortcut to return it to hand without dragging.
	##
	## @param card: The card that was clicked
	atk_card_clicked.emit(card)

func _on_atk_card_drag_started(card: Node):
	## Handle when an attack card drag starts
	##
	## Forward to GameScreen for drag state coordination.
	##
	## @param card: The card being dragged
	atk_card_drag_started.emit(card)

func _on_atk_card_drag_ended(card: Node):
	## Handle when an attack card drag ends - check if it's outside play zone bounds
	##
	## If the card is dropped outside the PlayZone bounds, it's returned to hand.
	## If dropped inside bounds, it snaps back to its arranged position.
	##
	## @param card: The card that was dragged
	var card_local_pos = card.global_position - global_position
	var play_zone_bounds = _get_bounds_rect()

	if not play_zone_bounds.has_point(card_local_pos):
		# Card was dragged outside play zone bounds - return to hand
		atk_card_dragged_out.emit(card)
	else:
		# Card was dropped inside the play zone - just rearrange to snap it back
		_arrange_cards()

# ============================================================================
# EDITOR PREVIEW
# ============================================================================

func _setup_editor_preview() -> void:
	## Create sample set and attack cards in editor for layout preview
	##
	## Shows 2 set cards and 2 attack cards to visualize the dual-zone system.
	## Helps developers see how the layout looks in the editor.

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
