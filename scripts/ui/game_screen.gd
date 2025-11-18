extends Node2D
##
## GameScreen - Main Game Orchestration Controller
##
## Serves as the central orchestrator for all game UI and visual feedback. Manages:
## - Dealing animation sequence and card distribution
## - Player interaction (card selection, dragging, playing)
## - AI turn animation and coordination with GameManager
## - Visual state updates (turn indicators, passed labels, game over screen)
## - Theme switching and hand sorting toggles
##
## Architecture:
## - GameScreen is independent of game logic (handled by GameManager autoload)
## - GameScreen only manages visual representation and user interaction
## - Communication with GameManager happens via signals to avoid tight coupling
## - All card movement is reflected visually without duplicating game logic
##
## Signal Flow:
## 1. Player action (click/drag) -> GameScreen updates visual and emits to GameManager
## 2. GameManager validates and updates game state
## 3. GameManager emits signal back to GameScreen for visual confirmation
## 4. GameScreen animates the visual change
##
## Key Methods:
## - animate_deal_sequence(): Animated dealing of cards to all players
## - _on_play_pressed(): Handle player card play submission
## - _on_ai_turn_started(): Orchestrate AI player animation
## - _connect_game_manager_signals(): Set up all signal connections
##


# ============================================================================
# SIGNALS
# ============================================================================

## Emitted when an AI player completes their action (play or pass).
## Signals to GameManager that visual animations are complete.
signal ai_action_complete(player_idx: int, cards_played: Array)

## Emitted when the human player completes their action.
## Signals to GameManager that visual animations are complete.
signal player_action_complete

## Emitted when card play visuals are complete for any player.
## Used to trigger round tracker updates and other dependent UI elements.
signal card_play_visual_complete(player_index: int, cards: Array)


# ============================================================================
# SCENE REFERENCES (@onready)
# ============================================================================

## Scene child references - cached for performance and null-checking
@onready var _player_hand: Node2D = $PlayerHand
@onready var _cpu_hand_left: Node2D = $CPUHandLeft
@onready var _cpu_hand_top: Node2D = $CPUHandTop
@onready var _cpu_hand_right: Node2D = $CPUHandRight
@onready var _play_zone: Node2D = $PlayZone
@onready var _deck: Node2D = $Deck

## UI Button references
@onready var _start_button: Button = $CanvasLayer/UIContainer/StartButton
@onready var _play_button: Button = $CanvasLayer/UIContainer/ActionButtonsContainer/PlayButton
@onready var _pass_button: Button = $CanvasLayer/UIContainer/ActionButtonsContainer/PassButton
@onready var _sort_button: Button = $CanvasLayer/UIContainer/SortButton
@onready var _theme_button: Button = $CanvasLayer/UIContainer/ThemeButton
@onready var _back_button: Button = $CanvasLayer/UIContainer/BackButton

## UI Label and Modal references
@onready var _round_tracker: Control = $CanvasLayer/UIContainer/RoundTracker
@onready var _player_passed_label: Label = $CanvasLayer/UIContainer/PlayerPassedLabel
@onready var _cpu_top_passed_label: Label = $CanvasLayer/UIContainer/CPUTopPassedLabel
@onready var _cpu_left_passed_label: Label = $CanvasLayer/UIContainer/CPULeftPassedLabel
@onready var _cpu_right_passed_label: Label = $CanvasLayer/UIContainer/CPURightPassedLabel
@onready var _invalid_play_label: Label = $CanvasLayer/UIContainer/InvalidPlayLabel
@onready var _game_over_label: Label = $CanvasLayer/UIContainer/GameOverModal/VBoxContainer/GameOverLabel
@onready var _game_over_modal: PanelContainer = $CanvasLayer/UIContainer/GameOverModal


# ============================================================================
# RUNTIME VARIABLES
# ============================================================================

## Reference to the GameManager autoload singleton
var _game_manager = GameManager

## State tracking for dealing animation
var _is_dealing: bool = false
var _cards_dealt: int = 0

## Array of CPU hand nodes in player order (1=left, 2=top, 3=right)
var _cpu_hands: Array[Node2D] = []

## Card currently being dragged (used for visual feedback)
var _dragging_card: Node = null

## Previous card counts for each player (used during incremental dealing)
var _prev_player_counts: Array[int] = [0, 0, 0, 0]

## Feature toggles for player preferences
var _auto_sort_enabled: bool = true
var _use_dark_theme: bool = true


# ============================================================================
# LIFECYCLE
# ============================================================================

