extends Node
## GameManager - Central game coordinator singleton (autoload)
##
## This singleton manages the complete Tiến Lên game state, including:
## - Deck creation, shuffling, and dealing
## - Player hand management (4 players)
## - Turn execution (both human player and AI)
## - Game rule validation (valid plays, first turn 3♠ requirement, etc.)
## - Round progression and win detection
## - Visual card state tracking (hand, attack zone, set zone)
##
## Emits signals to notify GameScreen of game events for UI updates.

## Emitted after dealing completes and first player is determined (game ready to start)
signal game_started
## Emitted when a new round begins (all players passed except one, table clears)
signal round_started
## Emitted when turn advances to a new player
signal turn_changed(player_index: int)
## Emitted when any player plays cards (is_set_card = true if first play of round)
signal player_played(player_index: int, cards: Array, is_set_card: bool)
## Emitted when a player passes their turn
signal player_passed(player_index: int)
## Emitted when game ends (someone ran out of cards)
signal game_ended(winner: int)
## Emitted when player 0 attempts an invalid play
signal invalid_play_attempted(error_message: String)
## Emitted when an AI player's turn officially starts (for visual cues)
signal ai_turn_started(player_index: int)
## Emitted after AI decides to play or pass, before game logic executes
signal ai_decision_made(player_index: int, cards_to_play: Array)
## Emitted when the game is reset
signal game_reset
## Emitted when player 0's hand changes (logical cards)
signal player_0_hand_updated(cards: Array[Card])
## Emitted when player 0's attack zone changes (logical cards)
signal player_0_attack_zone_updated(cards: Array[Card])
## Emitted when player 0's set zone changes (logical cards)
signal player_0_set_zone_updated(cards: Array[Card])

## The deck of 52 cards
var deck: Deck
## Array of 4 Hand objects (player 0 = human, players 1-3 = CPU)
var players: Array[Hand] = []
## GameState object tracking turns, passes, and table state
var game_state: GameState
## True if game has been set up (deck dealt, hands created)
var current_game_started: bool = false

## Game flow state flags
var is_game_running: bool = false  ## True if game is actively playing (between start and end)
var game_won: bool = false  ## True if someone has won
var winner: int = -1  ## Index of winning player (-1 if no winner yet)
var first_turn_of_game: bool = true  ## True only on first turn (3♠ required)



func _ready():
	# GameManager initialization is handled by GameScreen.animate_deal_sequence()
	# No auto-setup here to avoid duplicate initialization
	pass

## Initialize a new game: create deck, shuffle, deal 13 cards to 4 players
## Does NOT start turn execution - call start_game() after setup_game()
func setup_game() -> void:
	deck = Deck.new()
	deck.shuffle()

	players.clear()

	# Deal 13 cards to each of 4 players
	var dealt_cards = deck.deal(4)

	# Create hands with the dealt cards
	for i in range(4):
		players.append(Hand.new(dealt_cards[i]))

	# Emit signal for player 0's initial hand
	player_0_hand_updated.emit(players[0].cards)

	# Initialize game state for 4 players
	game_state = GameState.new()

## Start the game after setup_game() completes
## Finds starting player (who has 3♠), emits signals, begins turn execution
func start_game() -> void:
	current_game_started = true
	is_game_running = true
	game_won = false
	first_turn_of_game = true

	_find_starting_player()

	# Emit signal to notify UI that game is ready
	game_started.emit()
	round_started.emit()
	turn_changed.emit(game_state.current_player)

	# If starting player is a CPU (not player 0), kick off their turn
	if game_state.current_player != 0:
		_execute_ai_turn()

