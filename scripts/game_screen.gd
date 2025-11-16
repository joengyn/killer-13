extends Node2D
## GameScreen - Main game controller for card dealing and gameplay

# Scene references (use @onready for scene childern)
@onready var _player_hand: Node2D = $PlayerHand
@onready var _cpu_hand_left: Node2D = $CPUHandLeft
@onready var _cpu_hand_top: Node2D = $CPUHandTop
@onready var _cpu_hand_right: Node2D = $CPUHandRight
@onready var _play_zone: Node2D = $PlayZone
@onready var _deck: Node2D = $Deck
@onready var _start_button: Button = $CanvasLayer/UIContainer/StartButton
@onready var _play_button: Button = $CanvasLayer/UIContainer/PlayButton
@onready var _pass_button: Button = $CanvasLayer/UIContainer/PassButton
@onready var _round_tracker: Control = $CanvasLayer/UIContainer/RoundTracker
@onready var _player_passed_label: Label = $CanvasLayer/UIContainer/PlayerPassedLabel
@onready var _cpu_top_passed_label: Label = $CanvasLayer/UIContainer/CPUTopPassedLabel
@onready var _cpu_left_passed_label: Label = $CanvasLayer/UIContainer/CPULeftPassedLabel
@onready var _cpu_right_passed_label: Label = $CanvasLayer/UIContainer/CPURightPassedLabel
@onready var _invalid_play_label: Label = $CanvasLayer/UIContainer/InvalidPlayLabel
@onready var _game_over_label: Label = $CanvasLayer/UIContainer/GameOverModal/VBoxContainer/GameOverLabel
@onready var _game_over_modal: PanelContainer = $CanvasLayer/UIContainer/GameOverModal

# Runtime data (NOT @onready)
var _game_manager = GameManager # Direct reference to autoload
var _is_dealing: bool = false
var _cards_dealt: int = 0
var _cpu_hands: Array[Node2D] = []
var _dragging_card: Node = null
var _prev_player_counts: Array[int] = [0, 0, 0, 0]  # TODO remove this

# Signals
signal ai_action_complete(player_idx: int, cards_played: Array)
signal player_action_complete
signal card_play_visual_complete(player_index: int, cards: Array)


func _ready() -> void:
	# Skip setup in editor
	if Engine.is_editor_hint():
		return


	# Connect GameScreen signals to GameManager handlers
	# This is the reliable way to connect to a singleton
	if _game_manager:
		if not ai_action_complete.is_connected(_game_manager._on_ai_action_complete):
			ai_action_complete.connect(_game_manager._on_ai_action_complete)
		if not player_action_complete.is_connected(_game_manager._on_player_action_complete):
			player_action_complete.connect(_game_manager._on_player_action_complete)


	# Connect to PlayerHand's card signals
	if _player_hand:
		if _player_hand.has_signal("card_dragged_out"):
			_player_hand.card_dragged_out.connect(_on_card_dragged_out_from_hand)
		if _player_hand.has_signal("card_clicked"):
			_player_hand.card_clicked.connect(_on_card_clicked)
		if _player_hand.has_signal("card_drag_started"):
			_player_hand.card_drag_started.connect(_on_card_drag_started)


	# Connect to PlayZone's atk card signals
	if _play_zone:
		if _play_zone.has_signal("atk_card_clicked"):
			_play_zone.atk_card_clicked.connect(_on_card_clicked)
		if _play_zone.has_signal("atk_card_dragged_out"):
			_play_zone.atk_card_dragged_out.connect(_on_card_returned_to_hand)
		if _play_zone.has_signal("atk_card_drag_started"):
			_play_zone.atk_card_drag_started.connect(_on_card_drag_started)

	# Populate CPU hands array in correct order (left=1, top=2, right=3)
	_cpu_hands = [_cpu_hand_left, _cpu_hand_top, _cpu_hand_right]


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


	# Hide invalid play label initially
	if _invalid_play_label:
		_invalid_play_label.visible = false

	add_to_group("game_screen")

	# Connect RoundTracker to card play visual complete signal
	if _round_tracker:
		card_play_visual_complete.connect(_round_tracker._on_card_play_visual_complete)



func _on_start_button_pressed() -> void:
	_start_game_immediately()