func _ready() -> void:
	## Initialize GameScreen, set up signal connections, and prepare UI.
	## Handles both editor preview mode and runtime mode.

	if Engine.is_editor_hint():
		# EDITOR MODE: Child components initialize their own previews
		# Skip all game logic and signal connections
		return

	# RUNTIME MODE: Set up all signal connections and initialization

	# Connect GameScreen signals to GameManager for coordination
	if _game_manager:
		if not ai_action_complete.is_connected(_game_manager._on_ai_action_complete):
			ai_action_complete.connect(_game_manager._on_ai_action_complete)
		if not player_action_complete.is_connected(_game_manager._on_player_action_complete):
			player_action_complete.connect(_game_manager._on_player_action_complete)

	# Connect to PlayerHand card interaction signals
	if _player_hand:
		if _player_hand.has_signal("card_dragged_out"):
			_player_hand.card_dragged_out.connect(_on_card_dragged_out_from_hand)
		if _player_hand.has_signal("card_clicked"):
			_player_hand.card_clicked.connect(_on_card_clicked)
		if _player_hand.has_signal("card_drag_started"):
			_player_hand.card_drag_started.connect(_on_card_drag_started)

	# Connect to PlayZone attack card signals
	if _play_zone:
		if _play_zone.has_signal("atk_card_clicked"):
			_play_zone.atk_card_clicked.connect(_on_card_clicked)
		if _play_zone.has_signal("atk_card_dragged_out"):
			_play_zone.atk_card_dragged_out.connect(_on_card_returned_to_hand)
		if _play_zone.has_signal("atk_card_drag_started"):
			_play_zone.atk_card_drag_started.connect(_on_card_drag_started)

	# Populate CPU hands array in player index order (1=left, 2=top, 3=right)
	_cpu_hands = [_cpu_hand_left, _cpu_hand_top, _cpu_hand_right]

	# Initialize UI button states
	_hide_action_buttons()
	if _back_button:
		_back_button.visible = true

	# Connect button click signals
	if _start_button:
		_start_button.pressed.connect(_on_start_button_pressed)
	if _play_button:
		_play_button.pressed.connect(_on_play_pressed)
	if _pass_button:
		_pass_button.pressed.connect(_on_pass_pressed)
	if _sort_button:
		_sort_button.pressed.connect(_on_sort_button_pressed)
	_update_sort_button_text()
	if _theme_button:
		_theme_button.pressed.connect(_on_theme_button_pressed)
	_update_theme_button_text()
	if _back_button:
		_back_button.pressed.connect(_on_back_button_pressed)

	# Connect to deck's dealing signal
	if _deck and _deck.has_signal("deal_started"):
		_deck.deal_started.connect(_on_deck_clicked)

	# Initialize UI visibility
	if _invalid_play_label:
		_invalid_play_label.visible = false

	add_to_group("game_screen")

	# Connect RoundTracker to card play visual complete signal
	if _round_tracker:
		card_play_visual_complete.connect(_round_tracker._on_card_play_visual_complete)


# ============================================================================
# GAME SETUP & INITIALIZATION
# ============================================================================

func _start_game_immediately() -> void:
	## Sets up and starts the game instantly without dealing animations.
	## Used as an alternative to animate_deal_sequence() for testing or quick play.

	# Set up game state in GameManager
	_game_manager.setup_game(true)

	# Get player hands from GameManager
	var players = _game_manager.players
	if not players or players.size() < 4:
		return

	# Populate player's hand with sorted cards
	if _player_hand and _player_hand.has_method("clear_and_populate"):
		_player_hand.clear_and_populate(players[0].get_sorted_cards())
		_player_hand.auto_sort_enabled = _auto_sort_enabled
		_player_hand.set_cards_interactive(true)

	# Populate CPU hands with correct card counts
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

	# Connect signals and start the game
	if _game_manager:
		_connect_game_manager_signals()
		_game_manager.start_game()


