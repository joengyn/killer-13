extends Node
## GameManager - Manages game state and UI coordination
##
## This singleton autoload manages the complete game state, including deck management,
## player hand creation, and game initialization for 4-player Tiến Lên gameplay.

var deck: Deck
var players: Array[Hand] = []
var game_state: GameState
var current_game_started = false

func _ready():
	# Initialize game components if not already done
	if players.is_empty():
		setup_game()

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

## Begin the actual game after Start button is clicked
func start_game():
	current_game_started = true
	_find_starting_player()
	print("Game started! Player %d's turn (has 3♠)." % game_state.current_player)

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
	setup_game()

## Return all player hands
func get_players() -> Array[Hand]:
	return players

## Return current game state
func get_current_state() -> GameState:
	return game_state
