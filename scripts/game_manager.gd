extends Node
## GameManager - Manages game state and UI coordination
##
## This singleton autoload manages the complete game state, including deck management,
## player hand creation, and game initialization for 4-player Tiến Lên gameplay.

signal game_started  # Emitted when game is ready to begin
signal round_started # Emitted when a new round of play begins
signal turn_changed(player_index: int)  # Current player changed
signal player_played(player_index: int, cards: Array, is_set_card: bool)  # Cards were played (is_set_card = true if first play)
signal player_passed(player_index: int)  # Player passed
signal game_ended(winner: int)  # Someone won

var deck: Deck
var players: Array[Hand] = []
var game_state: GameState
var current_game_started = false

# Game flow state
var is_game_running: bool = false
var game_won: bool = false
var winner: int = -1
var first_turn_of_game: bool = true  # First turn (3♠ required)

# Visual card state tracking (player 0 only for now)
var player_visual_cards_in_hand: Array[Node] = []  # Visual cards currently in player's hand
var player_visual_cards_in_atk_zone: Array[Node] = []  # Visual cards in play zone (being attempted to play)
var player_visual_cards_in_set_zone: Array[Node] = []  # Visual cards committed on table (set cards)

func _ready():
	# GameManager initialization is handled by GameScreen.animate_deal_sequence()
	# No auto-setup here to avoid duplicate initialization
	pass

## Initialize deck, deal cards to 4 players
func setup_game():
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

## Begin the actual game after cards are dealt
func start_game():
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

## Player submits cards to play - called from UI when Play button pressed
func execute_player_play(cards: Array[Card]) -> bool:
	"""
	Player attempts to play cards.
	Returns: true if play was valid and executed, false if invalid
	"""
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


## Player passes - called from UI when Pass button pressed
func pass_turn() -> void:
	"""Current player passes their turn"""
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


## Check if player 0 has passed in the current round
func has_player_passed() -> bool:
	"""Returns true if player 0 passed in the current round"""
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


## ===== VISUAL CARD STATE MANAGEMENT =====

## Get all visual cards currently in player's hand
func get_player_hand_cards() -> Array[Node]:
	return player_visual_cards_in_hand.duplicate()


## Get all visual cards in atk zone (being played)
func get_player_atk_cards() -> Array[Node]:
	return player_visual_cards_in_atk_zone.duplicate()


## Get all visual cards in set zone (committed)
func get_player_set_cards() -> Array[Node]:
	return player_visual_cards_in_set_zone.duplicate()


## Determine where a card currently is
func get_card_location(card: Node) -> String:
	"""Returns: 'hand', 'atk', 'set', or 'unknown'"""
	if card in player_visual_cards_in_hand:
		return "hand"
	elif card in player_visual_cards_in_atk_zone:
		return "atk"
	elif card in player_visual_cards_in_set_zone:
		return "set"
	else:
		return "unknown"


## Move a card from hand to atk zone
func move_card_to_atk_zone(card: Node) -> bool:
	"""Move card from hand to atk zone. Returns true if successful."""
	if card not in player_visual_cards_in_hand:
		push_warning("Card not in hand, cannot move to atk zone")
		return false

	player_visual_cards_in_hand.erase(card)
	player_visual_cards_in_atk_zone.append(card)
	return true


## Move a card from atk zone back to hand
func move_card_to_hand(card: Node) -> bool:
	"""Move card from atk zone back to hand. Returns true if successful."""
	if card not in player_visual_cards_in_atk_zone:
		push_warning("Card not in atk zone, cannot move to hand")
		return false

	player_visual_cards_in_atk_zone.erase(card)
	player_visual_cards_in_hand.append(card)
	return true


## Commit atk cards to set zone (called when Play button succeeds)
func commit_atk_cards_to_set() -> void:
	"""Move all cards from atk zone to set zone"""
	for card in player_visual_cards_in_atk_zone:
		player_visual_cards_in_set_zone.append(card)
	player_visual_cards_in_atk_zone.clear()


## Clear all player visual cards (for new deal/reset)
func clear_player_visual_cards() -> void:
	"""Clear all visual card state - call when dealing new hand"""
	player_visual_cards_in_hand.clear()
	player_visual_cards_in_atk_zone.clear()
	player_visual_cards_in_set_zone.clear()


## Register a visual card to the player's hand
func add_card_to_player_hand(card: Node) -> void:
	"""Called when a new card is dealt to player"""
	if card not in player_visual_cards_in_hand:
		player_visual_cards_in_hand.append(card)
