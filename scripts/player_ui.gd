extends Node2D
## PlayerUI - Coordinates player hand, play zone, buttons, and all player actions

var _player_hand: Node2D = null
var _play_zone: Node2D = null
var _dragging_card: Node = null
var _play_button: Button = null
var _pass_button: Button = null
var _connected_cards: Array[Node] = []

func _ready() -> void:
	# Find child components
	_player_hand = get_node_or_null("PlayerHand")
	_play_zone = get_node_or_null("PlayZone")

	if not _player_hand:
		push_error("PlayerUI: PlayerHand not found!")
		return

	if not _play_zone:
		push_error("PlayerUI: PlayZone not found!")
		return

	# Set up reference between play zone and hand
	_play_zone._player_hand = _player_hand

	# Only connect drag events at runtime (not in editor)
	if not Engine.is_editor_hint():
		# Connect to all card drag events
		_connect_card_listeners(_player_hand.get_children())

		# Connect button signals
		_connect_button_signals()


func _connect_button_signals() -> void:
	"""Connect button signal handlers"""
	_play_button = get_node_or_null("ControlUI/VBoxContainer/HBoxContainer/PlayButton")
	_pass_button = get_node_or_null("ControlUI/VBoxContainer/HBoxContainer/PassButton")

	if _play_button:
		_play_button.pressed.connect(_on_play_pressed)

	if _pass_button:
		_pass_button.pressed.connect(_on_pass_pressed)


func _on_play_pressed() -> void:
	"""Handle Play button press - submit atk cards to game manager"""
	var atk_cards = get_cards_in_play()

	if atk_cards.is_empty():
		print("No cards to play")
		if _play_button:
			_play_button.release_focus()
		return

	# Convert visual cards to Card data for game logic
	var card_data: Array[Card] = []
	for card_visual in atk_cards:
		# CardVisual has a 'card' property of type Card
		if card_visual.card:
			card_data.append(card_visual.card)

	# Submit play to game manager
	var success = GameManager.execute_player_play(card_data)

	if success:
		# Play was valid - animate atk cards to set cards
		await _play_zone.commit_atk_to_set()
		# Update GameManager state: atk cards are now set cards
		GameManager.commit_atk_cards_to_set()
	else:
		# Play was invalid - keep atk cards in zone for adjustment
		print("Invalid play - check console for details")

	# Release focus from button
	if _play_button:
		_play_button.release_focus()


func _on_pass_pressed() -> void:
	"""Handle Pass button press - return atk cards to hand and pass turn"""
	print("Pass button pressed")

	# Return all atk cards back to hand (use GameManager as source of truth)
	var atk_cards = GameManager.get_player_atk_cards()
	for card in atk_cards:
		_move_card_to_hand(card)

	# Notify game manager
	GameManager.pass_turn()

	# Release focus from button
	if _pass_button:
		_pass_button.release_focus()


func _connect_card_listeners(cards: Array) -> void:
	"""Connect drag and click listeners to all cards - safe to call multiple times"""
	for card in cards:
		# Skip if already connected to this card
		if card in _connected_cards:
			continue

		var interaction = card.get_node_or_null("Interaction")
		if interaction:
			# Connect drag signals
			interaction.drag_started.connect(_on_card_drag_started)
			interaction.drag_ended.connect(_on_card_drag_ended)
			# Connect click signal
			interaction.card_clicked.connect(_on_card_clicked)

			# Track that we've connected this card
			_connected_cards.append(card)


func _on_card_clicked(card_visual: Node) -> void:
	"""Handle when a card is clicked - toggle between hand and play zone"""
	# Query GameManager for authoritative card location
	var card_location = GameManager.get_card_location(card_visual)

	if card_location == "hand":
		# Move from hand to play zone
		_move_card_to_play_zone(card_visual)
	elif card_location == "atk":
		# Move from play zone back to hand
		_move_card_to_hand(card_visual)
	else:
		# Card is in an unexpected state
		push_warning("Card click on card in location: %s" % card_location)

	# Reset hover effects after moving
	var interaction = card_visual.get_node_or_null("Interaction")
	if interaction and interaction.has_method("reset_hover_state"):
		interaction.reset_hover_state()


