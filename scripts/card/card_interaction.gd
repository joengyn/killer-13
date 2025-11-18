extends Node
## CardInteraction - Manages player input, hover effects, and drag-and-drop for card visuals
##
## Handles click detection, drag operations, hover animations (scale + position + shader rotation),
## and shadow visibility. Uses static guards to prevent race conditions when multiple cards overlap.
## Only active when is_player_card is true.

## Emitted when the user starts dragging this card
signal drag_started(card_visual: Node)
## Emitted when the user stops dragging this card
signal drag_ended(card_visual: Node)
## Emitted when the card's position is updated during a drag
signal drag_position_updated(card_visual: Node)
## Emitted when the user clicks this card without dragging
signal card_clicked(card_visual: Node)

## ============================================================================
## CONFIGURATION - Adjustable via Godot Inspector
## ============================================================================

## Scale multiplier when hovering over card (1.1 = 10% larger)
@export var hover_scale_multiplier: float = 1.1
## Vertical lift when hovering (negative = upward movement)
@export var hover_vertical_offset: float = -80.0
## Duration for scale animations when entering/exiting hover
@export var scale_animation_duration: float = 0.2
## Duration for position animations when entering/exiting hover
@export var position_animation_duration: float = 0.2
## Duration for resetting hover effects
@export var reset_animation_duration: float = 0.3

## ============================================================================
## CONSTANTS
## ============================================================================

const CARD_SIZE: Vector2 = Vector2(56.0, 80.0)  ## Base card dimensions for hit detection
const SHADER_MAX_ROTATION: float = 15.0  ## Maximum 3D tilt angle in degrees
const SHADER_EASING_DURATION: float = 0.2  ## Duration for shader rotation animations

@onready var card_visual = get_parent()
var click_area: Area2D
var outer_sprite: Sprite2D

## If true, this card responds to player input (hover, click, drag)
var is_player_card: bool = false
## If true, this card can be moved out of the hand (clicked or dragged to play zone)
var can_move_out_of_hand: bool = false
## If true, the card is currently being dragged
var _is_being_dragged: bool = false
## Offset from cursor to card center during drag (maintains relative grab position)
var _drag_offset: Vector2 = Vector2.ZERO
## If true, mouse is currently over this card
var _is_mouse_over: bool = false
## If true, mouse was pressed down on this card (used to distinguish click vs drag)
var _mouse_pressed: bool = false
## Position where mouse was initially pressed (used to detect drag threshold)
var _mouse_press_position: Vector2 = Vector2.ZERO

## Tween for shader rotation animations
var _reset_tween: Tween
## Original scale before hover effects applied
var _base_scale: Vector2 = Vector2.ONE
## Tween for scale animations
var _scale_tween: Tween
## Tween for position animations
var _position_tween: Tween
## Base Y position when in hand (updated when hand rearranges)
var _base_y: float = 0.0

## Static guard to prevent multiple cards from processing the same click in one frame
static var _last_click_frame: int = -1
static var _click_processed_this_frame: bool = false

## Guard to prevent immediate re-click after card moves (prevents toggle spam)
static var _last_clicked_card: Node = null
static var _last_clicked_frame: int = -1

## Track if any card is currently being dragged (disables hover on all other cards)
static var _any_card_being_dragged: Node = null


func _ready():
	click_area = card_visual.get_node("ClickArea")
	outer_sprite = get_parent().get_node("OuterSprite")
	if not click_area:
		push_error("CardInteraction: click_area is null!")
		return

	_base_scale = card_visual.scale
	_base_y = card_visual.position.y
	click_area.input_pickable = true
	click_area.input_event.connect(_on_click_area_input)

	# Hide shadow initially for player cards
	if is_player_card:
		if card_visual.has_method("set_shadow_visible"):
			card_visual.set_shadow_visible(false)


## Update the base Y position reference when the hand is rearranged
## Called by PlayerHand after repositioning cards
func update_base_position() -> void:
	_base_y = card_visual.position.y

## Reset all hover effects when card changes location (hand ↔ play zone)
## Clears hover flags, resets shader rotation, and updates shadow visibility
func reset_hover_state() -> void:
	_is_mouse_over = false
	_reset_shader_rotation()
	_animate_scale_to(_base_scale)

	# Only apply position changes if in player hand
	if _is_in_player_hand():
		_animate_position_y_to(_base_y)

	# Update shadow visibility based on location
	_update_shadow_for_location()


