extends Node2D
## GameScreen - Main game controller for card dealing and gameplay

var _player_hand: Node2D
var _play_zone: Node2D
var _cpu_hands: Array[Node2D] = []
var _game_manager: Node
var _is_dealing: bool = false
var _cards_dealt: int = 0  # Track how many cards have been dealt
var _prev_player_counts: Array[int] = [0, 0, 0, 0]  # Track previous card count for each player

# Player interaction tracking
var _dragging_card: Node = null
var _connected_cards: Array[Node] = []

@onready var _start_button: Button = $CanvasLayer/UIContainer/StartButton
@onready var _play_button: Button = $CanvasLayer/UIContainer/PlayButton
@onready var _pass_button: Button = $CanvasLayer/UIContainer/PassButton
@onready var _deck: Node2D = $Deck
@onready var _player_passed_label: Label = $CanvasLayer/UIContainer/PlayerPassedLabel
@onready var _cpu_top_passed_label: Label = $CanvasLayer/UIContainer/CPUTopPassedLabel
@onready var _cpu_left_passed_label: Label = $CanvasLayer/UIContainer/CPULeftPassedLabel
@onready var _cpu_right_passed_label: Label = $CanvasLayer/UIContainer/CPURightPassedLabel

func _ready() -> void:
	# Skip setup in editor
	if Engine.is_editor_hint():
		return

	# Get references to main components
	_player_hand = get_node_or_null("PlayerHand")
	_play_zone = get_node_or_null("PlayZone")
	_game_manager = GameManager

	# Set up reference between play zone and hand
	if _play_zone and _player_hand:
		_play_zone._player_hand = _player_hand

	# Get CPU hands
	var cpu_top = get_node_or_null("CPUHandTop")
	var cpu_left = get_node_or_null("CPUHandLeft")
	var cpu_right = get_node_or_null("CPUHandRight")

	if cpu_top:
		_cpu_hands.append(cpu_top)
	if cpu_left:
		_cpu_hands.append(cpu_left)
	if cpu_right:
		_cpu_hands.append(cpu_right)

	# Hide action buttons until game starts
	_hide_action_buttons()

	# Connect button signals
	if _start_button:
		_start_button.pressed.connect(_on_start_button_pressed)
	if _play_button:
		_play_button.pressed.connect(_on_play_pressed)
	if _pass_button:
		_pass_button.pressed.connect(_on_pass_pressed)

	# Connect deck click to dealing animation
	if _deck and _deck.has_signal("deal_started"):
		_deck.deal_started.connect(_on_deck_clicked)



func _on_start_button_pressed() -> void:
	_start_game_immediately()


func _start_game_immediately() -> void:
	"""Sets up and starts the game instantly without dealing animations."""
	# First, make sure GameManager has set up the game
	if _game_manager and _game_manager.has_method("setup_game"):
		_game_manager.setup_game()

	# Clear visual card state for fresh deal
	if _game_manager and _game_manager.has_method("clear_player_visual_cards"):
		_game_manager.clear_player_visual_cards()

	# Get player hands from GameManager
	var players = _game_manager.players
	if not players or players.size() < 4:
		push_error("GameManager did not set up players correctly.")
		return

	# Populate player's hand
	if _player_hand and _player_hand.has_method("clear_and_populate"):
		_player_hand.clear_and_populate(players[0].cards)
		# Register visual cards with GameManager
		for card_visual in _player_hand.get_children():
			if card_visual is Node2D and card_visual.has_method("set_card"):
				_game_manager.add_card_to_player_hand(card_visual)

	# Populate CPU hands
	# Player 1 = CPU Top, Player 2 = CPU Left, Player 3 = CPU Right
	var cpu_map = [0, 1, 2] # Map game manager player index to _cpu_hands index
	for i in range(1, 4):
		var cpu_hand_node = _cpu_hands[cpu_map[i-1]]
		if cpu_hand_node and cpu_hand_node.has_method("clear_and_set_count"):
			cpu_hand_node.clear_and_set_count(players[i].cards.size())

	# Hide deck and start button
	if _deck:
		_deck.visible = false
	if _start_button:
		_start_button.visible = false

	# Show play and pass buttons
	_show_action_buttons()

	# Connect drag listeners to all dealt cards
	if _player_hand:
		_connect_card_listeners(_player_hand.get_children())

	# Start the game - find starting player and begin turns
	if _game_manager and _game_manager.has_method("start_game"):
		_game_manager.start_game()

		# Connect to game manager signals
		if not _game_manager.turn_changed.is_connected(_on_turn_changed):
			_game_manager.turn_changed.connect(_on_turn_changed)
		if not _game_manager.player_played.is_connected(_on_player_played):
			_game_manager.player_played.connect(_on_player_played)
		if not _game_manager.player_passed.is_connected(_on_player_passed):
			_game_manager.player_passed.connect(_on_player_passed)
		if not _game_manager.round_started.is_connected(_on_round_started):
			_game_manager.round_started.connect(_on_round_started)
		if not _game_manager.game_ended.is_connected(_on_game_ended):
			_game_manager.game_ended.connect(_on_game_ended)