func _start_game_immediately() -> void:
	"""Sets up and starts the game instantly without dealing animations."""
	# First, make sure GameManager has set up the game
	_game_manager.setup_game(true)

	# Get player hands from GameManager
	var players = _game_manager.players
	if not players or players.size() < 4:
		# push_error("GameManager did not set up players correctly.")
		return

	# Populate player's hand
	if _player_hand and _player_hand.has_method("clear_and_populate"):
		_player_hand.clear_and_populate(players[0].cards)

	# Populate CPU hands
	# Player 1 = CPU Left, Player 2 = CPU Top, Player 3 = CPU Right
	for i in range(1, 4):
		var cpu_hand_node = _cpu_hands[i-1]
		if cpu_hand_node and cpu_hand_node.has_method("clear_and_set_count"):
			cpu_hand_node.clear_and_set_count(players[i].cards.size())

	# Hide deck and start button
	if _deck:
		_deck.visible = false
	if _start_button:
		_start_button.visible = false

	_show_action_buttons()


	if _game_manager:
		_connect_game_manager_signals()
		_game_manager.start_game()


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
	# Set up the game (this populates the players array in the GameManager)
	# For dealing animation, don't emit signals as cards are populated incrementally
	_game_manager.setup_game(false)

	# Reset card tracking for this deal
	_cards_dealt = 0
	_prev_player_counts = [0, 0, 0, 0]

	# Animate dealing 13 rounds, each round deals to 4 players
	# Order: Bottom (Player), Left (CPU), Top (CPU), Right (CPU) - clockwise from bottom
	var deal_order = [0, 1, 2, 3]  # Player, Left, Top, Right
	var player_pos = Vector2(960, 1010)
	if _player_hand:
		player_pos = _player_hand.global_position

	var cpu_top_pos = Vector2(960, 100)
	if _cpu_hands.size() > 0:
		cpu_top_pos = _cpu_hands[0].global_position

	var cpu_left_pos = Vector2(100, 540)
	if _cpu_hands.size() > 1:
		cpu_left_pos = _cpu_hands[1].global_position

	var cpu_right_pos = Vector2(1820, 540)
	if _cpu_hands.size() > 2:
		cpu_right_pos = _cpu_hands[2].global_position

	var hand_positions = [player_pos, cpu_top_pos, cpu_left_pos, cpu_right_pos]
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

	_show_action_buttons()


	if _game_manager:
		_connect_game_manager_signals()
		_game_manager.start_game()


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





func _on_play_pressed() -> void:
	"""Handle Play button press - submit atk cards to game manager"""
	var atk_cards = get_cards_in_play()

	if atk_cards.is_empty():
		if _play_button:
			_play_button.release_focus()
		return

	# Disable buttons immediately to prevent race conditions
	_play_button.disabled = true
	_pass_button.disabled = true

	# Convert visual cards to Card data for game logic
	var card_data: Array[Card] = []
	for card_visual in atk_cards:
		if card_visual.card:
			card_data.append(card_visual.card)

	# Submit play to game manager
	var success = GameManager.execute_player_play(card_data)

	if success:
		# Play was valid - animate atk cards to set cards
		await _play_zone.commit_atk_to_set()

		# Emit signal that card play visuals are complete for human player
		card_play_visual_complete.emit(0, card_data)

		# Tell GameManager the player's action is visually complete
		player_action_complete.emit()
	else:
		# Play was invalid - re-enable buttons so player can correct their move
		if _game_manager.has_player_passed() == false:
			_play_button.disabled = false
			_pass_button.disabled = false
		pass

	if _play_button:
		_play_button.release_focus()


func _on_pass_pressed() -> void:
	"""Handle Pass button press - return atk cards to hand and pass turn"""
	# Disable buttons immediately to prevent race conditions
	_play_button.disabled = true
	_pass_button.disabled = true

	var atk_cards = _play_zone.get_atk_cards()
	for card in atk_cards:
		_move_card_to_hand(card)

	# GameManager.pass_turn() should return instantly now
	var pass_result = GameManager.pass_turn()

	if pass_result == "pass_ok":
		# Tell GameManager the player's action is visually complete
		player_action_complete.emit()
	elif pass_result == "round_ended":
		# Do nothing. The round_ended signal is already fired.
		# GameScreen will handle the reset after a delay.
		pass
	else: # "invalid"
		# Invalid pass attempt - re-enable buttons
		if _game_manager.has_player_passed() == false:
			_play_button.disabled = false
			_pass_button.disabled = false
		pass

	if _pass_button:
		_pass_button.release_focus()


func _show_pass_label_for_player(player_idx: int) -> void:
	match player_idx:
		0:
			if _player_passed_label:
				_player_passed_label.visible = true
		1:
			if _cpu_left_passed_label:
				_cpu_left_passed_label.visible = true
		2:
			if _cpu_top_passed_label:
				_cpu_top_passed_label.visible = true
		3:
			if _cpu_right_passed_label:
				_cpu_right_passed_label.visible = true