## Enable or disable all interaction for this card and reset effects
## @param enabled: If true, enables interaction; if false, disables and resets all effects
## NOTE: Prefer direct assignment to is_player_card in most cases.
## Use this method when you need the full reset behavior (clears hover, drag, animations).
func set_interactive(can_drag_reorder: bool, can_move_out_of_hand_param: bool) -> void:
	is_player_card = can_drag_reorder # is_player_card now controls general interaction like hover and reordering
	can_move_out_of_hand = can_move_out_of_hand_param # New flag for moving cards out of hand
	if not is_player_card: # If general interaction is disabled, reset all states
		# Reset any active hover/drag state
		_is_mouse_over = false
		_is_being_dragged = false
		_mouse_pressed = false
		_reset_shader_rotation()
		_animate_scale_to(_base_scale)
		if _is_in_player_hand():
			_animate_position_y_to(_base_y)
		_update_shadow_for_location()


func _on_click_area_input(_viewport: Node, event: InputEvent, _shape_idx: int):
	if not is_player_card:
		return

	# Only accept input if this card is topmost (highest z_index among siblings)
	if not _is_topmost_by_z_index():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var current_frame = Engine.get_process_frames()

		# Reset guard if we're in a new frame
		if _last_click_frame != current_frame:
			_last_click_frame = current_frame
			_click_processed_this_frame = false

		if event.pressed:
			_mouse_pressed = true
			# Convert screen position to global position to account for any camera transformations
			_mouse_press_position = get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
		else:
			# Mouse released - check if this was a click or drag
			if _mouse_pressed and not _is_being_dragged and not _click_processed_this_frame:
				# Check if this is a re-click of the same card too soon (prevents click → move → immediate re-click)
				if _last_clicked_card == card_visual and (current_frame - _last_clicked_frame) < Constants.CARD_CLICK_COOLDOWN_FRAMES:
					# Same card clicked too soon - ignore to prevent rapid toggling when mouse stays over card
					_mouse_pressed = false
					return

				# Was a click (not dragged far enough to trigger drag)
				# Mark that we processed a click this frame to prevent other cards from also processing
				_click_processed_this_frame = true
				_last_clicked_card = card_visual
				_last_clicked_frame = current_frame

				if is_player_card:
					card_clicked.emit(card_visual)
			_mouse_pressed = false
		get_tree().root.set_input_as_handled()


func _unhandled_input(event: InputEvent):
	if event is InputEventMouseMotion:
		# Check if mouse is being dragged from a press
		if _mouse_pressed and not _is_being_dragged and is_player_card:
			var current_global_mouse = get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
			var drag_distance = current_global_mouse.distance_to(_mouse_press_position)
			if drag_distance > 5.0 and is_player_card:  # Threshold to start drag (5 pixels)
				_start_drag(_mouse_press_position)

		if _is_being_dragged:
			# Use global mouse position to maintain proper positioning during drag
			var global_mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
			card_visual.global_position = global_mouse_pos + _drag_offset
			drag_position_updated.emit(card_visual)
			get_tree().root.set_input_as_handled()
		elif is_player_card and not _is_being_dragged:
			# Simplified hover logic: only hover if this card is topmost and no other card is dragging
			var is_any_card_dragging = _any_card_being_dragged != null

			# If any card is being dragged, disable hover on all cards
			if is_any_card_dragging:
				if _is_mouse_over:
					_is_mouse_over = false
					_reset_shader_rotation()
					if _is_in_player_hand():
						_animate_scale_to(_base_scale)
						_animate_position_y_to(_base_y)
					_update_shadow_for_location()
				return

			# Check if this card is under the mouse and is the topmost card
			var mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
			var base_card_size = Vector2(Constants.CARD_BASE_WIDTH, Constants.CARD_BASE_HEIGHT)
			var scaled_card_size = base_card_size * card_visual.scale
			var card_rect = Rect2(card_visual.global_position - scaled_card_size / 2.0, scaled_card_size)
			var is_under_mouse = card_rect.has_point(mouse_pos)

			var should_hover = is_under_mouse and _is_topmost_by_z_index()

			if should_hover and not _is_mouse_over:
				# Activate hover
				_is_mouse_over = true
				if _is_in_player_hand():
					_animate_scale_to(_base_scale * hover_scale_multiplier)
					_animate_position_y_to(_base_y + hover_vertical_offset)
				if card_visual.has_method("set_shadow_visible"):
					card_visual.set_shadow_visible(true)
				_update_shader_rotation()
			elif should_hover and _is_mouse_over:
				# Continue hover - update shader rotation
				_update_shader_rotation()
			elif not should_hover and _is_mouse_over:
				# Deactivate hover
				_is_mouse_over = false
				_reset_shader_rotation()
				if _is_in_player_hand():
					_animate_scale_to(_base_scale)
					_animate_position_y_to(_base_y)
				_update_shadow_for_location()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _is_being_dragged:
		_end_drag()
		get_tree().root.set_input_as_handled()


