@tool
extends Node2D
## PlayerHand - Manages the player's hand of cards

## Emitted when a card is dragged out of the hand bounds
signal card_dragged_out(card_visual: Node)

## Emitted when a card in the hand is clicked
signal card_clicked(card_visual: Node)

## Emitted when a card drag starts
signal card_drag_started(card_visual: Node)

## Emitted when a card drag ends (for play zone handling)
signal card_drag_ended(card_visual: Node)

const CARD_SPACING: float = 115.0  # Horizontal spacing between cards
const THRESHOLD_PADDING: float = 20.0  # Extra padding around hand bounds for threshold
const HAND_Z_INDEX_BASE: int = 20  # Base z-index for hand cards (above PlayZone cards)

var _cards_in_hand: Array[Node] = []  # Track which cards are still in the hand
var _card_original_index: Dictionary = {}  # Map each card to its original scene tree index

# Flag to indicate that this PlayerHand version handles bounds checking
var handles_bounds_checking: bool = true


func _ready() -> void:
	if Engine.is_editor_hint():
		# MODE 1: EDITOR PREVIEW
		# Visual preview only - cards visible but not truly interactive (just for layout)
		_setup_editor_preview()
	else:
		# Runtime mode - check if standalone or full game
		var is_standalone = _is_running_standalone()

		if is_standalone:
			# MODE 2: STANDALONE TEST (F6)
			# Running just this scene for testing - create preview cards with full interactivity
			_setup_editor_preview()
			_setup_test_camera()
		else:
			# MODE 3: FULL GAME
			# Part of larger game - clear preview cards, wait for game to populate real cards
			for child in get_children():
				child.queue_free()

	# Set up drag monitoring if we're not in editor mode
	if not Engine.is_editor_hint():
		# Connect to card drag events to detect when cards are dragged out of bounds
		_setup_drag_listeners()

		# In standalone mode, we'll handle the card removal and arrangement here
		if _is_running_standalone():
			_setup_test_mode_listeners()


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


func _on_card_drag_ended(card_visual: Node):
	# Check if this card (which was in the hand) was dragged outside hand bounds
	if card_visual in _cards_in_hand:
		var card_local_pos = card_visual.global_position - global_position
		var hand_bounds = _get_hand_bounds()

		if not hand_bounds.has_point(card_local_pos):
			# Card was in hand and is now outside hand bounds - handle drag-out
			_handle_card_dragged_out(card_visual)
		# else: Card ended drag within hand bounds
		# Do nothing here, as this is the end of a drag that stayed in bounds
	else:
		# Card was not in hand (must be in play zone)
		# Do nothing here, as PlayZone handles drags for atk cards
		# This prevents double-processing of drag events
		pass


func _on_card_clicked(card_visual: Node):
	# In full game mode with bounds checking, clicking a card in hand sends it to play zone
	if not _is_running_standalone():
		if card_visual in _cards_in_hand:
			# Card is in hand, so send it to play zone (like dragging it out)
			# This emits the card_dragged_out signal, which GameScreen handles
			_handle_card_dragged_out(card_visual)
		# else: Card is not in hand (probably in play zone)
		# Do nothing here, as PlayZone handles clicks for atk cards
		# This prevents double-processing of click events
		pass
	elif _is_running_standalone():
		# In standalone/test mode, clicking cards in hand sends them out (deletes them)
		# Cards in play zone behavior is not relevant in standalone hand mode
		if card_visual in _cards_in_hand:
			# Handle click-specific behavior in test mode
			var card_description = _get_card_action_description(card_visual, "Clicked")
			_cards_in_hand.erase(card_visual)
			_update_z_indices()
			_arrange_cards()
			card_visual.queue_free()
			print(card_description)


func _on_card_drag_started(card_visual: Node):
	# Forward card drag start to GameScreen in full game mode
	if not _is_running_standalone():
		card_drag_started.emit(card_visual)


func _setup_test_mode_listeners():
	# In test mode, we handle card removal directly
	pass


# No longer using _process for continuous checking
# Instead, we'll rely on card interaction events to detect drag-outs