func _on_card_clicked(card_visual: Node) -> void:
	"""Handle when a card is clicked - toggle between hand and play zone"""
	if _player_hand.has_card(card_visual):
		# Move from hand to play zone
		_move_card_to_play_zone(card_visual)
	elif _play_zone.has_atk_card(card_visual):
		# Move from play zone back to hand
		_move_card_to_hand(card_visual)
	else:
		# Card is in an unexpected state
		pass

	# Reset hover effects after moving
	var interaction = card_visual.get_node_or_null("Interaction")
	if interaction and interaction.has_method("reset_hover_state"):
		interaction.reset_hover_state()


func _on_card_drag_started(card_visual: Node) -> void:
	"""Handle when a card drag starts"""
	_dragging_card = card_visual
	# Can add visual feedback here (highlight valid drop zones, etc.)





func _on_card_dragged_out_from_hand(card_visual: Node) -> void:
	"""Handle when a card is dragged out of the hand bounds (from PlayerHand signal)"""
	# This is specifically for cards dragged from hand to play zone
	# Card is already outside hand bounds as detected by PlayerHand

	# Ensure the card is not in the drag state anymore
	_dragging_card = null

	if _player_hand.has_card(card_visual):
		# Move the card to play zone as an atk card
		_move_card_to_play_zone(card_visual)


func _on_card_returned_to_hand(card_visual: Node) -> void:
	"""Handle when an atk card is returned to hand (from PlayZone signal)"""
	# This handles cards that were dragged out of the play zone bounds
	# Move the card back to hand
	_move_card_to_hand(card_visual)


func _move_card_to_play_zone(card: Node) -> void:
	_player_hand._cards_in_hand.erase(card)
	_player_hand._update_z_indices()

	# Update visual: hand arranges after card removal
	_player_hand._arrange_cards()

	# Add to play zone as atk card (visual reparenting)
	_play_zone.add_atk_card(card)

	# Ensure click listener is still connected
	var interaction = card.get_node_or_null("Interaction")
	if interaction:
		# PlayZone manages the card connections, so don't connect directly
		# PlayZone.add_atk_card already connected the card
		pass


func _move_card_to_hand(card: Node) -> void:
	"""Move a card from play zone atk cards back to hand"""


	# Remove from play zone atk cards (this handles reparenting and scaling)
	_play_zone.remove_atk_card(card, _player_hand)

	# Add back to hand (this handles positioning and z_indices)
	_player_hand._add_card_back(card)

	# Ensure listeners are connected and re-enable interaction
	var interaction = card.get_node_or_null("Interaction")
	if interaction:
		# PlayerHand manages all the card connections, so don't connect directly
		# PlayerHand._add_card_back already connected the card
		pass

	card.set_shadow_visible(false)


func get_cards_in_hand() -> Array:
	"""Get all cards currently in hand"""
	return _player_hand.get_cards()


func get_cards_in_play() -> Array[Node]:
	"""Get all atk cards currently being played"""
	return _play_zone.get_atk_cards()


func _on_turn_changed(player_idx: int) -> void:
	"""Called when game turn changes - enable/disable buttons based on turn"""
	# Keep buttons visible but disable them when it's not player 0's turn
	var is_player_turn = (player_idx == 0)

	# Don't enable buttons if player has already passed
	var has_passed = false
	if _game_manager:
		has_passed = _game_manager.has_player_passed()

	# Enable/disable player card interaction
	var can_interact_with_cards = is_player_turn and not has_passed
	if _player_hand:
		_player_hand.set_cards_interactive(can_interact_with_cards)
	if _play_zone:
		_play_zone.set_cards_interactive(can_interact_with_cards)

	if _play_button:
		_play_button.disabled = !is_player_turn or has_passed
	if _pass_button:
		_pass_button.disabled = !is_player_turn or has_passed


func _on_ai_turn_started(player_idx: int, cards_to_play: Array) -> void:
	var cpu_hand_idx = player_idx - 1

	# Safety check
	if cpu_hand_idx < 0 or cpu_hand_idx >= _cpu_hands.size():
		push_error("Invalid CPU hand index: %d" % cpu_hand_idx)
		ai_action_complete.emit(player_idx, cards_to_play)
		return

	var cpu_hand = _cpu_hands[cpu_hand_idx]

	# Step 1: Animate hand moving up/toward center
	cpu_hand.animate_to_center()
	await get_tree().create_timer(0.5).timeout

	# Step 2: Brief delay for "AI thinking" effect
	await get_tree().create_timer(0.8).timeout

	# Step 3: Execute the visual action (play cards or pass)
	if cards_to_play.is_empty():
		# AI is passing - show PASSED label
		_show_pass_label_for_player(player_idx)
		await get_tree().create_timer(0.5).timeout  # Brief pause to see label
	else:
		# AI is playing cards - animate to table
		await _animate_ai_cards_to_table(player_idx, cards_to_play)

	# Step 4: Animate hand returning to original position
	cpu_hand.animate_to_original_position()
	await get_tree().create_timer(0.3).timeout

	# Step 5: Tell GameManager animations are complete
	# GameManager will now update state and advance turn
	ai_action_complete.emit(player_idx, cards_to_play)