## Internal: Start dragging this card
## @param mouse_pos: Global mouse position where drag was initiated
func _start_drag(mouse_pos: Vector2) -> void:
	_is_being_dragged = true
	_any_card_being_dragged = card_visual  # Track globally that a card is being dragged
	_drag_offset = card_visual.global_position - mouse_pos
	# Set to high z_index while dragging so it appears above all other cards
	card_visual.z_index = 100
	_reset_shader_rotation()
	_animate_scale_to(_base_scale)
	# Show shadow effect when dragging starts
	var card_visual_script = card_visual as Node2D
	if card_visual_script:
		card_visual_script.set_shadow_visible(true)

	drag_started.emit(card_visual)


## Internal: End drag operation and emit signal
## Parent (GameScreen) handles actual card placement logic
func _end_drag() -> void:
	_is_being_dragged = false
	_any_card_being_dragged = null  # Clear global drag tracking
	_mouse_pressed = false  # Reset mouse state
	_drag_offset = Vector2.ZERO  # Clear drag offset to prevent further movement
	# Note: z_index will be reset by PlayerHand.rearrange_cards_in_hand() after repositioning

	drag_ended.emit(card_visual)


## Update shader rotation to create 3D tilt effect based on mouse position
## Mouse near edges causes card to tilt away from cursor, creating depth illusion
func _update_shader_rotation() -> void:
	if not outer_sprite or not outer_sprite.material:
		return

	var mouse_pos: Vector2 = card_visual.get_local_mouse_position()

	# Remap mouse position to 0-1 range (inverted Y so corners push away)
	var lerp_val_x: float = remap(mouse_pos.x, -CARD_SIZE.x / 2.0, CARD_SIZE.x / 2.0, 0.0, 1.0)
	var lerp_val_y: float = remap(mouse_pos.y, -CARD_SIZE.y / 2.0, CARD_SIZE.y / 2.0, 1.0, 0.0)

	# Clamp to valid range
	lerp_val_x = clamp(lerp_val_x, 0.0, 1.0)
	lerp_val_y = clamp(lerp_val_y, 0.0, 1.0)

	# Calculate target rotation angles using lerp_angle
	var target_rot_x: float = rad_to_deg(lerp_angle(deg_to_rad(-SHADER_MAX_ROTATION), deg_to_rad(SHADER_MAX_ROTATION), lerp_val_x))
	var target_rot_y: float = rad_to_deg(lerp_angle(deg_to_rad(-SHADER_MAX_ROTATION), deg_to_rad(SHADER_MAX_ROTATION), lerp_val_y))

	# Get current rotation values
	var current_x_rot = outer_sprite.material.get_shader_parameter("x_rot") as float
	var current_y_rot = outer_sprite.material.get_shader_parameter("y_rot") as float

	# Kill previous tween if it exists to avoid conflicting animations
	if _reset_tween:
		_reset_tween.kill()

	# Create tween to smoothly ease in to target rotation
	_reset_tween = create_tween()
	_reset_tween.set_trans(Tween.TRANS_QUAD)
	_reset_tween.set_ease(Tween.EASE_OUT)
	_reset_tween.set_parallel(true)
	_reset_tween.tween_method(
		func(val: float) -> void: outer_sprite.material.set_shader_parameter("x_rot", val),
		current_x_rot,
		target_rot_y,
		SHADER_EASING_DURATION
	)
	_reset_tween.tween_method(
		func(val: float) -> void: outer_sprite.material.set_shader_parameter("y_rot", val),
		current_y_rot,
		target_rot_x,
		SHADER_EASING_DURATION
	)


## Smoothly animate card scale with easing
## @param target_scale: Target scale vector (e.g., Vector2(1.1, 1.1) for 10% larger)
func _animate_scale_to(target_scale: Vector2) -> void:
	# Kill previous scale tween if it exists
	if _scale_tween:
		_scale_tween.kill()

	# Create tween to smoothly interpolate to target scale
	_scale_tween = create_tween()
	_scale_tween.set_trans(Tween.TRANS_QUAD)
	_scale_tween.set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(card_visual, "scale", target_scale, scale_animation_duration)


## Smoothly animate card's Y position (for hover lift effect)
## @param target_y: Target Y coordinate in local space
func _animate_position_y_to(target_y: float) -> void:
	# Kill previous position tween if it exists
	if _position_tween:
		_position_tween.kill()

	# Create tween to smoothly interpolate Y position only
	_position_tween = create_tween()
	_position_tween.set_trans(Tween.TRANS_QUAD)
	_position_tween.set_ease(Tween.EASE_OUT)

	var start_y = card_visual.position.y
	_position_tween.tween_method(
		func(y: float) -> void: card_visual.position.y = y,
		start_y,
		target_y,
		position_animation_duration
	)


