@tool
extends Node2D
## CPUHand - Visual representation of opponent card counts
##
## This component displays the cards in a CPU player's hand as face-down card backs.
## Unlike PlayerHand, this is purely visual - the actual card data is managed by
## GameState, and this component only shows how many cards the opponent has.
##
## Key features:
## - Shows card backs only (cards are hidden from human player)
## - Non-interactive - no clicking or dragging allowed
## - Animated transitions when CPU plays cards (move to center and back)
## - Dynamic card count management (updates as CPU draws/plays cards)
## - Tighter spacing than PlayerHand to handle potentially larger hands
##
## Why card backs only:
## In Killer 13, players can't see opponents' cards (obviously). This component
## creates the visual representation of "I know they have 8 cards, but I don't
## know what they are." The card count is public information, but the cards
## themselves remain hidden.
##
## Integration: Works with GameScreen for lifecycle and animation coordination.

# ============================================================================
# EXPORTS - Tunable Animation Parameters
# ============================================================================

## Duration for animating hand to center when CPU is playing (in seconds)
## Short duration keeps the game moving at a good pace
@export var animate_to_center_duration: float = 0.3

## Scale multiplier when hand is animated to center (creates emphasis effect)
## Slightly larger than 1.0 draws attention to which CPU is playing
@export var center_scale_multiplier: float = 1.1

## Duration for animating hand back to original position after play
@export var animate_to_original_duration: float = 0.3

## Offset amount when moving toward center (in pixels)
## How far the hand moves toward the center of the screen
@export var center_offset_amount: float = 100.0

# ============================================================================
# DERIVED VALUES - Cached Constants
# ============================================================================

## Spacing between card backs in CPU hand
## Tighter than player hand spacing to accommodate larger card counts
var CARD_SPACING: float:
	get: return Constants.CPU_HAND_CARD_SPACING

# ============================================================================
# STATE VARIABLES
# ============================================================================

## Array tracking card visual nodes currently in the hand
## Note: These are just visual placeholders, not actual Card data
var _cards: Array[Node] = []

## Original position of the hand (stored for animation return)
## Set during _ready() and used by animate_to_original_position()
var _original_position: Vector2

# ============================================================================
# LIFECYCLE METHODS
# ============================================================================

func _ready() -> void:
	# Store the original position for animation system
	_original_position = position

	if Engine.is_editor_hint():
		# MODE 1: EDITOR PREVIEW
		# Shows 8 sample card backs for layout visualization
		_setup_editor_preview()
	else:
		# MODE 2: RUNTIME
		# Clear any preview cards - real card count will be set by GameScreen
		for card in get_children():
			card.queue_free()

func _exit_tree() -> void:
	## Clean up all resources when CPUHand is freed
	# Free all card visuals
	for card in _cards:
		if is_instance_valid(card):
			card.queue_free()
	_cards.clear()

# ============================================================================
# PUBLIC API - Card Count Management
# ============================================================================

func add_card() -> void:
	## Add a single card back to the hand (used during dealing)
	##
	## This increments the visual card count by one. The card is always a
	## face-down back since the human player can't see CPU cards.
	var card_visual = CardPool.get_card()
	add_child(card_visual)

	# Set to show back (hide the card face)
	if card_visual.has_method("set_show_back"):
		card_visual.set_show_back(true)

	# Hide shadows for CPU hands
	if card_visual.has_method("set_shadow_visible"):
		card_visual.set_shadow_visible(false)

	var shadow_sprite = card_visual.get_node_or_null("ShadowSprite")
	if shadow_sprite:
		shadow_sprite.visible = false

	# Track the new card
	_cards.append(card_visual)

	# Disable interaction for CPU cards (players can't click/drag opponent cards)
	var interaction = card_visual.get_node_or_null("Interaction")
	if interaction:
		interaction.is_player_card = false

	# Rearrange cards to accommodate the new one
	_arrange_cards()

func clear_and_set_count(count: int) -> void:
	## Remove all child cards and create exact number of card backs
	##
	## This is used to synchronize the visual card count with the logical count
	## in GameState. Called when CPU plays cards or when starting a new round.
	##
	## @param count: Number of card backs to display

	# Clear the tracking array immediately (prevents visual bugs during transitions)
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

func clear_all_cards() -> void:
	## Removes all cards from the CPU hand
	##
	## Complete reset operation - used when starting a new game.
	for card in _cards:
		card.queue_free()
	_cards.clear()

# ============================================================================
# PUBLIC API - Animation System
# ============================================================================
# These animations provide visual feedback about which CPU player is currently
# taking their turn. The hand moves toward the center and scales up slightly,
# then returns to its original position after the play completes.
# ============================================================================

func animate_to_center(duration: float = -1.0) -> void:
	## Animates the CPU hand towards the center of the screen
	##
	## This creates visual emphasis when a CPU player starts their turn.
	## The hand moves inward and scales up slightly to draw attention.
	##
	## How it works:
	## 1. Calculate direction vector from hand to screen center
	## 2. Move hand along that direction by center_offset_amount pixels
	## 3. Scale hand up by center_scale_multiplier
	## 4. Animate both transformations simultaneously
	##
	## @param duration: Animation duration in seconds (-1 uses default)
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

	# Animate position and scale simultaneously
	tween.tween_property(self, "position", target_position, duration)
	tween.tween_property(self, "scale", Vector2(center_scale_multiplier, center_scale_multiplier), duration)

func animate_to_original_position(duration: float = -1.0) -> void:
	## Animates the CPU hand back to its original position
	##
	## Called after a CPU player completes their turn. Returns the hand to
	## its resting position and resets scale to normal.
	##
	## @param duration: Animation duration in seconds (-1 uses default)
	if duration < 0:
		duration = animate_to_original_duration

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)

	# Return to original position and scale
	tween.tween_property(self, "position", _original_position, duration)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), duration)

# ============================================================================
# ARRANGEMENT - Card Layout
# ============================================================================

func _arrange_cards() -> void:
	## Arrange cards in a straight horizontal line with tight spacing
	##
	## Uses CPU_HAND_CARD_SPACING which is tighter than player hand spacing.
	## This allows CPU hands to display more cards without taking up too much space.
	##
	## Layout is centered around the hand's origin point, just like PlayerHand.
	if _cards.size() == 0:
		return

	var card_count = _cards.size()
	# Calculate total width and center offset
	var total_width = (card_count - 1) * CARD_SPACING
	var start_x = -total_width / 2.0

	for idx in range(card_count):
		var card = _cards[idx]
		var x = start_x + (idx * CARD_SPACING)
		card.position = Vector2(x, 0)

# ============================================================================
# EDITOR PREVIEW
# ============================================================================

func _setup_editor_preview() -> void:
	## Create sample face-down cards in editor for layout preview
	##
	## Shows 8 card backs to represent a typical CPU hand size.
	## Helps developers visualize the layout in the editor.

	# Clear any existing cards
	for card in get_children():
		card.queue_free()

	_cards.clear()

	# Create 8 face-down cards for preview (typical CPU hand size)
	for i in range(8):
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

		# Disable interaction for preview
		var interaction = card_visual.get_node_or_null("Interaction")
		if interaction:
			interaction.is_player_card = false

		# Track the card
		_cards.append(card_visual)

	# Arrange cards
	_arrange_cards()