func _animate_ai_cards_to_table(player_idx: int, cards: Array) -> void:
	var cpu_hand_idx = player_idx - 1

	if cpu_hand_idx < 0 or cpu_hand_idx >= _cpu_hands.size():
		push_error("Invalid CPU hand index: %d" % cpu_hand_idx)
		return

	var cpu_hand = _cpu_hands[cpu_hand_idx]

	# Create visual cards from CPU hand
	var cards_to_move: Array[Node] = []
	for i in range(cards.size()):
		if cpu_hand._cards.size() > 0:
			var card_visual = cpu_hand._cards.pop_back()

			# Set the card data to match logical card
			if i < cards.size() and card_visual.has_method("set_card"):
				card_visual.set_card(cards[i])

			# Show card face (not back)
			if card_visual.has_method("set_show_back"):
				card_visual.set_show_back(false)

			cards_to_move.append(card_visual)

	# Add cards to play zone as attack cards
	for card in cards_to_move:
		_play_zone.add_atk_card(card)

	# Commit them to set position with animation
	await _play_zone.commit_atk_to_set()

	# Emit for round tracker
	card_play_visual_complete.emit(player_idx, cards)

	# Rearrange CPU hand (visual update)
	if cpu_hand.has_method("_arrange_cards"):
		cpu_hand._arrange_cards()


func _on_round_started() -> void:
	"""Called when a new round starts - hide all PASSED indicators"""
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
	await get_tree().create_timer(0.4).timeout
	_hide_action_buttons()
	if _player_hand:
		_player_hand.set_cards_interactive(false)
	if _play_zone:
		_play_zone.set_cards_interactive(false)
	if _game_over_modal and _game_over_label:
		_game_over_modal.visible = true
		if winner_idx == 0: # Player 0 is the human player
			_game_over_label.text = "YOU WIN!"
		else:
			_game_over_label.text = "YOU LOSE!"


func _on_PlayAgainButton_pressed() -> void:
	"""Called when the 'Play Again' button is pressed"""
	if _game_over_modal:
		_game_over_modal.visible = false

	# Reset the game through the GameManager
	if _game_manager and _game_manager.has_method("reset_game"):
		_game_manager.reset_game()
	else:
		push_error("GameManager does not have a 'reset_game' method.")


func _on_invalid_play_attempted(_error_message: String) -> void:
	"""Called when GameManager signals an invalid play attempt by player 0"""
	if _invalid_play_label:
		_invalid_play_label.text = "INVALID" # Changed to simply "INVALID"
		_invalid_play_label.visible = true

		# Trigger the card shaking animation
		if _play_zone and _play_zone.has_method("shake_atk_cards"):
			_play_zone.shake_atk_cards()

		# Hide the label after a short delay
		var timer = get_tree().create_timer(3.0) # Show for 3 seconds
		await timer.timeout
		_invalid_play_label.visible = false


func _on_player_passed_visual(player_idx: int) -> void:
	"""Show PASSED label when any player passes
	Note: AI player labels are shown in _on_ai_turn_started,
	but this catches human player (player_idx == 0)
	"""
	if player_idx == 0:
		# Human player passed
		if _player_passed_label:
			_player_passed_label.visible = true


func _on_round_ended() -> void:
	"""Called when all but one player have passed. Waits then resets the round."""
	await get_tree().create_timer(1.5).timeout
	if _game_manager:
		_game_manager.trigger_round_reset()


