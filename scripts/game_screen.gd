extends Node2D
## GameScreen - Main game controller for card dealing and gameplay

var _player_ui: Node2D
var _player_hand: Node2D
var _cpu_hands: Array[Node2D] = []
var _game_manager: Node
var _is_dealing: bool = false
var _cards_dealt: int = 0  # Track how many cards have been dealt
var _prev_player_counts: Array[int] = [0, 0, 0, 0]  # Track previous card count for each player

@onready var _start_button: Button = $CanvasLayer/UIContainer/StartButton
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
	_player_ui = get_node_or_null("PlayerUI")
	_game_manager = GameManager

	if _player_ui:
		_player_hand = _player_ui.get_node_or_null("PlayerHand")

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

	if _start_button:
		_start_button.pressed.connect(_on_start_button_pressed)

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
	if _player_ui and _player_hand and _player_ui.has_method("_connect_card_listeners"):
		_player_ui._connect_card_listeners(_player_hand.get_children())

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
	if _player_ui and _player_hand and _player_ui.has_method("_connect_card_listeners"):
		_player_ui._connect_card_listeners(_player_hand.get_children())

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
	if _player_ui:
		var control_ui = _player_ui.get_node_or_null("ControlUI")
		if control_ui:
			control_ui.visible = false


func _show_action_buttons() -> void:
	"""Show play and pass buttons after dealing is complete"""
	if _player_ui:
		var control_ui = _player_ui.get_node_or_null("ControlUI")
		if control_ui:
			control_ui.visible = true


func _on_turn_changed(player_idx: int) -> void:
	"""Called when game turn changes - enable/disable buttons based on turn"""
	if _player_ui:
		var control_ui = _player_ui.get_node_or_null("ControlUI")
		if control_ui:
			# Keep buttons visible but disable them when it's not player 0's turn
			var vbox = control_ui.get_node_or_null("VBoxContainer")
			if vbox:
				var hbox = vbox.get_node_or_null("HBoxContainer")
				if hbox:
					var play_button = hbox.get_node_or_null("PlayButton")
					var pass_button = hbox.get_node_or_null("PassButton")
					var is_player_turn = (player_idx == 0)

					# Don't enable buttons if player has already passed
					var has_passed = _game_manager.has_player_passed() if _game_manager else false

					if play_button:
						play_button.disabled = !is_player_turn or has_passed
					if pass_button:
						pass_button.disabled = !is_player_turn or has_passed


func _on_player_played(player_idx: int, cards: Array, is_set_card: bool) -> void:
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
	var play_zone = _player_ui.get_node_or_null("PlayZone") if _player_ui else null
	if not play_zone:
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

	# Move cards to play zone
	if is_set_card:
		# First play of round - use initialize_with_cards which handles reparenting
		play_zone.initialize_with_cards(cards_to_move)
	else:
		# Response play - add as atk cards (add_atk_card handles reparenting)
		for card in cards_to_move:
			play_zone.add_atk_card(card)
		# Immediately commit them to set position
		await play_zone.commit_atk_to_set()

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


func _on_game_ended(winner_idx: int) -> void:
	"""Called when game ends"""
	_hide_action_buttons()
	print("Game ended! Player %d wins!" % winner_idx)
