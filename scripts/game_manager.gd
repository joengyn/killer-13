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

## Visual card state tracking for player 0 (human player)
## Tracks which visual card nodes are in which zone (source of truth for card locations)
var player_visual_cards_in_hand: Array[Node] = []  ## Cards in PlayerHand
var player_visual_cards_in_atk_zone: Array[Node] = []  ## Cards in PlayZone attack area (being played)
var player_visual_cards_in_set_zone: Array[Node] = []  ## Cards committed on table (set)

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

	# Initialize game state for 4 players
	game_state = GameState.new()

	print("Game started! 4 players, 13 cards each.")

## Start the game after setup_game() completes
## Finds starting player (who has 3♠), emits signals, begins turn execution
func start_game() -> void:
	current_game_started = true
	is_game_running = true
	game_won = false
	first_turn_of_game = true

	_find_starting_player()
	print("Game started! Player %d's turn (has 3♠)." % game_state.current_player)

	# Emit signal to notify UI that game is ready
	game_started.emit()
	round_started.emit()
	turn_changed.emit(game_state.current_player)

	# If starting player is a CPU (not player 0), kick off their turn
	if game_state.current_player != 0:
		await get_tree().create_timer(0.5).timeout
		_execute_ai_turn()

## Execute human player's (player 0) play attempt
## Validates the play against game rules, updates game state if valid
## @param cards: Array of Card objects player wants to play
## @return: True if play was valid and executed, false if invalid
func execute_player_play(cards: Array[Card]) -> bool:
	if not is_game_running or game_state.current_player != 0:
		return false

	# Prevent playing after passing (shouldn't happen with skip logic, but safety check)
	if game_state.has_current_player_passed():
		print("Player 0 has already passed this round - cannot play!")
		return false

	if cards.is_empty():
		print("No cards to play")
		return false

	# Validate the play
	var is_valid = _validate_play(cards)

	if is_valid:
		# Execute the play
		_execute_play(cards)
		return true
	else:
		print("Invalid play")
		return false


## Execute human player's (player 0) pass action
## Marks player as passed, checks for round end, advances turn
func pass_turn() -> void:
	if not is_game_running or game_state.current_player != 0:
		return

	# Prevent double-passing
	if game_state.has_current_player_passed():
		print("Player 0 has already passed this round!")
		return

	print("Player 0 PASSES")
	game_state.mark_player_passed()
	player_passed.emit(0)

	# Check if all other players passed (round over)
	if game_state.all_others_passed():
		await _handle_round_reset()
		return  # Don't advance turn normally

	_advance_turn()


## Internal: Handle round reset when all other players have passed
func _handle_round_reset() -> void:
	"""Called when all players except one have passed - award round and reset"""
	print("All other players passed! Player %d wins the round!" % game_state.last_player_to_play)
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
func _validate_play(cards: Array[Card]) -> bool:
	"""Check if cards are valid according to game rules"""
	# Check if it's a valid combination
	if not Combination.is_valid(cards):
		print("Invalid combination: %s" % Combination.combo_to_string(cards))
		return false

	# First turn of the game requires 3♠
	if first_turn_of_game and game_state.current_player == _find_starting_player_index():
		var has_three_spades = false
		for card in cards:
			if card.is_three_of_spades():
				has_three_spades = true
				break
		if not has_three_spades:
			print("First turn requires 3♠")
			return false

	# If table is empty, starting new round (any valid combo allowed)
	if game_state.get_table_combo().is_empty():
		return true

	# Table has cards - must beat them
	if not Combination.beats(cards, game_state.get_table_combo()):
		print("Cards don't beat table: %s" % Combination.combo_to_string(cards))
		return false

	return true


## Internal: Execute a validated play
func _execute_play(cards: Array[Card]) -> void:
	"""Execute a valid play"""
	var player_idx = game_state.current_player
	var player_hand = players[player_idx]

	# Check if this is the first play of the round (becomes set card)
	var is_set_play = game_state.get_table_combo().is_empty()

	# Remove cards from player's hand
	player_hand.remove_cards(cards)

	# Update game state
	game_state.mark_player_played()
	game_state.set_table_combo(cards)

	print("Player %d plays %s" % [player_idx, Combination.combo_to_string(cards)])
	player_played.emit(player_idx, cards, is_set_play)

	# Check if player won
	if player_hand.is_empty():
		_end_game(player_idx)
		return

	# Mark that first turn is complete
	if first_turn_of_game:
		first_turn_of_game = false

	_advance_turn()


