class_name GameState
## Tracks all game state for a Tiến Lên game session
##
## Manages turn progression, pass tracking, table state, and game-over conditions.
## Handles player cycling, round resets, and win detection.

var current_player: int = 0
var num_players: int = 4

var table_combo: Array = []                    # Last played combination on the table
var passed_players: Array[bool] = []           # Which players passed in current round
var game_over: bool = false
var winner: int = -1
var active_players: Array[bool] = []           # Players still in the game (have cards)
var consecutive_passes: int = 0                # Passes in a row (resets when someone plays)
var is_first_turn_of_game: bool = true         # Only true at the very start of the game

## Initialize game state for the specified number of players
func _init(num: int = 4) -> void:
	num_players = num
	# Initialize pass tracking and active player arrays
	for i in range(num_players):
		passed_players.append(false)
		active_players.append(true)
	current_player = 0

## Move to next player in clockwise order
func next_player() -> void:
	current_player = (current_player + 1) % num_players

## Get the next active player (skip players with no cards)
func get_next_active_player() -> int:
	var start = current_player
	next_player()

	while not active_players[current_player]:
		next_player()
		if current_player == start:
			# All players checked
			break

	return current_player

## Check if current player passed in this round
func has_current_player_passed() -> bool:
	return passed_players[current_player]

## Mark current player as passed
func mark_player_passed() -> void:
	passed_players[current_player] = true
	consecutive_passes += 1

## Mark current player as not passed (when they play a card)
func mark_player_played() -> void:
	passed_players[current_player] = false
	consecutive_passes = 0

## Set the current table combination
func set_table_combo(combo: Array) -> void:
	table_combo = combo.duplicate()

## Get the current table combination
func get_table_combo() -> Array:
	return table_combo

## Reset the round (all pass, so next player starts fresh)
func reset_round() -> void:
	for i in range(num_players):
		passed_players[i] = false
	table_combo = []
	consecutive_passes = 0

## Check if all other active players have passed
# (meaning the current player's play stands)
func all_others_passed() -> bool:
	var active_pass_count = 0
	var num_active = 0

	for i in range(num_players):
		if not active_players[i]:
			continue  # Skip inactive players

		num_active += 1
		if i != current_player and passed_players[i]:
			active_pass_count += 1

	# All other active players passed if all but current player passed
	return active_pass_count == num_active - 1

## Mark a player as inactive (out of cards)
func mark_player_inactive(player: int) -> void:
	active_players[player] = false

## Check if game is over (only one player has cards left)
func check_game_over() -> bool:
	var active_count = 0
	var last_active = -1

	for i in range(num_players):
		if active_players[i]:
			active_count += 1
			last_active = i

	if active_count == 1:
		game_over = true
		winner = last_active
		return true

	return false

## Get game status string
func get_status() -> String:
	return "Turn: Player %d | Table: %s | Passes: %d" % [
		current_player,
		Combination.combo_to_string(table_combo) if not table_combo.is_empty() else "Empty",
		consecutive_passes
	]