func _on_deck_clicked() -> void:
	"""Called when player clicks the deck to start dealing"""
	if _is_dealing:
		return

	# Hide the start button once dealing begins
	if _start_button:
		_start_button.visible = false

	_is_dealing = true
	await animate_deal_sequence()
	_is_dealing = false


func animate_deal_sequence() -> void:
	"""Animate dealing 13 cards to each of 4 players (52 total)"""
	# First, make sure GameManager has set up the game
	if _game_manager and _game_manager.has_method("setup_game"):
		_game_manager.setup_game()

	# Clear visual card state for fresh deal
	if _game_manager and _game_manager.has_method("clear_player_visual_cards"):
		_game_manager.clear_player_visual_cards()

	# Reset card tracking for this deal
	_cards_dealt = 0
	_prev_player_counts = [0, 0, 0, 0]

	# Animate dealing 13 rounds, each round deals to 4 players
	# Order: Bottom (Player), Left (CPU), Top (CPU), Right (CPU) - clockwise from bottom
	var deal_order = [0, 2, 1, 3]  # Player, Left, Top, Right
	var hand_positions = [
		_player_hand.global_position if _player_hand else Vector2(960, 1010),  # Player
		_cpu_hands[0].global_position if _cpu_hands.size() > 0 else Vector2(960, 100),  # CPU Top
		_cpu_hands[1].global_position if _cpu_hands.size() > 1 else Vector2(100, 540),  # CPU Left
		_cpu_hands[2].global_position if _cpu_hands.size() > 2 else Vector2(1820, 540),  # CPU Right
	]
	for round_num in range(13):
		# Deal to each player in clockwise order starting from bottom
		for order_idx in deal_order:
			# Animate one card visually to the target hand position
			await _deck.deal_card_animated(hand_positions[order_idx], order_idx)

			# Increment dealt count and populate only the cards that have been dealt
			_cards_dealt += 1
			_populate_dealt_cards(_cards_dealt)

			# Minimal delay between cards (2x faster)
			await get_tree().create_timer(0.015).timeout

	# After dealing is complete, clean up animated cards and hide the deck
	if _deck and _deck.has_method("cleanup_dealt_cards"):
		_deck.cleanup_dealt_cards()

	# Hide the deck so it doesn't intercept clicks
	if _deck:
		_deck.visible = false

	# Show play and pass buttons now that dealing is done
	_show_action_buttons()

	# Connect drag listeners to all dealt cards
	if _player_hand:
		_connect_card_listeners(_player_hand.get_children())

	# Start the game - find starting player and begin turns
	if _game_manager and _game_manager.has_method("start_game"):
		_game_manager.start_game()

		# Connect to game manager signals
		if not _game_manager.turn_changed.is_connected(_on_turn_changed):
			_game_manager.turn_changed.connect(_on_turn_changed)
		if not _game_manager.player_played.is_connected(_on_player_played):
			_game_manager.player_played.connect(_on_player_played)
		if not _game_manager.player_passed.is_connected(_on_player_passed):
			_game_manager.player_passed.connect(_on_player_passed)
		if not _game_manager.round_started.is_connected(_on_round_started):
			_game_manager.round_started.connect(_on_round_started)
		if not _game_manager.game_ended.is_connected(_on_game_ended):
			_game_manager.game_ended.connect(_on_game_ended)


func _populate_dealt_cards(num_cards_dealt: int) -> void:
	"""Add new cards to hands incrementally (only new cards, not rebuilding)"""
	if not _game_manager:
		return

	# Get the players array from GameManager
	var players = _game_manager.players

	if not players or players.size() < 4:
		return

	# Count cards dealt to each player
	var player_counts: Array[int] = [0, 0, 0, 0]
	for card_idx in range(num_cards_dealt):
		var player_idx = card_idx % 4
		player_counts[player_idx] += 1

	# Add new cards to player hand if count increased
	if _player_hand and _player_hand.has_method("add_card"):
		for i in range(_prev_player_counts[0], player_counts[0]):
			var card_visual = _player_hand.add_card(players[0].cards[i])
			# Register with GameManager so it knows about the visual card
			if _game_manager and card_visual:
				_game_manager.add_card_to_player_hand(card_visual)

	# Add new cards to CPU hands if count increased
	for player_idx in range(1, 4):
		var cpu_hand_idx = player_idx - 1
		if cpu_hand_idx < _cpu_hands.size():
			if _cpu_hands[cpu_hand_idx].has_method("add_card"):
				for i in range(_prev_player_counts[player_idx], player_counts[player_idx]):
					_cpu_hands[cpu_hand_idx].add_card()

	# Update previous counts for next call
	_prev_player_counts = player_counts


