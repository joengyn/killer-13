extends Node
class_name CardDragHandler

## Emitted when a card is dragged out of the hand bounds
signal card_dragged_out(card_visual: Node)

## Emitted when a card is clicked
signal card_clicked(card_visual: Node)

## Emitted when a card drag starts
signal card_drag_started(card_visual: Node)

## Emitted when auto-sorting is disabled due to manual reordering
signal auto_sort_disabled

# Drag preview state tracking
var _dragged_card: Node = null
var _preview_insert_index: int = -1
var _preview_tween: Tween = null
var _last_preview_update: float = 0.0
const PREVIEW_UPDATE_INTERVAL: float = 0.05  # 20fps

# Reference to the parent PlayerHand node
var _player_hand_node: Node2D = null

func _ready() -> void:
	_player_hand_node = get_parent()
	if not _player_hand_node or not _player_hand_node is PlayerHand:
		push_error("CardDragHandler must be a child of a PlayerHand node.")
		set_process(false) # Disable processing if parent is not PlayerHand

func connect_card_drag_listeners(card: Node):
	var interaction = card.get_node_or_null("Interaction")
	if interaction:
		# Connect drag signals
		if interaction.has_signal("drag_ended"):
			if interaction.drag_ended.is_connected(_on_card_drag_ended):
				interaction.drag_ended.disconnect(_on_card_drag_ended)
			interaction.drag_ended.connect(_on_card_drag_ended)

		# Connect click signals
		if interaction.has_signal("card_clicked"):
			if interaction.card_clicked.is_connected(_on_card_clicked):
				interaction.card_clicked.disconnect(_on_card_clicked)
			interaction.card_clicked.connect(_on_card_clicked)

		# Connect drag started signals
		if interaction.has_signal("drag_started"):
			if interaction.drag_started.is_connected(_on_card_drag_started):
				interaction.drag_started.disconnect(_on_card_drag_started)
			interaction.drag_started.connect(_on_card_drag_started)

		# Connect drag position updated signals
		if interaction.has_signal("drag_position_updated"):
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

	var cards_in_hand = _player_hand_node.get_cards() # Get current cards from PlayerHand

	# Check if this card (which was in the hand) was dragged outside hand bounds
	var card_in_hand = card_visual in cards_in_hand
	if card_in_hand or was_dragged_card:
		var card_local_pos = card_visual.global_position - _player_hand_node.global_position
		var hand_bounds = _player_hand_node.get_hand_bounds() # Use PlayerHand's public method

		var interaction = card_visual.get_node_or_null("Interaction")
		var is_outside_bounds = not hand_bounds.has_point(card_local_pos)

		if is_outside_bounds and interaction and interaction.can_move_out_of_hand:
			# Card was in hand and is now outside hand bounds - handle drag-out
			# First, ensure it's back in the array if it was removed during drag
			if was_dragged_card and not card_in_hand:
				if final_preview_index >= 0 and final_preview_index <= cards_in_hand.size():
					_player_hand_node.insert_card_visual(card_visual, final_preview_index)
				else:
					_player_hand_node.add_card_visual(card_visual)
			_handle_card_dragged_out(card_visual)
		else:
			# Card ended drag within hand bounds OR outside bounds but can't be played
			# Either way, finalize the reorder to snap card back into valid hand position
			_finalize_reorder(card_visual)
	else:
		# Card was not in hand (must be in play zone)
		pass

func _on_card_clicked(card_visual: Node):
	## Handle when a card in hand is clicked - shortcut for playing the card
	##
	## Clicking a card is equivalent to dragging it out of the hand. This provides
	## a quick way for players to play cards without needing to drag.
	##
	## @param card_visual: The card that was clicked
	var cards_in_hand = _player_hand_node.get_cards()
	if card_visual in cards_in_hand:
		var interaction = card_visual.get_node_or_null("Interaction")
		if interaction and interaction.can_move_out_of_hand:
			# Card is in hand and allowed to be played, so emit the signal
			card_clicked.emit(card_visual)
	# else: Card is not in hand (probably in PlayZone already)
	# Do nothing here, as PlayZone handles clicks for atk cards

func _on_card_drag_started(card_visual: Node):
	var cards_in_hand = _player_hand_node.get_cards()
	if card_visual in cards_in_hand:
		_dragged_card = card_visual
		_player_hand_node.remove_card_visual(card_visual) # Use PlayerHand's public method

	card_drag_started.emit(card_visual)

func _handle_card_dragged_out(card_visual: Node):
	card_dragged_out.emit(card_visual)

func _get_card_description(card_visual: Node) -> String:
	if card_visual.has_method("get_card"):
		var card_data = card_visual.get_card()
		if card_data and card_data.has_method("to_string"):
			return card_data.to_string()
		elif card_data:
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
	var card_description = _get_card_description(card_visual)
	return action_type + " - " + card_description