## Internal: Advance to the next player
func _advance_turn() -> void:
	"""Move to next player, execute AI if needed"""
	game_state.next_player()
	var next_player = game_state.current_player

	print("\n--- Turn: Player %d's turn | Cards left: %d" % [next_player, players[next_player].get_card_count()])

	turn_changed.emit(next_player)

	# If next player is AI (player 1, 2, or 3), execute AI turn automatically
	if next_player != 0:
		# Small delay so UI can update
		await get_tree().create_timer(0.5).timeout
		_execute_ai_turn()


## Internal: Execute AI player's turn
func _execute_ai_turn() -> void:
	"""AI decides what to do and executes turn"""
	var player_idx = game_state.current_player
	var hand = players[player_idx]

	# Safety check: Skip if this player has already passed
	# (shouldn't happen with next_player() skip logic, but just in case)
	if game_state.has_current_player_passed():
		print("  [WARNING] Player %d already passed - skipping AI turn" % player_idx)
		_advance_turn()
		return

	# Get AI decision
	var cards_to_play = SimpleAI.decide_play(hand, game_state, first_turn_of_game and player_idx == _find_starting_player_index())

	if cards_to_play.is_empty():
		# AI passes
		print("Player %d PASSES" % player_idx)
		game_state.mark_player_passed()
		player_passed.emit(player_idx)

		# Check if all others passed
		if game_state.all_others_passed():
			await _handle_round_reset()
			return  # Don't advance turn normally
	else:
		# AI plays - cast to Array[Card] for type safety
		var cards: Array[Card] = []
		for card in cards_to_play:
			cards.append(card as Card)
		_execute_play(cards)
		return  # _advance_turn already called from _execute_play

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

	print("\n" + "=".repeat(80))
	print("GAME OVER! Player %d wins!" % winner_idx)
	print("=".repeat(80) + "\n")

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

## Return all player hands
func get_players() -> Array[Hand]:
	return players

## Return current game state
func get_current_state() -> GameState:
	return game_state


## ============================================================================
## VISUAL CARD STATE MANAGEMENT (Player 0 only)
## ============================================================================
## These methods track which visual card nodes are in which zone
## GameManager is the source of truth for card locations

## Get all visual card nodes currently in player's hand
## @return: Array of Node (CardVisual) in hand zone
func get_player_hand_cards() -> Array[Node]:
	return player_visual_cards_in_hand.duplicate()


## Get all visual card nodes in attack zone (cards player is attempting to play)
## @return: Array of Node (CardVisual) in atk zone
func get_player_atk_cards() -> Array[Node]:
	return player_visual_cards_in_atk_zone.duplicate()

## Get all visual card nodes in set zone (committed to table)
## @return: Array of Node (CardVisual) in set zone
func get_player_set_cards() -> Array[Node]:
	return player_visual_cards_in_set_zone.duplicate()

## Determine which zone a visual card is currently in
## @param card: The visual card Node to check
## @return: String: 'hand', 'atk', 'set', or 'unknown'
func get_card_location(card: Node) -> String:
	if card in player_visual_cards_in_hand:
		return "hand"
	elif card in player_visual_cards_in_atk_zone:
		return "atk"
	elif card in player_visual_cards_in_set_zone:
		return "set"
	else:
		return "unknown"


## Move a visual card from hand zone to attack zone
## @param card: The visual card Node to move
## @return: True if successful, false if card wasn't in hand
func move_card_to_atk_zone(card: Node) -> bool:
	if card not in player_visual_cards_in_hand:
		push_warning("Card not in hand, cannot move to atk zone")
		return false

	player_visual_cards_in_hand.erase(card)
	player_visual_cards_in_atk_zone.append(card)
	return true


## Move a visual card from attack zone back to hand zone
## @param card: The visual card Node to move
## @return: True if successful, false if card wasn't in atk zone
func move_card_to_hand(card: Node) -> bool:
	if card not in player_visual_cards_in_atk_zone:
		push_warning("Card not in atk zone, cannot move to hand")
		return false

	player_visual_cards_in_atk_zone.erase(card)
	player_visual_cards_in_hand.append(card)
	return true


## Commit all attack zone cards to set zone (called when Play succeeds)
## This finalizes the play - cards are now on the table
func commit_atk_cards_to_set() -> void:
	for card in player_visual_cards_in_atk_zone:
		player_visual_cards_in_set_zone.append(card)
	player_visual_cards_in_atk_zone.clear()


## Clear all visual card tracking (called when starting a new game/deal)
func clear_player_visual_cards() -> void:
	player_visual_cards_in_hand.clear()
	player_visual_cards_in_atk_zone.clear()
	player_visual_cards_in_set_zone.clear()


## Register a visual card node as being in player's hand
## Called during dealing when cards are created
## @param card: The visual card Node to register
func add_card_to_player_hand(card: Node) -> void:
	if card not in player_visual_cards_in_hand:
		player_visual_cards_in_hand.append(card)
