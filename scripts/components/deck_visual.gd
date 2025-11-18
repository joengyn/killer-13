@tool
extends Node2D
## DeckVisual - Visual deck representation and card dealing animation
##
## This component manages the visual deck of cards shown at the start of the game
## and handles the dealing animation as cards are distributed to players.
##
## Key responsibilities:
## - Displays a stack of card backs representing the deck
## - Animates individual cards flying from deck to player hands during dealing
## - Maintains visual deck count (decreases as cards are dealt)
## - Provides click interaction to trigger dealing (in some game modes)
##
## Dealing strategy - Two-phase approach:
##
## Phase 1: First 47 cards (DEALING_INSTANTIATE_THRESHOLD)
## - Creates temporary card instances for animation
## - Deck visual remains full (doesn't decrease yet)
## - Prevents jarring "deck shrinking too fast" visual
##
## Phase 2: Last 5 cards
## - Uses actual deck stack cards for animation
## - Deck visually decreases as cards are removed
## - Creates satisfying "running out of cards" effect
##
## Why this two-phase approach?
## If we decreased the deck count for all 52 cards, it would shrink immediately
## to zero during dealing (since dealing is fast). By keeping it full for the
## first 47 cards and only showing decrease for the last 5, we create better
## visual feedback without the deck disappearing too quickly.
##
## Integration: Works with GameScreen for dealing coordination and cleanup.

# ============================================================================
# SIGNALS
# ============================================================================

## Emitted when dealing starts (triggered by deck click)
signal deal_started

## Emitted when a single card finishes its dealing animation
## @param card_visual: The animated card that reached its destination
signal card_dealt(card_visual: Node)

# ============================================================================
# EXPORTS - Tunable Animation Parameters
# ============================================================================

## Duration for card dealing animation in seconds
## Short duration keeps dealing snappy and engaging
@export var deal_animation_duration: float = 0.15

## Rotation angle for cards dealt to left CPU player (radians)
## Cards rotate to match the hand orientation for that position
@export var left_player_rotation: float = -PI / 2.0

## Rotation angle for cards dealt to right CPU player (radians)
@export var right_player_rotation: float = -PI / 2.0

## Rotation angle for cards dealt to top CPU player (radians)
## No rotation needed since top player is horizontal like human player
@export var top_player_rotation: float = 0.0

# ============================================================================
# STATE VARIABLES
# ============================================================================

## Current number of cards remaining in the visual deck
## Decrements during Phase 2 of dealing (last 5 cards)
var _remaining_cards: int = 52

## Array of all card visual nodes in the deck stack
## Used to populate the deck and for Phase 2 dealing
var _card_visuals: Array[Node] = []

## Total cards dealt so far (across both phases)
## Used to determine when to switch from Phase 1 to Phase 2
var _cards_dealt_total: int = 0

## Array of temporary cards created for Phase 1 dealing animation
## These must be cleaned up after dealing completes to prevent memory leaks
var _dealt_cards: Array[Node] = []

# ============================================================================
# LIFECYCLE METHODS
# ============================================================================

func _ready() -> void:
	if Engine.is_editor_hint():
		# MODE 1: EDITOR PREVIEW
		# Shows 5 stacked cards with slight offset for depth effect
		_setup_editor_preview()
	else:
		# MODE 2: RUNTIME
		# Create the full deck of 52 card backs at runtime
		for i in range(52):
			var card_visual = CardPool.get_card()
			add_child(card_visual)

			# Position all cards in a stack (same position)
			card_visual.position = Vector2.ZERO

			# Set to show card back
			if card_visual.has_method("set_show_back"):
				card_visual.set_show_back(true)

			# Hide shadows for deck cards
			if card_visual.has_method("set_shadow_visible"):
				card_visual.set_shadow_visible(false)

			# Add to card visuals array
			_card_visuals.append(card_visual)

		_remaining_cards = _card_visuals.size()

		# Add click detection at runtime
		_setup_click_detection()

func _exit_tree() -> void:
	## Clean up all card visuals when scene is freed
	# Free all card visuals in the deck
	for card in _card_visuals:
		if is_instance_valid(card):
			card.queue_free()
	_card_visuals.clear()

	# Free all dealt cards
	for card in _dealt_cards:
		if is_instance_valid(card):
			card.queue_free()
	_dealt_cards.clear()

# ============================================================================
# PUBLIC API - Dealing and State
# ============================================================================