func animate_deal_sequence() -> void:
	## Animate dealing 13 cards to each of 4 players (52 total).
	## Cards are dealt in a clockwise order starting from the player (bottom).
	## This coroutine handles both the visual animation and incremental population
	## of the player arrays. It's called when the player clicks the deck.

	# Set up the game state in GameManager (without emitting signals yet)
	_game_manager.setup_game(false)

	# Reset card tracking for this deal
	_cards_dealt = 0
	_prev_player_counts = [0, 0, 0, 0]

	# Animate dealing 13 rounds, each round deals to 4 players
	# Order: Player (0) -> CPU Left (1) -> CPU Top (2) -> CPU Right (3)
	var deal_order = [0, 1, 2, 3]

	# Get hand positions for animation targets
	var player_pos = Vector2(960, 1010)
	if _player_hand:
		player_pos = _player_hand.global_position

	var cpu_left_pos = Vector2(100, 540)
	if _cpu_hands.size() > 0:
		cpu_left_pos = _cpu_hands[0].global_position

	var cpu_top_pos = Vector2(960, 100)
	if _cpu_hands.size() > 1:
		cpu_top_pos = _cpu_hands[1].global_position

	var cpu_right_pos = Vector2(1820, 540)
	if _cpu_hands.size() > 2:
		cpu_right_pos = _cpu_hands[2].global_position

	var hand_positions = [player_pos, cpu_left_pos, cpu_top_pos, cpu_right_pos]

	# Deal 13 cards per round (52 total / 4 players = 13 rounds)
	for round_num in range(13):
		for order_idx in deal_order:
			# Animate one card visually to the target hand position
			await _deck.deal_card_animated(hand_positions[order_idx], order_idx)

			# Increment dealt count and populate the hands incrementally
			_cards_dealt += 1
			_populate_dealt_cards(_cards_dealt)

			# Minimal delay between cards for animation pacing
			await get_tree().create_timer(Constants.DEAL_CARD_INTERVAL).timeout

	# After dealing is complete, clean up temporary cards
	if _deck and _deck.has_method("cleanup_dealt_cards"):
		_deck.cleanup_dealt_cards()

	# Hide the deck so it doesn't intercept clicks
	if _deck:
		_deck.visible = false

	# Finalize player hand display with sorted cards
	if _player_hand and _player_hand.has_method("clear_and_populate"):
		_player_hand.clear_and_populate(_game_manager.players[0].get_sorted_cards())
		_player_hand.auto_sort_enabled = _auto_sort_enabled
		_player_hand.set_cards_interactive(true)

	_show_action_buttons()

	# Connect signals and start the actual game
	if _game_manager:
		_connect_game_manager_signals()
		_game_manager.start_game()


func _populate_dealt_cards(num_cards_dealt: int) -> void:
	## Incrementally populate hands with dealt cards as the dealing animation progresses.
	## Only adds NEW cards that have been dealt since the last call (diff-based).
	## This avoids rebuilding entire hands on each frame.
	##
	## @param num_cards_dealt: Total number of cards dealt so far (1-52)

	if not _game_manager:
		return

	var players = _game_manager.players
	if not players or players.size() < 4:
		return

	# Calculate how many cards each player should have at this point
	# Cards are dealt in order: Player 0, 1, 2, 3, 0, 1, 2, 3, ... (round-robin)
	var player_counts: Array[int] = [0, 0, 0, 0]
	for card_idx in range(num_cards_dealt):
		var player_idx = card_idx % 4
		player_counts[player_idx] += 1

	# Add new cards to player hand only if count increased
	if _player_hand and _player_hand.has_method("add_card"):
		for i in range(_prev_player_counts[0], player_counts[0]):
			if i < players[0].cards.size():
				var _card_visual = _player_hand.add_card(players[0].cards[i])

	# Add new cards to CPU hands only if count increased
	for player_idx in range(1, 4):
		var cpu_hand_idx = player_idx - 1
		if cpu_hand_idx < _cpu_hands.size():
			if _cpu_hands[cpu_hand_idx].has_method("add_card"):
				for i in range(_prev_player_counts[player_idx], player_counts[player_idx]):
					_cpu_hands[cpu_hand_idx].add_card()

	# Update previous counts for next call
	_prev_player_counts = player_counts


# ============================================================================
# BUTTON HANDLERS
# ============================================================================

func _on_start_button_pressed() -> void:
	## Handle Start button press - begin game without dealing animation.
	_start_game_immediately()


func _on_deck_clicked() -> void:
	## Handle deck click - start animated dealing sequence.
	if _is_dealing:
		return

	# Hide the start button once dealing begins
	if _start_button:
		_start_button.visible = false

	_is_dealing = true
	await animate_deal_sequence()
	_is_dealing = false


func _on_sort_button_pressed() -> void:
	## Toggle the auto-sort feature for the player's hand.
	## When enabled, the hand is automatically sorted by card rank.
	## When disabled, the hand keeps its current visual order.

	_auto_sort_enabled = not _auto_sort_enabled
	_update_sort_button_text()

	if _auto_sort_enabled:
		# Re-sort and display the hand when turning on auto-sort
		if _player_hand and _player_hand.has_method("clear_and_populate"):
			# Get cards currently in hand (exclude cards in play zone)
			var cards_in_hand_data: Array[Card] = []
			for card_visual in _player_hand._cards_in_hand:
				if card_visual.has_method("get_card"):
					cards_in_hand_data.append(card_visual.get_card())

			# Get all sorted cards from game manager
			var all_sorted_cards = _game_manager.players[0].get_sorted_cards()

			# Filter sorted cards to only include those still in hand
			var sorted_hand_cards: Array[Card] = []
			for card in all_sorted_cards:
				if card in cards_in_hand_data:
					sorted_hand_cards.append(card)

			_player_hand.clear_and_populate(sorted_hand_cards)
			_player_hand.set_cards_interactive(true)