## Execute human player's (player 0) play attempt
## Validates the play against game rules, updates game state if valid
## @param cards: Array of Card objects player wants to play
## @return: True if play was valid and executed, false if invalid
func execute_player_play(cards: Array[Card]) -> bool:
	if not is_game_running or game_state.current_player != 0:
		return false

	var error_message = ""

	# Prevent playing after passing (shouldn't happen with skip logic, but safety check)
	if game_state.has_current_player_passed():
		error_message = "Player 0 has already passed this round - cannot play!"
	elif cards.is_empty():
		error_message = "No cards to play"
	else:
		# Validate the play using the _validate_play function
		error_message = _validate_play(cards)

	if error_message.is_empty(): # If empty, play is valid
		# Execute the play
		_execute_play(cards)
		return true
	else:
		# Consolidate the error message as requested
		var full_error_message = "%s. Attempted to play %s." % [error_message, Combination.combo_to_string(cards)]
		invalid_play_attempted.emit(full_error_message) # Emit the signal
		return false


## Execute human player's (player 0) pass action
## Marks player as passed, checks for round end, advances turn
func pass_turn() -> bool: # Changed return type to bool
	if not is_game_running or game_state.current_player != 0:
		return false

	# New rule: Cannot pass on first turn if player has 3♠
	if first_turn_of_game and players[0].find_three_of_spades():
		var error_message = "Cannot pass on the first turn if you have the 3♠!"
		invalid_play_attempted.emit(error_message)
		return false

	# Prevent double-passing
	if game_state.has_current_player_passed():
		var error_message = "Player 0 has already passed this round!"
		invalid_play_attempted.emit(error_message)
		return false

	game_state.mark_player_passed()
	player_passed.emit(0)

	# Check if all other players passed (round over)
	if game_state.all_others_passed():
		await _handle_round_reset()
		return true  # Don't advance turn normally

	_advance_turn()
	return true # Pass was successful


## Internal: Handle round reset when all other players have passed
func _handle_round_reset() -> void:
	"""Called when all players except one have passed - award round and reset"""
	var round_winner = game_state.last_player_to_play

	# Pause to let players see all PASSED labels
	await get_tree().create_timer(1.5).timeout

	game_state.reset_round()
	round_started.emit()  # Signal that new round has started

	# Round winner starts the new round
	game_state.current_player = round_winner
	turn_changed.emit(round_winner)

	# If round winner is AI, execute their turn
	if round_winner != 0:
		await get_tree().create_timer(0.5).timeout
		_execute_ai_turn()


## Check if human player (player 0) has passed in the current round
## Used to disable Play/Pass buttons when player has already passed
## @return: True if player 0 passed this round
func has_player_passed() -> bool:
	return game_state.passed_players[0] if game_state else false


## Internal: Validate a play attempt
func _validate_play(cards: Array[Card]) -> String: # Returns error message string, empty if valid
	"""Check if cards are valid according to game rules"""
	# Check if it's a valid combination
	if not Combination.is_valid(cards):
		return "Invalid combination: %s" % Combination.combo_to_string(cards)

	# First turn of the game requires 3♠
	if first_turn_of_game and game_state.current_player == _find_starting_player_index():
		var has_three_spades = false
		for card in cards:
			if card.is_three_of_spades():
				has_three_spades = true
				break
		if not has_three_spades:
			return "First turn requires 3♠"

	# If table is empty, starting new round (any valid combo allowed)
	if game_state.get_table_combo().is_empty():
		return "" # Valid play

	# Table has cards - must beat them
	if not Combination.beats(cards, game_state.get_table_combo()):
		return "Cards don't beat table: %s" % Combination.combo_to_string(cards)

	return "" # Valid play


## Internal: Execute a validated play
func _execute_play(cards: Array[Card]) -> void:
	"""Execute a valid play"""
	var player_idx = game_state.current_player
	var player_hand = players[player_idx]

	# Check if this is the first play of the round (becomes set card)
	var is_set_play = game_state.get_table_combo().is_empty()

	# Remove cards from player's hand
	player_hand.remove_cards(cards)
	if player_idx == 0:
		player_0_hand_updated.emit(player_hand.cards)

	# Update game state
	game_state.mark_player_played()
	if player_idx == 0:
		player_0_attack_zone_updated.emit(cards) # Cards are now logically in the attack zone
	game_state.set_table_combo(cards)
	if player_idx == 0:
		player_0_set_zone_updated.emit(cards) # Cards are now logically in the set zone

	player_played.emit(player_idx, cards, is_set_play)

	# Check if player won
	if player_hand.is_empty():
		await _end_game(player_idx)
		return

	# Mark that first turn is complete
	if first_turn_of_game:
		first_turn_of_game = false


