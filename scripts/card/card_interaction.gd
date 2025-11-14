extends Node
## Handles input and drag-and-drop for cards

signal drag_started(card_visual: Node)
signal drag_ended(card_visual: Node)
signal card_clicked(card_visual: Node)

# Constants for card interaction
const CARD_SIZE: Vector2 = Vector2(56.0, 80.0)
const SHADER_MAX_ROTATION: float = 15.0  # Max rotation in degrees
const SHADER_EASING_DURATION: float = 0.2
const HOVER_SCALE_MULTIPLIER: float = 1.1
const HOVER_VERTICAL_OFFSET: float = -80.0  # Move upward by 80 pixels
const SCALE_ANIMATION_DURATION: float = 0.2
const POSITION_ANIMATION_DURATION: float = 0.2
const RESET_ANIMATION_DURATION: float = 0.3

@onready var card_visual = get_parent()
@onready var click_area = card_visual.get_node("ClickArea")
@onready var outer_sprite = card_visual.get_node("OuterSprite")

var is_player_card: bool = false
var _is_being_dragged: bool = false
var _drag_offset: Vector2 = Vector2.ZERO  # Offset from click point to card center; allows card to follow cursor from click position
var _is_mouse_over: bool = false
var _mouse_pressed: bool = false  # Track if mouse was pressed on this card
var _mouse_press_position: Vector2 = Vector2.ZERO  # Track where mouse was pressed

var _reset_tween: Tween
var _base_scale: Vector2 = Vector2.ONE
var _scale_tween: Tween
var _position_tween: Tween
var _base_y: float = 0.0  # Base vertical position (updated with hand rearrangement)

# Static guard to prevent multiple cards from processing the same click in one frame
static var _last_click_frame: int = -1
static var _click_processed_this_frame: bool = false

# Guard to prevent immediate re-click of the same card after it moves
static var _last_clicked_card: Node = null
static var _last_clicked_frame: int = -1
const CLICK_COOLDOWN_FRAMES: int = 10  # Minimum frames between clicks on same card

# Static guard to ensure only ONE card can be hovered per frame
# Prevents race condition where multiple overlapping cards all think they're topmost
# Works the same way as the click guard above
static var _last_hover_frame: int = -1
static var _hovered_card_this_frame: Node = null


func _ready():
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


func update_base_position() -> void:
	"""Update base Y position when hand is rearranged - call from PlayerHand"""
	_base_y = card_visual.position.y


func reset_hover_state() -> void:
	"""Reset all hover effects - call this when card is moved to a new location"""
	_is_mouse_over = false
	_reset_shader_rotation()
	_animate_scale_to(_base_scale)

	# Only apply position changes if in player hand
	if _is_in_player_hand():
		_animate_position_y_to(_base_y)

	# Update shadow visibility based on location
	_update_shadow_for_location()


func set_interactive(enabled: bool) -> void:
	"""Enable or disable all interaction for this card (hover, drag, etc.)
	NOTE: Prefer direct assignment to is_player_card in most cases.
	This method is kept for cases where you need the full reset behavior."""
	is_player_card = enabled
	if not enabled:
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
			_mouse_press_position = event.position
		else:
			# Mouse released - check if this was a click or drag
			if _mouse_pressed and not _is_being_dragged and not _click_processed_this_frame:
				# Check if this is a re-click of the same card too soon (prevents click → move → immediate re-click)
				if _last_clicked_card == card_visual and (current_frame - _last_clicked_frame) < CLICK_COOLDOWN_FRAMES:
					# Same card clicked too soon - ignore to prevent rapid toggling when mouse stays over card
					_mouse_pressed = false
					return

				# Was a click (not dragged far enough to trigger drag)
				# Mark that we processed a click this frame to prevent other cards from also processing
				_click_processed_this_frame = true
				_last_clicked_card = card_visual
				_last_clicked_frame = current_frame
				card_clicked.emit(card_visual)
			_mouse_pressed = false
		get_tree().root.set_input_as_handled()