func _update_sort_button_text() -> void:
	## Update the Sort button's display text based on current auto-sort state.
	## Shows ✓ when enabled, ✗ when disabled.

	if _sort_button:
		_sort_button.text = ("✓" if _auto_sort_enabled else "✗")


func _on_theme_button_pressed() -> void:
	## Toggle card theme between dark and light modes.
	## Updates CardLoader and redraws all visible cards.

	_use_dark_theme = not _use_dark_theme

	# Update CardLoader and reload sprites
	CardLoader.use_dark_mode = _use_dark_theme
	CardLoader.load_sprites()

	# Update button display
	_update_theme_button_text()

	# Redraw all visible cards with new theme
	_redraw_all_cards()


func _update_theme_button_text() -> void:
	## Update the Theme button's display text based on current theme.
	## Shows ⏾ for dark mode, ☀︎ for light mode.

	if _theme_button:
		_theme_button.text = ("⏾" if _use_dark_theme else "☀︎")


func _redraw_all_cards() -> void:
	## Refresh all visible cards to apply the new theme sprites.
	## Called when theme is switched to update all on-screen card visuals.

	# Refresh player hand cards
	if _player_hand:
		for card_visual in _player_hand._cards_in_hand:
			if card_visual and card_visual.has_method("set_card"):
				card_visual.set_card(card_visual.card)

	# Refresh CPU hand card backs
	for cpu_hand in _cpu_hands:
		if cpu_hand:
			for card_visual in cpu_hand._cards:
				if card_visual and card_visual.has_method("set_show_back"):
					card_visual.set_show_back(true)

	# Refresh play zone attack cards
	if _play_zone:
		var atk_cards = _play_zone.get_atk_cards()
		for card_visual in atk_cards:
			if card_visual and card_visual.has_method("set_card"):
				card_visual.set_card(card_visual.card)

	# Refresh play zone set cards
	if _play_zone:
		var set_cards = _play_zone.get_set_cards()
		for card_visual in set_cards:
			if card_visual and card_visual.has_method("set_card"):
				card_visual.set_card(card_visual.card)


func _on_back_button_pressed() -> void:
	## Return to the main menu.
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


func _on_PlayAgainButton_pressed() -> void:
	## Handle Play Again button press - reset the game to initial state.
	## Calls GameManager.reset_game() which triggers the game_reset signal,
	## causing _on_game_reset() to clear all cards and return to the start screen.

	if _game_manager:
		_game_manager.reset_game()


# ============================================================================
# CARD INTERACTION & MOVEMENT
# ============================================================================

func _on_card_clicked(card_visual: Node) -> void:
	## Handle card click - toggle between hand and play zone.
	## When a card is in hand and clicked, move it to play zone (attack zone).
	## When a card is in play zone and clicked, return it to hand.

	if _player_hand.has_card(card_visual):
		# Move from hand to play zone
		_move_card_to_play_zone(card_visual)
	elif _play_zone.has_atk_card(card_visual):
		# Move from play zone back to hand
		_move_card_to_hand(card_visual)

	# Reset hover effects after moving
	var interaction = card_visual.get_node_or_null("Interaction")
	if interaction and interaction.has_method("reset_hover_state"):
		interaction.reset_hover_state()


func _on_card_drag_started(card_visual: Node) -> void:
	## Handle when a card drag starts - track the card being dragged.
	## Can be extended to add visual feedback (highlight valid zones, etc.)

	_dragging_card = card_visual


func _on_card_dragged_out_from_hand(card_visual: Node) -> void:
	## Handle when a card is dragged out of hand bounds.
	## Automatically moves the card to the play zone (attack zone).

	_dragging_card = null

	if _player_hand.has_card(card_visual):
		# Move the card to play zone as an attack card
		_move_card_to_play_zone(card_visual)


func _on_card_returned_to_hand(card_visual: Node) -> void:
	## Handle when an attack card is dragged out of play zone bounds.
	## Automatically returns the card to hand.

	_move_card_to_hand(card_visual)