func _calculate_insertion_index(card_visual: Node) -> int:
	var cards_in_hand = _player_hand_node.get_cards()
	if cards_in_hand.size() == 0:
		return 0

	var card_local_x = card_visual.global_position.x - _player_hand_node.global_position.x

	if cards_in_hand.size() == 1:
		var first_card_x = cards_in_hand[0].position.x
		if card_local_x < first_card_x:
			return 0
		else:
			return 1

	for idx in range(cards_in_hand.size() - 1):
		var current_card_x = cards_in_hand[idx].position.x
		var next_card_x = cards_in_hand[idx + 1].position.x

		var midpoint_x = (current_card_x + next_card_x) / 2.0

		if card_local_x < midpoint_x:
			return idx

	return cards_in_hand.size()

func _find_sorted_insertion_index(new_card_visual: Node) -> int:
	var cards_in_hand = _player_hand_node.get_cards()
	for i in range(cards_in_hand.size()):
		var existing_card_visual = cards_in_hand[i]
		if Card.compare_card_nodes_lt(new_card_visual, existing_card_visual):
			return i
	return cards_in_hand.size()

func _finalize_reorder(card_visual: Node) -> void:
	auto_sort_disabled.emit()

	var new_idx = _calculate_insertion_index(card_visual)
	_player_hand_node.insert_card_visual(card_visual, new_idx)

	var interaction = card_visual.get_node_or_null("Interaction")
	if interaction:
		if interaction.has_method("reset_hover_state"):
			interaction.reset_hover_state()

	_player_hand_node.rearrange_cards_in_hand()

func _on_card_drag_position_updated(card: Node) -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_preview_update < PREVIEW_UPDATE_INTERVAL:
		return
	_last_preview_update = now
	_update_drag_preview(card)

func _calculate_preview_index(drag_x_position: float) -> int:
	var cards_in_hand = _player_hand_node.get_cards()
	if cards_in_hand.size() == 0:
		return 0

	var card_local_x = drag_x_position - _player_hand_node.global_position.x

	if cards_in_hand.size() == 1:
		var first_card_x = cards_in_hand[0].position.x
		if card_local_x < first_card_x:
			return 0
		else:
			return 1

	for idx in range(cards_in_hand.size() - 1):
		var current_card_x = cards_in_hand[idx].position.x
		var next_card_x = cards_in_hand[idx + 1].position.x

		var midpoint_x = (current_card_x + next_card_x) / 2.0

		if card_local_x < midpoint_x:
			return idx

	return cards_in_hand.size()

func _update_drag_preview(card: Node) -> void:
	var card_local_pos = card.global_position - _player_hand_node.global_position
	var hand_bounds = _player_hand_node.get_hand_bounds() # Use PlayerHand's public method
	var is_in_bounds = hand_bounds.has_point(card_local_pos)

	if not is_in_bounds:
		if _preview_insert_index >= 0:
			_preview_insert_index = -1
			_animate_cards_to_preview(-1)
	else:
		var preview_idx = _calculate_insertion_index(card)

		if preview_idx != _preview_insert_index:
			_preview_insert_index = preview_idx
			_animate_cards_to_preview(preview_idx)

func _animate_cards_to_preview(preview_index: int) -> void:
	if _preview_tween:
		_preview_tween.kill()

	var cards_in_hand = _player_hand_node.get_cards()

	if preview_index < 0:
		var card_count = cards_in_hand.size()
		var total_width = (card_count - 1) * GameConstants.HAND_CARD_SPACING
		var start_x = -total_width / 2.0

		_preview_tween = _player_hand_node.create_tween()
		_preview_tween.set_trans(Tween.TRANS_QUAD)
		_preview_tween.set_ease(Tween.EASE_OUT)
		_preview_tween.set_parallel(true)

		for idx in range(card_count):
			var target_x = start_x + (idx * GameConstants.HAND_CARD_SPACING)
			_preview_tween.tween_property(cards_in_hand[idx], "position:x", target_x, 0.15)
		return

	_preview_tween = _player_hand_node.create_tween()
	_preview_tween.set_trans(Tween.TRANS_QUAD)
	_preview_tween.set_ease(Tween.EASE_OUT)
	_preview_tween.set_parallel(true)

	var total_cards = cards_in_hand.size()
	var current_card_offset_idx = 0

	var total_width_with_gap = (total_cards - 1) * GameConstants.HAND_CARD_SPACING + (GameConstants.HAND_PREVIEW_GAP - GameConstants.HAND_CARD_SPACING)
	var start_x_with_gap = -total_width_with_gap / 2.0

	for idx in range(total_cards):
		var target_x = start_x_with_gap + (current_card_offset_idx * GameConstants.HAND_CARD_SPACING)
		if idx == preview_index:
			target_x += (GameConstants.HAND_PREVIEW_GAP - GameConstants.HAND_CARD_SPACING)

		_preview_tween.tween_property(cards_in_hand[idx], "position:x", target_x, 0.15)
		current_card_offset_idx += 1

func reset_drag_state() -> void:
	_dragged_card = null
	if _preview_tween:
		_preview_tween.kill()
		_preview_tween = null
	_preview_insert_index = -1