func deal_card_animated(target_pos: Vector2, player_idx: int) -> void:
	## Animate a card from deck to target position
	##
	## This creates the visual effect of a card flying from the deck to a player's hand.
	## Uses a two-phase strategy to maintain good visual feedback throughout dealing.
	##
	## Phase 1 (first 47 cards):
	## - Creates temporary card instance for animation
	## - Deck visual stays full
	##
	## Phase 2 (last 5 cards):
	## - Pops cards from _card_visuals array
	## - Deck visual decreases
	##
	## @param target_pos: Global position where the card should animate to
	## @param player_idx: Which player is receiving the card (0=human, 1-3=CPU)

	var card: Node

	# Determine which phase we're in based on total cards dealt
	if _cards_dealt_total >= Constants.DEALING_INSTANTIATE_THRESHOLD and _card_visuals.size() > 0:
		# PHASE 2: Last 5 cards - use and remove from the deck visual stack
		card = _card_visuals.pop_back()
		_remaining_cards = _card_visuals.size()
	else:
		# PHASE 1: First 47 cards - instantiate temporary cards
		card = CardPool.get_card()
		add_child(card)
		card.position = Vector2.ZERO
		if card.has_method("set_show_back"):
			card.set_show_back(true)

	# Increment total dealt count
	_cards_dealt_total += 1

	# Always show card back during dealing animation
	if card.has_method("set_shadow_visible"):
		card.set_shadow_visible(false)

	# Animate from deck position to target with rotation for left/right CPU players
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)

	# Set target rotation based on player position
	# This makes cards orient correctly for their destination hand
	var target_rotation = 0.0
	if player_idx == 1:  # Left CPU
		target_rotation = left_player_rotation
	elif player_idx == 2:  # Top CPU
		target_rotation = top_player_rotation
	elif player_idx == 3:  # Right CPU
		target_rotation = right_player_rotation

	# Animate position (always) and rotation (if needed)
	tween.tween_property(card, "global_position", target_pos, deal_animation_duration)
	if target_rotation != 0.0:
		tween.parallel().tween_property(card, "rotation", target_rotation, deal_animation_duration)

	# Wait for animation to complete
	await tween.finished
	emit_signal("card_dealt", card)

	# Store the dealt card for cleanup at the end of dealing
	# This prevents the card from disappearing/reappearing glitch
	# Cards are cleaned up via cleanup_dealt_cards() after dealing completes
	_dealt_cards.append(card)

func get_remaining_card_count() -> int:
	## Return how many cards are left in the visual deck
	##
	## This reflects the visual state, not the logical state.
	## During Phase 1, this will be 52 even as cards are being dealt.
	##
	## @return: Number of card visuals remaining in the deck
	return _remaining_cards

func cleanup_dealt_cards() -> void:
	## Clean up all animated cards after dealing completes
	##
	## This removes the temporary cards created during Phase 1 dealing.
	## Called by GameScreen after all dealing animations finish.
	##
	## Why this is necessary:
	## Without cleanup, temporary cards would remain in the scene tree
	## even though they're not visible. This would cause memory leaks
	## and could interfere with other game systems.
	for card in _dealt_cards:
		card.queue_free()
	_dealt_cards.clear()

# ============================================================================
# CLICK DETECTION - Deck Interaction
# ============================================================================

func _setup_click_detection() -> void:
	## Add an Area2D for click detection on the deck
	##
	## Creates an interactive area over the deck that emits deal_started
	## when clicked. This is used in some game modes to manually trigger dealing.

	# Check if Area2D already exists (prevents duplicate creation)
	var area = get_node_or_null("Area2D")
	if area == null:
		area = Area2D.new()
		area.name = "Area2D"
		add_child(area)

		# Create collision shape for click detection
		var collision = CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		var shape = RectangleShape2D.new()
		# 1.5x card size for generous click area
		shape.size = Vector2(
			Constants.CARD_BASE_WIDTH * 1.5,
			Constants.CARD_BASE_HEIGHT * 1.5
		)
		collision.shape = shape
		area.add_child(collision)

		# Connect click detection
		if not area.input_event.is_connected(_on_deck_clicked):
			area.input_event.connect(_on_deck_clicked)

func _on_deck_clicked(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	## Handle deck click - emit deal_started signal
	##
	## @param _viewport: The viewport that received the input (unused)
	## @param event: The input event
	## @param _shape_idx: The collision shape index (unused)
	if event is InputEventMouseButton and event.pressed:
		emit_signal("deal_started")

# ============================================================================
# EDITOR PREVIEW
# ============================================================================

func _setup_editor_preview() -> void:
	## Create a stacked card deck preview in editor
	##
	## Shows 5 cards with slight positional offsets to create a 3D stack effect.
	## This helps visualize the deck appearance during development.

	# Clear any existing cards
	for card in get_children():
		card.queue_free()

	_card_visuals.clear()

	# Create 5 stacked cards with slight offsets for visual depth
	for i in range(5):
		var card_visual = CardPool.get_card()
		add_child(card_visual)

		# Position cards in a stack with slight offset for depth effect
		# Each subsequent card is offset by 2 pixels in both x and y
		var offset = i * 2
		card_visual.position = Vector2(offset * 0.5, offset * 0.5)

		# Set to show card back
		if card_visual.has_method("set_show_back"):
			card_visual.set_show_back(true)

		# Hide shadows for deck cards
		if card_visual.has_method("set_shadow_visible"):
			card_visual.set_shadow_visible(false)

		# Set z-index so cards layer correctly (higher cards on top)
		card_visual.z_index = i

		_card_visuals.append(card_visual)

	_remaining_cards = _card_visuals.size()