func _move_card_to_play_zone(card: Node) -> void:
	## Move a card from hand to play zone (attack zone).
	## Updates visual hierarchy, reparenting, and layout.
	## The card's data remains in GameManager; this only updates visuals.

	# Remove from player hand's visual tracking
	_player_hand._cards_in_hand.erase(card)
	_player_hand._update_z_indices()

	# Rearrange remaining cards in hand
	_player_hand._arrange_cards()

	# Add to play zone as attack card (handles reparenting and scaling)
	# Player 0 is the human player
	_play_zone.add_atk_card(card, 0)


func _move_card_to_hand(card: Node) -> void:
	## Move a card from play zone (attack zone) back to hand.
	## Handles reparenting, scaling, and layout updates.
	## The card's data remains in GameManager; this only updates visuals.

	# Remove from play zone's attack cards (handles reparenting)
	_play_zone.remove_atk_card(card, _player_hand)

	# Add back to player hand (handles positioning and z-indices)
	_player_hand._add_card_back(card)

	# Clear shadow effect
	card.set_shadow_visible(false)


func get_cards_in_hand() -> Array:
	## Get all cards currently displayed in the player's hand.
	## Returns visual card nodes, not game data.

	return _player_hand.get_cards()


func get_cards_in_play() -> Array[Node]:
	## Get all attack cards currently being played in the play zone.
	## Returns visual card nodes, not game data.

	return _play_zone.get_atk_cards()


# ============================================================================
# PLAYER TURN MANAGEMENT
# ============================================================================

func _on_turn_changed(player_idx: int) -> void:
	## Handle turn change - enable/disable UI based on whose turn it is.
	## Only enables buttons when it's the human player's turn and they haven't passed.

	var is_player_turn = (player_idx == 0)

	# Check if player has already passed in this round
	var has_passed = false
	if _game_manager:
		has_passed = _game_manager.has_player_passed()

	# Allow card interaction only on player's turn and if they haven't passed
	var can_interact_with_cards = is_player_turn and not has_passed
	if _player_hand:
		_player_hand.set_cards_interactive(can_interact_with_cards)
	if _play_zone:
		_play_zone.set_cards_interactive(can_interact_with_cards)

	# Enable/disable action buttons accordingly
	if _play_button:
		_play_button.disabled = !is_player_turn or has_passed
	if _pass_button:
		_pass_button.disabled = !is_player_turn or has_passed


func _on_play_pressed() -> void:
	## Handle Play button press - submit attack cards to GameManager for validation.
	## If valid, animates cards to the set zone. If invalid, re-enables buttons.

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

	# Submit play to GameManager for validation
	var success = GameManager.execute_player_play(card_data)

	if success:
		# Play was valid - animate attack cards to set zone
		await _play_zone.commit_atk_to_set()

		# Emit signals for other UI elements
		card_play_visual_complete.emit(0, card_data)
		player_action_complete.emit()
	else:
		# Play was invalid - re-enable buttons so player can correct their move
		if _game_manager.has_player_passed() == false:
			_play_button.disabled = false
			_pass_button.disabled = false

	if _play_button:
		_play_button.release_focus()


func _on_pass_pressed() -> void:
	## Handle Pass button press - return attack cards to hand and signal pass to GameManager.

	# Disable buttons immediately to prevent race conditions
	_play_button.disabled = true
	_pass_button.disabled = true

	# Move any cards on the table back to hand
	var atk_cards = _play_zone.get_atk_cards()
	for card in atk_cards:
		_move_card_to_hand(card)

	# Signal pass to GameManager
	var pass_result = GameManager.pass_turn()

	if pass_result == "pass_ok":
		# Pass was valid
		player_action_complete.emit()
	elif pass_result == "round_ended":
		# Round ended after this pass (other players already passed)
		pass
	else:  # "invalid"
		# Pass was invalid - re-enable buttons
		if _game_manager.has_player_passed() == false:
			_play_button.disabled = false
			_pass_button.disabled = false

	if _pass_button:
		_pass_button.release_focus()


# ============================================================================
# AI TURN ORCHESTRATION
# ============================================================================

func _on_ai_turn_started(player_idx: int, cards_to_play: Array) -> void:
	## Orchestrate visual animation for an AI player's turn.
	## Sequence: Hand moves up -> Think delay -> Play/Pass animation -> Hand moves back.
	## Emits ai_action_complete when animations are done.
	##
	## @param player_idx: Index of the AI player (1=left, 2=top, 3=right)
	## @param cards_to_play: Array of Card objects to play (empty if passing)

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
		await get_tree().create_timer(0.5).timeout
	else:
		# AI is playing cards - animate to table
		await _animate_ai_cards_to_table(player_idx, cards_to_play)

	# Step 4: Animate hand returning to original position
	cpu_hand.animate_to_original_position()
	await get_tree().create_timer(0.3).timeout

	# Step 5: Signal that visual animations are complete
	# GameManager will update game state and advance turn
	ai_action_complete.emit(player_idx, cards_to_play)