func _on_card_drag_started(card_visual: Node) -> void:
	"""Handle when a card drag starts"""
	_dragging_card = card_visual
	# Can add visual feedback here (highlight valid drop zones, etc.)


func _on_card_drag_ended(card_visual: Node) -> void:
	"""Handle when a card drag ends - route to appropriate zone"""
	_dragging_card = null

	# Query GameManager for authoritative card location
	var card_location = GameManager.get_card_location(card_visual)

	if card_location == "hand":
		# Check if card left hand bounds
		var hand_bounds = _player_hand._get_hand_bounds()
		var card_local_pos = card_visual.global_position - _player_hand.global_position

		if not hand_bounds.has_point(card_local_pos):
			# Card moved outside hand - send to play zone as atk card
			_move_card_to_play_zone(card_visual)
	elif card_location == "atk":
		# Check if card should be returned to hand (either inside hand bounds or outside play zone)
		var hand_bounds = _player_hand._get_hand_bounds()
		var play_bounds = _play_zone._get_bounds_rect()

		var card_local_pos = card_visual.global_position - _player_hand.global_position
		var card_local_pos_play = card_visual.global_position - _play_zone.global_position

		if hand_bounds.has_point(card_local_pos):
			# Card moved back into hand - return to hand
			_move_card_to_hand(card_visual)
		elif not play_bounds.has_point(card_local_pos_play):
			# Card moved outside play zone bounds - return to hand
			_move_card_to_hand(card_visual)
	else:
		# Card is in an unexpected state
		push_warning("Card drag ended with unexpected location: %s" % card_location)


func _move_card_to_play_zone(card: Node) -> void:
	"""Move a card from hand to play zone as an atk card"""
	# Update GameManager state (source of truth)
	if not GameManager.move_card_to_atk_zone(card):
		return

	# CRITICAL: Remove from PlayerHand's local tracking array
	# Otherwise the hand thinks the card is still there when arranging
	_player_hand._cards_in_hand.erase(card)
	_player_hand._update_z_indices()

	# Update visual: hand arranges after card removal
	_player_hand._arrange_cards()

	# Add to play zone as atk card (visual reparenting)
	_play_zone.add_atk_card(card)

	# Ensure click listener is still connected
	var interaction = card.get_node_or_null("Interaction")
	if interaction and not interaction.card_clicked.is_connected(_on_card_clicked):
		interaction.card_clicked.connect(_on_card_clicked)


func _move_card_to_hand(card: Node) -> void:
	"""Move a card from play zone atk cards back to hand"""
	# Update GameManager state (source of truth)
	if not GameManager.move_card_to_hand(card):
		return

	# Remove from play zone atk cards (this handles reparenting and scaling)
	_play_zone.remove_atk_card(card, _player_hand)

	# Add back to hand (this handles positioning and z_indices)
	_player_hand._add_card_back(card)

	# Ensure listeners are connected and re-enable interaction
	var interaction = card.get_node_or_null("Interaction")
	if interaction:
		if not interaction.drag_ended.is_connected(_on_card_drag_ended):
			interaction.drag_ended.connect(_on_card_drag_ended)
		if not interaction.card_clicked.is_connected(_on_card_clicked):
			interaction.card_clicked.connect(_on_card_clicked)
		# Re-enable interaction for cards returning to hand
		interaction.is_player_card = true

	card.set_shadow_visible(false)


func get_cards_in_hand() -> Array:
	"""Get all cards currently in hand"""
	return GameManager.get_player_hand_cards()


func get_cards_in_play() -> Array[Node]:
	"""Get all atk cards currently being played"""
	return GameManager.get_player_atk_cards()