func _unhandled_input(event: InputEvent):
	if event is InputEventMouseMotion:
		# Check if mouse is being dragged from a press
		if _mouse_pressed and not _is_being_dragged and is_player_card:
			var drag_distance = event.position.distance_to(_mouse_press_position)
			if drag_distance > 5.0:  # Threshold to start drag (5 pixels)
				_start_drag(_mouse_press_position)

		if _is_being_dragged:
			card_visual.global_position = event.position + _drag_offset
			get_tree().root.set_input_as_handled()
		elif is_player_card and not _is_being_dragged:
			# Enable hover effects for all player cards (both hand and play zone)
			var current_frame = Engine.get_process_frames()

			# Reset hover guard if we're in a new frame
			if _last_hover_frame != current_frame:
				_last_hover_frame = current_frame
				_hovered_card_this_frame = null

			# Check if this card is under the mouse
			var mouse_pos = get_viewport().get_mouse_position()
			# Use base card size (56x80) and multiply by card's current scale
			var base_card_size = Vector2(Constants.CARD_BASE_WIDTH, Constants.CARD_BASE_HEIGHT)
			var scaled_card_size = base_card_size * card_visual.scale
			var card_rect = Rect2(card_visual.global_position - scaled_card_size / 2.0, scaled_card_size)
			var is_under_mouse = card_rect.has_point(mouse_pos)

			# Check if this card is topmost under the mouse
			var is_topmost = _is_topmost_by_z_index() if is_under_mouse else false

			# Force deactivate if another card is hovered this frame
			if _hovered_card_this_frame != null and _hovered_card_this_frame != card_visual and _is_mouse_over:
				# Another card claimed hover - immediately deactivate
				_is_mouse_over = false
				_reset_shader_rotation()
				# Only reset scale and position for hand cards
				if _is_in_player_hand():
					_animate_scale_to(_base_scale)
					_animate_position_y_to(_base_y)
				_update_shadow_for_location()
			# Activate hover if no card claimed it yet and conditions are met
			elif is_under_mouse and is_topmost and not _is_mouse_over and _hovered_card_this_frame == null:
				# Claim hover for this frame
				_hovered_card_this_frame = card_visual
				_is_mouse_over = true
				# Only apply scale and vertical offset for player hand cards
				if _is_in_player_hand():
					_animate_scale_to(_base_scale * HOVER_SCALE_MULTIPLIER)
					_animate_position_y_to(_base_y + HOVER_VERTICAL_OFFSET)
				# Show shadow on hover
				if card_visual.has_method("set_shadow_visible"):
					card_visual.set_shadow_visible(true)
				_update_shader_rotation()
			# Continue hover - update shader rotation as mouse moves
			elif is_under_mouse and is_topmost and _is_mouse_over:
				# Reclaim hover for this frame if we were hovered and still are
				_hovered_card_this_frame = card_visual
				# Still hovered and topmost - update rotation
				_update_shader_rotation()
			# Deactivate hover if no longer under mouse or not topmost
			elif (not is_under_mouse or not is_topmost) and _is_mouse_over:
				# No longer valid for hover - deactivate
				_is_mouse_over = false
				_reset_shader_rotation()
				# Only reset scale and position for hand cards
				if _is_in_player_hand():
					_animate_scale_to(_base_scale)
					_animate_position_y_to(_base_y)
				# Update shadow based on location
				_update_shadow_for_location()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _is_being_dragged:
		_end_drag()
		get_tree().root.set_input_as_handled()


func _start_drag(mouse_pos: Vector2) -> void:
	_is_being_dragged = true
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


func _end_drag() -> void:
	_is_being_dragged = false
	_mouse_pressed = false  # Reset mouse state
	_drag_offset = Vector2.ZERO  # Clear drag offset to prevent further movement
	# Don't reset z_index here - let the parent (PlayerHand/PlayZone) manage it
	# when the card is repositioned via _update_z_indices() or similar
	drag_ended.emit(card_visual)


func _update_shader_rotation() -> void:
	"""Update shader rotation based on mouse position over card"""
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


func _animate_scale_to(target_scale: Vector2) -> void:
	"""Smoothly animate card scale to target"""
	# Kill previous scale tween if it exists
	if _scale_tween:
		_scale_tween.kill()

	# Create tween to smoothly interpolate to target scale
	_scale_tween = create_tween()
	_scale_tween.set_trans(Tween.TRANS_QUAD)
	_scale_tween.set_ease(Tween.EASE_OUT)
	_scale_tween.tween_property(card_visual, "scale", target_scale, SCALE_ANIMATION_DURATION)


func _animate_position_y_to(target_y: float) -> void:
	"""Smoothly animate card's Y position to target"""
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
		POSITION_ANIMATION_DURATION
	)


func _reset_shader_rotation() -> void:
	"""Smoothly reset shader rotation back to 0"""
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
		RESET_ANIMATION_DURATION
	)
	_reset_tween.tween_method(
		func(val: float) -> void: outer_sprite.material.set_shader_parameter("y_rot", val),
		current_y_rot,
		0.0,
		RESET_ANIMATION_DURATION
	)


func _update_shadow_for_location() -> void:
	"""Update shadow visibility based on card location - show by default in play zone, hide in hand unless hovering"""
	if not card_visual.has_method("set_shadow_visible"):
		return

	if _is_in_player_hand():
		# In hand: only show shadow if hovering
		card_visual.set_shadow_visible(_is_mouse_over)
	else:
		# In play zone or other location: always show shadow
		card_visual.set_shadow_visible(true)


func _is_in_player_hand() -> bool:
	"""Check if this card is in the player's hand"""
	var parent = card_visual.get_parent()
	return parent and parent.name == "PlayerHand"


func _is_topmost_by_z_index() -> bool:
	"""Check if this card has the highest z_index among ALL interactive cards under the mouse."""
	var mouse_pos = get_viewport().get_mouse_position()
	var cards_under_mouse: Array[Node] = []

	var player_ui = _find_player_ui()
	if not player_ui:
		return true # Should not happen, but default to true to avoid blocking input

	var player_hand = player_ui.get_node_or_null("PlayerHand")
	var play_zone = player_ui.get_node_or_null("PlayZone")

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


func _is_point_in_card(card: Node, point: Vector2) -> bool:
	"""Check if a global point is within the card's bounding rectangle."""
	var base_card_size = Vector2(Constants.CARD_BASE_WIDTH, Constants.CARD_BASE_HEIGHT)
	var scaled_card_size = base_card_size * card.scale
	var card_rect = Rect2(card.global_position - scaled_card_size / 2.0, scaled_card_size)
	return card_rect.has_point(point)


func _find_player_ui() -> Node:
	"""Find the PlayerUI node in the scene"""
	# Try to find it by walking up the tree
	var current = card_visual.get_parent()
	while current:
		if current.name == "PlayerUI":
			return current
		# Check if any sibling is PlayerUI
		var parent = current.get_parent()
		if parent:
			var player_ui = parent.get_node_or_null("PlayerUI")
			if player_ui:
				return player_ui
		current = parent
	return null


func _exit_tree() -> void:
	"""Clean up tweens when node is removed from tree"""
	if _reset_tween:
		_reset_tween.kill()
	if _scale_tween:
		_scale_tween.kill()
	if _position_tween:
		_position_tween.kill()