func _animate_ai_cards_to_table(player_idx: int, cards: Array) -> void:
	## Animate AI player's cards to the play table.
	## Cards are visually moved from hand to attack zone, then committed to set zone.
	##
	## @param player_idx: Index of the AI player (1=left, 2=top, 3=right)
	## @param cards: Array of Card objects to be played

	var cpu_hand_idx = player_idx - 1

	if cpu_hand_idx < 0 or cpu_hand_idx >= _cpu_hands.size():
		push_error("Invalid CPU hand index: %d" % cpu_hand_idx)
		return

	var cpu_hand = _cpu_hands[cpu_hand_idx]

	# Create visual cards for the play by extracting from CPU hand visuals
	var cards_to_move: Array[Node] = []
	for i in range(cards.size()):
		if cpu_hand._cards.size() > 0:
			var card_visual = cpu_hand._cards.pop_back()

			# Reset rotation (cards have rotation from dealing animation)
			card_visual.rotation = 0.0

			# Set the card data to match the logical card
			if i < cards.size() and card_visual.has_method("set_card"):
				card_visual.set_card(cards[i])

			# Show card face (not back)
			if card_visual.has_method("set_show_back"):
				card_visual.set_show_back(false)

			cards_to_move.append(card_visual)

	# Add cards to play zone as attack cards
	for card in cards_to_move:
		_play_zone.add_atk_card(card, player_idx)

	# Animate attack cards to set zone
	await _play_zone.commit_atk_to_set()

	# Signal that card play visuals are complete
	card_play_visual_complete.emit(player_idx, cards)

	# Rearrange remaining CPU hand cards
	if cpu_hand.has_method("_arrange_cards"):
		cpu_hand._arrange_cards()


# ============================================================================
# ROUND & GAME STATE MANAGEMENT
# ============================================================================

func _on_round_started() -> void:
	## Handle new round start - reset visual indicators.
	## Hides all "PASSED" labels and resets the play zone placeholder.

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


func _on_round_ended() -> void:
	## Handle round end - wait before triggering the reset.
	## GameManager resets the round after visual indicators are cleared.

	await get_tree().create_timer(1.5).timeout
	if _game_manager:
		_game_manager.trigger_round_reset()


func _on_game_ended(winner_idx: int) -> void:
	## Handle game end - show game over modal with winner/loser message.
	##
	## @param winner_idx: Index of the winning player (0=human player)

	await get_tree().create_timer(0.4).timeout
	_hide_action_buttons()
	if _player_hand:
		_player_hand.set_cards_interactive(false)
	if _play_zone:
		_play_zone.set_cards_interactive(false)
	if _game_over_modal and _game_over_label:
		_game_over_modal.visible = true
		if winner_idx == 0:
			_game_over_label.text = "YOU WIN!"
		else:
			_game_over_label.text = "YOU LOSE!"


func _on_game_reset() -> void:
	## Handle visual reset when returning to the start screen.
	## Clears all cards, resets UI state, and shows the deck/start button again.

	# Re-enable player interaction
	if _player_hand:
		_player_hand.set_cards_interactive(true)
	if _play_zone:
		_play_zone.set_cards_interactive(true)

	# Clear all visual cards
	if _play_zone and _play_zone.has_method("clear_all_cards"):
		_play_zone.clear_all_cards()
	if _player_hand and _player_hand.has_method("clear_all_cards"):
		_player_hand.clear_all_cards()
	for cpu_hand in _cpu_hands:
		if cpu_hand and cpu_hand.has_method("clear_all_cards"):
			cpu_hand.clear_all_cards()

	# Reset UI to pre-game state
	if _deck:
		_deck.visible = true
	if _start_button:
		_start_button.visible = true
	if _game_over_modal:
		_game_over_modal.visible = false

	# Clear all status labels
	if _player_passed_label:
		_player_passed_label.visible = false
	if _cpu_top_passed_label:
		_cpu_top_passed_label.visible = false
	if _cpu_left_passed_label:
		_cpu_left_passed_label.visible = false
	if _cpu_right_passed_label:
		_cpu_right_passed_label.visible = false
	if _invalid_play_label:
		_invalid_play_label.visible = false
	if _round_tracker:
		_round_tracker.visible = false

	# Reset internal state
	_dragging_card = null
	_cards_dealt = 0
	_prev_player_counts = [0, 0, 0, 0]
	_auto_sort_enabled = true
	_update_sort_button_text()

	# Reset theme to default
	_use_dark_theme = true
	CardLoader.use_dark_mode = _use_dark_theme
	CardLoader.load_sprites()
	_update_theme_button_text()