func _hide_action_buttons() -> void:
	"""Hide play and pass buttons during dealing"""
	if _play_button:
		_play_button.visible = false
	if _pass_button:
		_pass_button.visible = false


func _show_action_buttons() -> void:
	"""Show play and pass buttons after dealing is complete"""
	if _play_button:
		_play_button.visible = true
	if _pass_button:
		_pass_button.visible = true


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


func _on_turn_changed(player_idx: int) -> void:
	"""Called when game turn changes - enable/disable buttons based on turn"""
	# Keep buttons visible but disable them when it's not player 0's turn
	var is_player_turn = (player_idx == 0)

	# Don't enable buttons if player has already passed
	var has_passed = _game_manager.has_player_passed() if _game_manager else false

	if _play_button:
		_play_button.disabled = !is_player_turn or has_passed
	if _pass_button:
		_pass_button.disabled = !is_player_turn or has_passed


func _on_player_played(player_idx: int, cards: Array, _is_set_card: bool) -> void:
	"""Called when a player (human or AI) plays cards"""
	# Only handle CPU players (player 0 handles their own visuals via drag/drop)
	if player_idx == 0:
		return

	# Player 0 = human (no action needed)
	# Player 1 = CPU Top, Player 2 = CPU Left, Player 3 = CPU Right
	var cpu_hand_idx = player_idx - 1
	if cpu_hand_idx >= _cpu_hands.size():
		return

	var cpu_hand = _cpu_hands[cpu_hand_idx]
	var num_cards = cards.size()

	# Get the play zone
	if not _play_zone:
		return

	# Take the last N cards from the CPU's hand visual
	var cards_to_move: Array[Node] = []
	for i in range(num_cards):
		if cpu_hand._cards.size() > 0:
			var card_visual = cpu_hand._cards.pop_back()
			# Set the card data to the visual node
			if i < cards.size() and card_visual.has_method("set_card"):
				card_visual.set_card(cards[i])
			# Show card face (not back) when played
			if card_visual.has_method("set_show_back"):
				card_visual.set_show_back(false)
			cards_to_move.append(card_visual)

	# Move cards to play zone - always go through atk → set flow
	# Add as atk cards first (handles reparenting)
	for card in cards_to_move:
		_play_zone.add_atk_card(card)

	# Commit them to set position with animation
	await _play_zone.commit_atk_to_set()

	# Rearrange CPU hand
	if cpu_hand.has_method("_arrange_cards"):
		cpu_hand._arrange_cards()


func _on_player_passed(player_idx: int) -> void:
	"""Called when a player passes - show PASSED indicator"""
	print("[GameScreen] Player %d passed - showing indicator" % player_idx)
	match player_idx:
		0:
			# Human player
			if _player_passed_label:
				_player_passed_label.visible = true
				print("[GameScreen] Player PASSED label visible")
		1:
			# CPU Top
			if _cpu_top_passed_label:
				_cpu_top_passed_label.visible = true
				print("[GameScreen] CPU Top PASSED label visible")
		2:
			# CPU Left
			if _cpu_left_passed_label:
				_cpu_left_passed_label.visible = true
				print("[GameScreen] CPU Left PASSED label visible")
		3:
			# CPU Right
			if _cpu_right_passed_label:
				_cpu_right_passed_label.visible = true
				print("[GameScreen] CPU Right PASSED label visible")


func _on_round_started() -> void:
	"""Called when a new round starts - hide all PASSED indicators"""
	print("[GameScreen] Round started - hiding all PASSED indicators")
	if _player_passed_label:
		_player_passed_label.visible = false
	if _cpu_top_passed_label:
		_cpu_top_passed_label.visible = false
	if _cpu_left_passed_label:
		_cpu_left_passed_label.visible = false
	if _cpu_right_passed_label:
		_cpu_right_passed_label.visible = false

	# Reset play zone to show placeholder card
	if _play_zone and _play_zone.has_method("reset_to_placeholder"):
		_play_zone.reset_to_placeholder()


func _on_game_ended(winner_idx: int) -> void:
	"""Called when game ends"""
	_hide_action_buttons()
	print("Game ended! Player %d wins!" % winner_idx)
