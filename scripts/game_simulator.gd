extends Node

var deck: Deck
var game_state: GameState
var player_hands: Array[Hand] = []

var is_game_over: bool = false
var first_turn_of_game: bool = true
var first_player_index: int = -1

func _ready() -> void:
	print("\n" + "=".repeat(80))
	print("TIẾN LÊN CARD GAME - Console Simulation")
	print("=".repeat(80) + "\n")

	# Initialize game
	initialize_game()

	# Run the game
	run_game()

	# Print results
	print_game_results()

func initialize_game() -> void:
	print("Initializing game...\n")

	# Create and shuffle deck
	deck = Deck.new()
	deck.shuffle()

	# Create game state
	game_state = GameState.new(4)

	# Deal cards
	var dealt_hands = deck.deal(4)
	for i in range(4):
		player_hands.append(Hand.new(dealt_hands[i]))

	# Print initial hands
	print("Initial hands dealt:")
	for i in range(4):
		print("  Player %d (%d cards): %s" % [i, player_hands[i].get_card_count(), player_hands[i]._to_string()])

	# Find player with 3♠ to start
	for i in range(4):
		if player_hands[i].find_three_of_spades():
			first_player_index = i
			game_state.current_player = i
			break

	print("\nPlayer %d has 3♠ and will start!" % first_player_index)
	print("\n" + "-".repeat(80) + "\n")

func run_game() -> void:
	var turn_count = 0

	while not is_game_over and turn_count < Constants.MAX_TURNS:
		turn_count += 1
		execute_turn()

		# Check if anyone is out of cards
		for i in range(4):
			if player_hands[i].is_empty():
				game_state.mark_player_inactive(i)

		# Check game over condition
		if game_state.check_game_over():
			is_game_over = true
			break

	if turn_count >= Constants.MAX_TURNS:
		print("ERROR: Game exceeded maximum turns!")

func execute_turn() -> void:
	var player = game_state.current_player
	var hand = player_hands[player]

	print("--- Turn: Player %d | Cards left: %d | Table: %s" % [
		player,
		hand.get_card_count(),
		Combination.combo_to_string(game_state.get_table_combo()) if not game_state.get_table_combo().is_empty() else "EMPTY (Starting new round)"
	])

	# Get AI decision
	var played_cards = SimpleAI.decide_play(hand, game_state, first_turn_of_game and player == first_player_index)

	if played_cards.is_empty():
		# Player passed
		game_state.mark_player_passed()
		print("  Player %d PASSES" % player)

		# Check if all others have passed
		if game_state.all_others_passed():
			print("  All other players passed! Resetting round...\n")
			game_state.reset_round()

	else:
		# Player played cards
		game_state.mark_player_played()

		# Validate play
		var combo_type = Combination.detect_type(played_cards)

		if game_state.get_table_combo().is_empty():
			# Starting a new round
			var is_valid = Combination.is_valid(played_cards)
			# First turn of game must include 3♠
			if is_valid and first_turn_of_game:
				is_valid = Combination.contains_three_of_spades(played_cards)

			if is_valid:
				hand.remove_cards(played_cards)
				game_state.set_table_combo(played_cards)
				print("  Player %d plays %s (%s)" % [
					player,
					Combination.combo_to_string(played_cards),
					Combination.type_to_string(combo_type)
				])
				first_turn_of_game = false

				# Check if player won
				if hand.is_empty():
					is_game_over = true
					game_state.winner = player
					return
			else:
				# Invalid combo - treat as pass
				game_state.mark_player_passed()
				print("  Player %d PASSES (invalid combo %s)" % [
					player,
					Combination.combo_to_string(played_cards)
				])

				# Check if all others have passed
				if game_state.all_others_passed():
					print("  All other players passed! Resetting round...\n")
					game_state.reset_round()
		else:
			# Trying to beat existing combo
			if Combination.beats(played_cards, game_state.get_table_combo()):
				hand.remove_cards(played_cards)
				game_state.set_table_combo(played_cards)
				print("  Player %d beats with %s (%s)" % [
					player,
					Combination.combo_to_string(played_cards),
					Combination.type_to_string(combo_type)
				])

				# Check if player won
				if hand.is_empty():
					is_game_over = true
					game_state.winner = player
					return
			else:
				# Invalid combo - treat as pass
				game_state.mark_player_passed()
				print("  Player %d PASSES (couldn't beat with %s)" % [
					player,
					Combination.combo_to_string(played_cards)
				])

				# Check if all others have passed
				if game_state.all_others_passed():
					print("  All other players passed! Resetting round...\n")
					game_state.reset_round()

	# Move to next player
	game_state.next_player()

func print_game_results() -> void:
	print("\n" + "=".repeat(80))
	print("GAME OVER!")
	print("=".repeat(80) + "\n")

	if game_state.winner != -1:
		# Prominent winner announcement
		print("*".repeat(80))
		print("*" + " ".repeat(78) + "*")
		var winner_text = "🎉 WINNER: Player %d! 🎉" % game_state.winner
		var padding = (78 - winner_text.length()) / 2
		var centered = " ".repeat(padding) + winner_text + " ".repeat(78 - padding - winner_text.length())
		print("*" + centered + "*")
		print("*" + " ".repeat(78) + "*")
		print("*".repeat(80) + "\n")

		# Final hand states
		print("Final hand states:")
		for i in range(4):
			var status = "OUT OF CARDS (WINNER)" if i == game_state.winner else "%d cards remaining" % player_hands[i].get_card_count()
			print("  Player %d: %s" % [i, status])
			if not player_hands[i].is_empty():
				print("    Remaining: %s" % player_hands[i]._to_string())

		# Final confirmation
		print("\n" + "-".repeat(80))
		print("🏆 Player %d wins the game! 🏆" % game_state.winner)
		print("-".repeat(80) + "\n")
	else:
		print("No winner determined!")
		print("\n" + "=".repeat(80) + "\n")