func _handle_card_dragged_out(card_visual: Node):
	# Emit signal that a card was dragged out
	card_dragged_out.emit(card_visual)

	# In standalone/test mode, we handle the full behavior here
	if _is_running_standalone():
		# Remove the card from the hand's tracking array
		_cards_in_hand.erase(card_visual)

		# Update z indices and rearrange remaining cards
		_update_z_indices()
		_arrange_cards()

		# Delete the card with action-specific logging
		var card_description = _get_card_action_description(card_visual, "Dragged")
		card_visual.queue_free()
		print(card_description)
	# In full game mode, GameScreen handles the card movement and hand adjustment


## Check if this scene is running standalone (F6) vs as part of full game
## Returns true if no GameScreen parent is found (standalone mode)
func _is_running_standalone() -> bool:
	# Walk up the scene tree looking for GameScreen
	var current = get_parent()
	while current:
		if current.name == "GameScreen":
			return false  # Found GameScreen - we're in full game
		current = current.get_parent()
	return true  # No GameScreen found - running standalone


## Create a camera for standalone test mode (F6 only)
## Centers the view on the player hand for easier testing
func _setup_test_camera() -> void:
	var camera = Camera2D.new()
	camera.name = "TestCamera"
	camera.position = Vector2.ZERO  # Center on PlayerHand (which is at 0,0)
	camera.enabled = true
	add_child(camera)


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
			var rank_str = str(card_data.rank) if card_data.rank != null else "Unknown"
			var suit_str = str(card_data.suit) if card_data.suit != null else "Unknown"
			return rank_str + " of " + suit_str
	return card_visual.name if card_visual.name else "Unknown"


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
	_card_original_index.clear()

	# Create 13 default cards for editor preview (ranks 3 through 2 in different suits)
	var default_cards = []
	for i in range(13):
		var rank = i % 13  # 0-12 (THREE to TWO)
		var suit = int(i / 4) % 4  # 0-3 (SPADES to HEARTS) - cycling through suits
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
		_card_original_index[card_visual] = idx

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


func _add_card_back(card: Node) -> void:
	"""Add a card back to the hand at its original position"""
	# Safety check: don't add if already in hand
	if card in _cards_in_hand:
		return

	# Find the correct insertion point based on original index
	var original_idx = _card_original_index.get(card, -1)
	if original_idx == -1:
		return

	# Insert at the position that maintains original order
	var insert_pos = 0
	for in_hand_card in _cards_in_hand:
		var in_hand_original_idx = _card_original_index.get(in_hand_card, -1)
		if in_hand_original_idx < original_idx:
			insert_pos += 1

	_cards_in_hand.insert(insert_pos, card)

	# Connect drag listener for this card if not already connected
	_connect_card_drag_listener(card)

	_update_z_indices()
	_arrange_cards()


func _update_z_indices() -> void:
	"""Recalculate z_indices for remaining in-hand cards"""
	for idx in range(_cards_in_hand.size()):
		_cards_in_hand[idx].z_index = HAND_Z_INDEX_BASE + idx


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
		interaction.is_player_card = true
		# Update base position for hover animations
		if interaction.has_method("update_base_position"):
			interaction.update_base_position()

	# Hide shadows
	if card_visual.has_method("set_shadow_visible"):
		card_visual.set_shadow_visible(false)

	# Track the card
	var new_idx = _cards_in_hand.size()
	_cards_in_hand.append(card_visual)
	_card_original_index[card_visual] = new_idx

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
	_card_original_index.clear()

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
			interaction.is_player_card = true
			# Update base position for hover animations
			if interaction.has_method("update_base_position"):
				interaction.update_base_position()

		# Track the card
		_cards_in_hand.append(card_visual)
		_card_original_index[card_visual] = idx

		# Connect drag listener for this card
		_connect_card_drag_listener(card_visual)

		# Hide shadows
		if card_visual.has_method("set_shadow_visible"):
			card_visual.set_shadow_visible(false)

	# Update z indices and arrange
	_update_z_indices()
	_arrange_cards()