# ============================================================================
# UI & VISUAL FEEDBACK
# ============================================================================

func _show_pass_label_for_player(player_idx: int) -> void:
	## Show "PASSED" label for a specific player.
	##
	## @param player_idx: Index of the player who passed (0=bottom, 1=left, 2=top, 3=right)

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


func _on_player_passed_visual(player_idx: int) -> void:
	## Handle visual feedback when a player passes their turn.
	## Shows a PASSED label for the human player only
	## (AI labels are shown in _on_ai_turn_started).

	if player_idx == 0:
		if _player_passed_label:
			_player_passed_label.visible = true


func _on_invalid_play_attempted(_error_message: String) -> void:
	## Handle invalid play attempt - show error label and shake cards.
	## Displays "INVALID" for 3 seconds then hides automatically.

	if _invalid_play_label:
		_invalid_play_label.text = "INVALID"
		_invalid_play_label.visible = true

		# Trigger card shaking animation for feedback
		if _play_zone and _play_zone.has_method("shake_atk_cards"):
			_play_zone.shake_atk_cards()

		# Auto-hide label after delay
		await get_tree().create_timer(3.0).timeout
		_invalid_play_label.visible = false


func _hide_action_buttons() -> void:
	## Hide action buttons (Play, Pass, Sort, Theme).
	## Useful during dealing or when waiting for other players.

	if _play_button:
		_play_button.visible = false
	if _pass_button:
		_pass_button.visible = false
	if _sort_button:
		_sort_button.visible = false
	if _theme_button:
		_theme_button.visible = false


func _show_action_buttons() -> void:
	## Show action buttons after dealing is complete.
	## Also ensures Back button is visible for navigation.

	if _play_button:
		_play_button.visible = true
	if _pass_button:
		_pass_button.visible = true
	if _sort_button:
		_sort_button.visible = true
	if _theme_button:
		_theme_button.visible = true
	if _back_button:
		_back_button.visible = true


# ============================================================================
# GAME MANAGER SIGNAL CONNECTIONS
# ============================================================================

func _connect_game_manager_signals() -> void:
	## Connect all GameManager signals to GameScreen handlers.
	## This establishes the communication flow between game logic and visuals.

	if not _game_manager:
		return

	# Core game flow signals
	if not _game_manager.turn_changed.is_connected(_on_turn_changed):
		_game_manager.turn_changed.connect(_on_turn_changed)
	if not _game_manager.round_started.is_connected(_on_round_started):
		_game_manager.round_started.connect(_on_round_started)
	if not _game_manager.round_ended.is_connected(_on_round_ended):
		_game_manager.round_ended.connect(_on_round_ended)
	if not _game_manager.game_ended.is_connected(_on_game_ended):
		_game_manager.game_ended.connect(_on_game_ended)

	# Player action signals
	if not _game_manager.invalid_play_attempted.is_connected(_on_invalid_play_attempted):
		_game_manager.invalid_play_attempted.connect(_on_invalid_play_attempted)
	if not _game_manager.player_passed.is_connected(_on_player_passed_visual):
		_game_manager.player_passed.connect(_on_player_passed_visual)

	# AI orchestration signals
	if not _game_manager.ai_turn_started.is_connected(_on_ai_turn_started):
		_game_manager.ai_turn_started.connect(_on_ai_turn_started)

	# Hand update signals (for auto-sort feature)
	if not _game_manager.hand_updated.is_connected(_on_hand_updated):
		_game_manager.hand_updated.connect(_on_hand_updated)

	# Player zone update signals (mainly for logging/debugging)
	if not _game_manager.player_0_attack_zone_updated.is_connected(_on_player_0_attack_zone_updated):
		_game_manager.player_0_attack_zone_updated.connect(_on_player_0_attack_zone_updated)
	if not _game_manager.player_0_set_zone_updated.is_connected(_on_player_0_set_zone_updated):
		_game_manager.player_0_set_zone_updated.connect(_on_player_0_set_zone_updated)

	# Game reset signal
	if not _game_manager.game_reset.is_connected(_on_game_reset):
		_game_manager.game_reset.connect(_on_game_reset)

	# Player hand signals
	if _player_hand and not _player_hand.auto_sort_disabled.is_connected(_on_player_hand_auto_sort_disabled):
		_player_hand.auto_sort_disabled.connect(_on_player_hand_auto_sort_disabled)


# ============================================================================
# GAME MANAGER SIGNAL HANDLERS
# ============================================================================

