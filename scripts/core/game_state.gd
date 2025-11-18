class_name GameState
## Tracks all game state for a Tiến Lên game session
##
## Manages turn progression, pass tracking, table combination, and game-over detection.
## Handles player cycling (skipping passed/inactive players), round resets when all others pass,
## and win detection when only one player has cards remaining.

## Current player's turn (0-3 for 4 players)
var current_player: int = 0
## Total number of players in the game
var num_players: int = 4

## Current combination of cards on the table (what must be beaten)
var table_combo: Array = []
## Tracks which players have passed in the current round
var passed_players: Array[bool] = []
## True if the game has ended (only one player has cards left)
var game_over: bool = false
## Index of the winning player (-1 if game not over)
var winner: int = -1
## Tracks which players are still active (have cards remaining)
var active_players: Array[bool] = []
## Count of consecutive passes (resets when someone plays cards)
var consecutive_passes: int = 0
## True only on the very first turn of the game (3♠ is required)
var is_first_turn_of_game: bool = true
## Index of the player who most recently played cards (set the current table combo)
var last_player_to_play: int = -1

## Initialize game state for a new game
## @param num: Number of players (default 4)
func _init(num: int = 4) -> void:
	num_players = num
	# Initialize pass tracking and active player arrays
	for i in range(num_players):
		passed_players.append(false)
		active_players.append(true)
	current_player = 0

## Move to next valid player in clockwise order
## Skips players who are inactive (no cards) or who have already passed this round
func next_player() -> void:
	var start_player = current_player
	var iterations = 0
	var max_iterations = num_players  # Safety limit

	while iterations < max_iterations:
		current_player = (current_player + 1) % num_players
		iterations += 1

		# Skip inactive players (no cards left)
		if not active_players[current_player]:
			continue

		# Skip players who have already passed this round
		if passed_players[current_player]:
			continue

		# Found a valid player who is active and hasn't passed
		break

	# Safety check: if we cycled through everyone, go back to start
	# This shouldn't happen in normal gameplay due to all_others_passed() check
	if iterations >= max_iterations:
		print("  [WARNING] Cycled through all players - none available!")
		current_player = start_player

## Get the next active player's index, skipping inactive players
## @return: Player index of the next active player
func get_next_active_player() -> int:
	var start = current_player
	next_player()

	while not active_players[current_player]:
		next_player()
		if current_player == start:
			# All players checked
			break

	return current_player

## Check if the current player has already passed this round
## @return: True if current player passed
func has_current_player_passed() -> bool:
	return passed_players[current_player]

## Mark the current player as having passed this round
## Increments consecutive pass counter
func mark_player_passed() -> void:
	passed_players[current_player] = true
	consecutive_passes += 1

## Mark the current player as having played cards (clears their pass status)
## Resets consecutive passes counter and updates last_player_to_play
func mark_player_played() -> void:
	passed_players[current_player] = false
	consecutive_passes = 0
	last_player_to_play = current_player

## Set the cards currently on the table (the combination to beat)
## @param combo: Array of Card objects forming the table combination
func set_table_combo(combo: Array) -> void:
	table_combo = combo.duplicate()

## Get the current table combination that must be beaten
## @return: Array of Card objects on the table
func get_table_combo() -> Array:
	return table_combo

## Reset the round when all players except one have passed
## Clears all pass flags, table combo, and last player tracking
func reset_round() -> void:
	for i in range(num_players):
		passed_players[i] = false
	table_combo = []
	consecutive_passes = 0
	last_player_to_play = -1  # Reset - no one has played in new round yet

## Check if all other active players have passed the current round
## When this returns true, the round is over and last_player_to_play wins the round
## @return: True if all players except last_player_to_play have passed
func all_others_passed() -> bool:
	# If no one has played yet, can't have "all others" pass
	if last_player_to_play == -1:
		return false

	var active_pass_count = 0
	var num_active = 0

	for i in range(num_players):
		if not active_players[i]:
			continue  # Skip inactive players

		num_active += 1
		# Check if all players EXCEPT the one who last played have passed
		if i != last_player_to_play and passed_players[i]:
			active_pass_count += 1

	# All other active players passed if all but the last player to play have passed
	return active_pass_count == num_active - 1

## Mark a player as inactive because they ran out of cards
## @param player: Player index to mark as inactive
func mark_player_inactive(player: int) -> void:
	active_players[player] = false

## Check if the game is over (only one player has cards remaining)
## Sets game_over and winner if game has ended
## @return: True if game is over
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

## Get a formatted string showing current game status for debugging
## @return: String with current player, table combo, and pass count
func get_status() -> String:
	var table_combo_str = "Empty"
	if not table_combo.is_empty():
		table_combo_str = Combination.combo_to_string(table_combo)

	return "Turn: Player %d | Table: %s | Passes: %d" % [
		current_player,
		table_combo_str,
		consecutive_passes
	]