## Internal: Advance to the next player
func _advance_turn() -> void:
	"""Move to next player, execute AI if needed"""
	if not is_game_running: # Stop advancing turns if game has ended
		return
	game_state.next_player()
	var next_player = game_state.current_player

	turn_changed.emit(next_player)

	# If next player is AI (player 1, 2, or 3), execute AI turn automatically
	if next_player != 0:
		await _execute_ai_turn() # Await the AI's full turn cycle


## Internal: Execute AI player's turn
func _execute_ai_turn() -> void:
	"""AI decides what to do and executes turn"""
	if not is_game_running: # Stop AI if game has ended
		return
	var player_idx = game_state.current_player
	var hand = players[player_idx]

	# Emit signal for GameScreen to start visual "hand up" animation
	ai_turn_started.emit(player_idx)
	# Await GameScreen to complete the visual animation and initial delay
	await get_tree().create_timer(1.0).timeout


	# Safety check: Skip if this player has already passed
	if game_state.has_current_player_passed():
		_advance_turn() # Advance turn as no action will be taken
		return

	# Get AI decision
	var is_first_player_with_3_spades = first_turn_of_game and player_idx == _find_starting_player_index()
	var cards_to_play = SimpleAI.decide_play(hand, game_state, is_first_player_with_3_spades)

	# Emit signal for GameScreen to show AI's decision (cards or pass)
	ai_decision_made.emit(player_idx, cards_to_play)

	var should_advance_turn_after_await = true

	if cards_to_play.is_empty():
		# AI passes
		game_state.mark_player_passed()
		player_passed.emit(player_idx) # This will trigger GameScreen._on_player_passed which emits ai_action_complete

		# Check if all others passed (round over)
		if game_state.all_others_passed():
			await _handle_round_reset()
			should_advance_turn_after_await = false # Round reset handles next turn
	else:
		# AI plays
		var cards: Array[Card] = []
		for card in cards_to_play:
			cards.append(card as Card)
		_execute_play(cards) # _execute_play no longer calls _advance_turn()
		should_advance_turn_after_await = true # We need to advance turn after await

	# Await GameScreen to complete the visual action (card movement/pass label) and delay
	await get_tree().create_timer(1.0).timeout

	if should_advance_turn_after_await:
		_advance_turn()


## Internal: Find the starting player index
func _find_starting_player_index() -> int:
	"""Return index of player with 3♠"""
	for player_idx in range(4):
		if players[player_idx].find_three_of_spades():
			return player_idx
	return 0


## Internal: End the game when someone wins
func _end_game(winner_idx: int) -> void:
	"""Handle game end"""
	is_game_running = false
	game_won = true
	winner = winner_idx

	# Wait for visual card animations to complete before showing game over modal
	await get_tree().create_timer(0.4).timeout

	game_ended.emit(winner_idx)


## Find player with 3♠ to start the game
func _find_starting_player():
	for player_idx in range(4):
		var hand = players[player_idx]
		if hand.find_three_of_spades():
			game_state.current_player = player_idx
			return
	# Fallback to player 0 if no 3♠ found (shouldn't happen)
	game_state.current_player = 0

## Reset game for a new round
func reset_game():
	current_game_started = false
	is_game_running = false
	setup_game()
	game_reset.emit()

## Return all player hands
func get_players() -> Array[Hand]:
	return players

## Return current game state
func get_current_state() -> GameState:
	return game_state