func _on_hand_updated(player_index: int, cards: Array[Card]) -> void:
	## Handle hand update signal - refresh visual hand representation.
	## Supports auto-sort feature: preserves visual order when disabled.
	##
	## @param player_index: Index of the player whose hand was updated
	## @param cards: Array of Card objects now in the player's hand

	if player_index == 0:
		# Update human player's hand
		if _auto_sort_enabled:
			# Auto-sort enabled: clear and populate with sorted cards
			if _player_hand and _player_hand.has_method("clear_and_populate"):
				_player_hand.clear_and_populate(cards)
				_player_hand.auto_sort_enabled = _auto_sort_enabled
				_player_hand.set_cards_interactive(true)
		else:
			# Auto-sort disabled: update without changing visual order
			if _player_hand and _player_hand.has_method("update_visual_cards_after_play"):
				_player_hand.update_visual_cards_after_play(cards)
				_player_hand.auto_sort_enabled = _auto_sort_enabled
	else:
		# Update CPU hand count
		var cpu_hand_idx = player_index - 1
		if cpu_hand_idx >= 0 and cpu_hand_idx < _cpu_hands.size():
			var cpu_hand_node = _cpu_hands[cpu_hand_idx]
			if cpu_hand_node and cpu_hand_node.has_method("clear_and_set_count"):
				cpu_hand_node.clear_and_set_count(cards.size())


func _on_player_0_attack_zone_updated(_cards: Array[Card]) -> void:
	## Handler for player 0's attack zone update.
	## This is mainly for confirmation/logging - visual updates are handled
	## during the play action itself.

	pass


func _on_player_0_set_zone_updated(_cards: Array[Card]) -> void:
	## Handler for player 0's set zone update.
	## This is mainly for confirmation/logging - visual updates are handled
	## during commit_atk_to_set animation.

	pass


func _on_player_hand_auto_sort_disabled() -> void:
	## Handle signal from PlayerHand when user manually arranges cards.
	## Disables auto-sort to preserve the user's manual arrangement.

	_auto_sort_enabled = false
	_update_sort_button_text()


# ============================================================================
# CLEANUP
# ============================================================================

func _exit_tree() -> void:
	## Clean up signal connections when GameScreen is freed.
	## Prevents memory leaks from lingering signal connections.

	if not _game_manager:
		return

	# Disconnect GameManager signals
	if _game_manager.turn_changed.is_connected(_on_turn_changed):
		_game_manager.turn_changed.disconnect(_on_turn_changed)
	if _game_manager.round_started.is_connected(_on_round_started):
		_game_manager.round_started.disconnect(_on_round_started)
	if _game_manager.round_ended.is_connected(_on_round_ended):
		_game_manager.round_ended.disconnect(_on_round_ended)
	if _game_manager.game_ended.is_connected(_on_game_ended):
		_game_manager.game_ended.disconnect(_on_game_ended)
	if _game_manager.invalid_play_attempted.is_connected(_on_invalid_play_attempted):
		_game_manager.invalid_play_attempted.disconnect(_on_invalid_play_attempted)
	if _game_manager.player_passed.is_connected(_on_player_passed_visual):
		_game_manager.player_passed.disconnect(_on_player_passed_visual)
	if _game_manager.game_reset.is_connected(_on_game_reset):
		_game_manager.game_reset.disconnect(_on_game_reset)
	if _game_manager.ai_turn_started.is_connected(_on_ai_turn_started):
		_game_manager.ai_turn_started.disconnect(_on_ai_turn_started)
	if _game_manager.hand_updated.is_connected(_on_hand_updated):
		_game_manager.hand_updated.disconnect(_on_hand_updated)
	if _game_manager.player_0_attack_zone_updated.is_connected(_on_player_0_attack_zone_updated):
		_game_manager.player_0_attack_zone_updated.disconnect(_on_player_0_attack_zone_updated)
	if _game_manager.player_0_set_zone_updated.is_connected(_on_player_0_set_zone_updated):
		_game_manager.player_0_set_zone_updated.disconnect(_on_player_0_set_zone_updated)

	# Disconnect PlayerHand signals
	if _player_hand and _player_hand.auto_sort_disabled.is_connected(_on_player_hand_auto_sort_disabled):
		_player_hand.auto_sort_disabled.disconnect(_on_player_hand_auto_sort_disabled)

	# Disconnect UI button signals
	if _theme_button and _theme_button.pressed.is_connected(_on_theme_button_pressed):
		_theme_button.pressed.disconnect(_on_theme_button_pressed)
	if _back_button and _back_button.pressed.is_connected(_on_back_button_pressed):
		_back_button.pressed.disconnect(_on_back_button_pressed)