## Smoothly reset shader rotation back to neutral (0, 0) position
func _reset_shader_rotation() -> void:
	if not outer_sprite or not outer_sprite.material:
		return

	# Kill previous tween if it exists
	if _reset_tween:
		_reset_tween.kill()

	# Get current rotation values
	var current_x_rot = outer_sprite.material.get_shader_parameter("x_rot") as float
	var current_y_rot = outer_sprite.material.get_shader_parameter("y_rot") as float

	# Create tween to smoothly interpolate to 0
	_reset_tween = create_tween()
	_reset_tween.set_trans(Tween.TRANS_CUBIC)
	_reset_tween.set_ease(Tween.EASE_OUT)
	_reset_tween.set_parallel(true)
	_reset_tween.tween_method(
		func(val: float) -> void: outer_sprite.material.set_shader_parameter("x_rot", val),
		current_x_rot,
		0.0,
		reset_animation_duration
	)
	_reset_tween.tween_method(
		func(val: float) -> void: outer_sprite.material.set_shader_parameter("y_rot", val),
		current_y_rot,
		0.0,
		reset_animation_duration
	)


## Update shadow visibility based on card location
## Rule: In hand, shadow only shows on hover. In play zone, shadow always shows.
func _update_shadow_for_location() -> void:
	if not card_visual.has_method("set_shadow_visible"):
		return

	if _is_in_player_hand():
		# In hand: only show shadow if hovering
		card_visual.set_shadow_visible(_is_mouse_over)
	else:
		# In play zone or other location: always show shadow
		card_visual.set_shadow_visible(true)


## Check if this card is currently in the player's hand (vs play zone)
## @return: True if parent is PlayerHand node
func _is_in_player_hand() -> bool:
	var parent = card_visual.get_parent()
	return parent and parent.name == "PlayerHand"

## Check if this card has the highest z_index among all interactive cards under the mouse
## Prevents lower cards from stealing hover/click when overlapping
## @return: True if this card has the highest z_index of all cards under cursor
func _is_topmost_by_z_index() -> bool:
	# Convert screen position to global position to account for any camera transformations
	var mouse_pos = get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()
	var cards_under_mouse: Array[Node] = []

	var game_screen = _find_game_screen()
	if not game_screen:
		return true # Should not happen, but default to true to avoid blocking input

	var player_hand = game_screen.get_node_or_null("PlayerHand")
	var play_zone = game_screen.get_node_or_null("PlayZone")

	# Collect all interactive cards under the mouse from both hand and zone
	var potential_cards: Array[Node] = []
	if player_hand:
		potential_cards.append_array(player_hand.get_children())
	if play_zone:
		potential_cards.append_array(play_zone.get_children())

	for card in potential_cards:
		var interaction = card.get_node_or_null("Interaction")
		if interaction and interaction.is_player_card and _is_point_in_card(card, mouse_pos):
			cards_under_mouse.append(card)

	# If no cards are under the mouse (somehow), or only this one, it's topmost
	if cards_under_mouse.is_empty() or (cards_under_mouse.size() == 1 and cards_under_mouse[0] == card_visual):
		return true

	# Find the card with the highest z_index from the list
	var topmost_card = cards_under_mouse[0]
	for i in range(1, cards_under_mouse.size()):
		if cards_under_mouse[i].z_index > topmost_card.z_index:
			topmost_card = cards_under_mouse[i]

	# Is this card instance the one with the highest z_index?
	return topmost_card == card_visual


## Check if a global screen point is within a card's bounding rectangle
## @param card: The card node to check
## @param point: Global screen position to test (should be in global/world coordinates)
## @return: True if point is inside the card's bounds
func _is_point_in_card(card: Node, point: Vector2) -> bool:
	var base_card_size = Vector2(Constants.CARD_BASE_WIDTH, Constants.CARD_BASE_HEIGHT)
	var scaled_card_size = base_card_size * card.scale
	var card_rect = Rect2(card.global_position - scaled_card_size / 2.0, scaled_card_size)
	return card_rect.has_point(point)


## Find the GameScreen node by walking up the scene tree
## @return: The GameScreen node, or null if not found
func _find_game_screen() -> Node:
	# Try to find it by walking up the tree
	var current = card_visual.get_parent()
	while current:
		if current.name == "GameScreen":
			return current
		# Check if any sibling is GameScreen
		var parent = current.get_parent()
		if parent:
			var game_screen = parent.get_node_or_null("GameScreen")
			if game_screen:
				return game_screen
		current = parent
	return null


## Clean up tweens when node is removed to prevent memory leaks
func _exit_tree() -> void:
	if _reset_tween:
		_reset_tween.kill()
	if _scale_tween:
		_scale_tween.kill()
	if _position_tween:
		_position_tween.kill()