func _connect_game_manager_signals() -> void:
	if not _game_manager:
		return

	# Connect to game manager signals
	if not _game_manager.turn_changed.is_connected(_on_turn_changed):
		_game_manager.turn_changed.connect(_on_turn_changed)
	if not _game_manager.round_started.is_connected(_on_round_started):
		_game_manager.round_started.connect(_on_round_started)
	if not _game_manager.round_ended.is_connected(_on_round_ended):
		_game_manager.round_ended.connect(_on_round_ended)
	if not _game_manager.game_ended.is_connected(_on_game_ended):
		_game_manager.game_ended.connect(_on_game_ended)
	if not _game_manager.invalid_play_attempted.is_connected(_on_invalid_play_attempted):
		_game_manager.invalid_play_attempted.connect(_on_invalid_play_attempted)
	if not _game_manager.player_passed.is_connected(_on_player_passed_visual):
		_game_manager.player_passed.connect(_on_player_passed_visual)
	if not _game_manager.game_reset.is_connected(_on_game_reset):
		_game_manager.game_reset.connect(_on_game_reset)

	# Connect to AI orchestration signals
	if not _game_manager.ai_turn_started.is_connected(_on_ai_turn_started):
		_game_manager.ai_turn_started.connect(_on_ai_turn_started)
	if not _game_manager.hand_updated.is_connected(_on_hand_updated):
		_game_manager.hand_updated.connect(_on_hand_updated)
	if not _game_manager.player_0_attack_zone_updated.is_connected(_on_player_0_attack_zone_updated):
		_game_manager.player_0_attack_zone_updated.connect(_on_player_0_attack_zone_updated)
	if not _game_manager.player_0_set_zone_updated.is_connected(_on_player_0_set_zone_updated):
		_game_manager.player_0_set_zone_updated.connect(_on_player_0_set_zone_updated)


func _on_game_reset() -> void:
	"""Handles the visual reset of the game screen when GameManager signals a game reset."""
	# Re-enable player interaction
	if _player_hand:
		_player_hand.set_cards_interactive(true)
	if _play_zone:
		_play_zone.set_cards_interactive(true)

	# Clear visual cards from play zone
	if _play_zone and _play_zone.has_method("clear_all_cards"):
		_play_zone.clear_all_cards()

	# Clear visual cards from player hand
	if _player_hand and _player_hand.has_method("clear_all_cards"):
		_player_hand.clear_all_cards()

	# Clear visual cards from CPU hands
	for cpu_hand in _cpu_hands:
		if cpu_hand and cpu_hand.has_method("clear_all_cards"):
			cpu_hand.clear_all_cards()

	# Make the deck visible again
	if _deck:
		_deck.visible = true

	# Make the start button visible again
	if _start_button:
		_start_button.visible = true

	# Hide the game over modal
	if _game_over_modal:
		_game_over_modal.visible = false

	# Hide all "PASSED" labels
	if _player_passed_label:
		_player_passed_label.visible = false
	if _cpu_top_passed_label:
		_cpu_top_passed_label.visible = false
	if _cpu_left_passed_label:
		_cpu_left_passed_label.visible = false
	if _cpu_right_passed_label:
		_cpu_right_passed_label.visible = false

	# Hide the invalid play label
	if _invalid_play_label:
		_invalid_play_label.visible = false

	# Hide the RoundTracker
	if _round_tracker:
		_round_tracker.visible = false


	_dragging_card = null

	# Reset card tracking for dealing
	_cards_dealt = 0
	_prev_player_counts = [0, 0, 0, 0]


func _on_hand_updated(player_index: int, cards: Array[Card]) -> void:
	"""Handler for GameManager.hand_updated signal - updates any player's visual hand."""
	if player_index == 0:
		# Update player 0's (human) hand
		if _player_hand and _player_hand.has_method("clear_and_populate"):
			_player_hand.clear_and_populate(cards)

	else:
		# Update a CPU's hand
		var cpu_hand_idx = player_index - 1
		if cpu_hand_idx >= 0 and cpu_hand_idx < _cpu_hands.size():
			var cpu_hand_node = _cpu_hands[cpu_hand_idx]
			if cpu_hand_node and cpu_hand_node.has_method("clear_and_set_count"):
				cpu_hand_node.clear_and_set_count(cards.size())


func _on_player_0_attack_zone_updated(cards: Array[Card]) -> void:
	"""Handler for GameManager.player_0_attack_zone_updated signal - updates player 0's visual attack zone."""
	# This signal is emitted when player 0 successfully plays cards.
	# The visual update (moving cards from hand to attack zone) is already handled by _on_play_pressed
	# and _move_card_to_play_zone. This signal serves as a confirmation/trigger for other UI elements if needed.
	pass


func _on_player_0_set_zone_updated(cards: Array[Card]) -> void:
	"""Handler for GameManager.player_0_set_zone_updated signal - updates player 0's visual set zone."""
	# This signal is emitted when player 0 successfully plays cards and they are committed to the set.
	# The visual update (moving cards from attack zone to set zone) is already handled by _on_play_pressed
	# and _play_zone.commit_atk_to_set(). This signal serves as a confirmation/trigger for other UI elements if needed.
	pass
