extends Control
## GameScreen - Main game display with full game loop
##
## Handles the visual representation of a 4-player Tiến Lên game with:
## - Player hand display at 4 positions
## - Table display in the center
## - Automatic turn execution via timer (AI vs AI)
## - Victory screen display

# ============================================================================
# PROPERTIES
# ============================================================================

var game_manager: Node
var card_scene = preload("res://scenes/card.tscn")
var card_visuals: Array[Array] = []  # [player_index][card_index]
var player_hand_nodes: Array[Node2D] = []  # Simple Node2D containers for each player

var game_state
var is_playing = false
var game_over = false
var turn_timer: Timer
var table_display: Node2D
var victory_overlay: Control
var first_player_index: int = -1  # Player with 3♠ (starts the game)
var first_turn_of_game: bool = true  # Only true at the very start
var last_player_to_play: int = -1  # Tracks who played last (for round resets)

# Player controls (Player 1 / Player 0 index)
var selected_cards: Array[Card] = []
var valid_playable_cards: Array[Card] = []
var pass_button: Button
var play_button: Button

# ============================================================================
# INITIALIZATION & SETUP
# ============================================================================

func _ready():
	# Get or create GameManager
	game_manager = get_node("/root/GameManager")
	if not game_manager:
		# Create new GameManager if it doesn't exist
		game_manager = Node.new()
		game_manager.set_script(load("res://scripts/game_manager.gd"))
		get_tree().root.add_child(game_manager)
		game_manager.name = "GameManager"
		await get_tree().process_frame  # Wait for _ready

	# Connect Start button
	$StartButton.pressed.connect(_on_start_pressed)

	# Position and size UI elements
	var viewport_size = get_viewport().get_visible_rect().size

	# Fill screen with background
	$ColorRect.position = Vector2.ZERO
	$ColorRect.size = viewport_size

	# Center start button
	$StartButton.position = (viewport_size - $StartButton.custom_minimum_size) / 2

	# Create hand position nodes for each player
	_setup_hand_positions()

	# Display all player hands
	display_hands()

	# Create table display area in center
	_setup_table_display()

	# Create timer for turn delays
	_setup_turn_timer()

	# Create Pass and Play buttons for player 1
	_setup_player_buttons()

# ============================================================================
# HAND & DISPLAY SETUP
# ============================================================================

func _setup_hand_positions():
	"""Create the 4 hand position nodes for each player"""
	player_hand_nodes.clear()

	var viewport_size = get_viewport().get_visible_rect().size

	# Positions for each player: [x, y] - more compact
	var positions = [
		[viewport_size.x / 2, viewport_size.y + Constants.PLAYER_0_Y_OFFSET],       # Player 0: Bottom center
		[Constants.PLAYER_1_X_OFFSET, viewport_size.y / 2],                         # Player 1: Left center
		[viewport_size.x / 2, Constants.PLAYER_2_Y_OFFSET],                         # Player 2: Top center
		[viewport_size.x - Constants.PLAYER_3_X_OFFSET, viewport_size.y / 2],       # Player 3: Right center
	]

	for i in range(4):
		var hand_node = Node2D.new()
		hand_node.name = "Player%dHand" % i
		hand_node.position = Vector2(positions[i][0], positions[i][1])
		add_child(hand_node)
		player_hand_nodes.append(hand_node)

func display_hands():
	"""Create and display all 4 player hands in traditional positions"""
	var players = game_manager.get_players()

	for player_idx in range(4):
		var hand = players[player_idx]
		card_visuals.append([])

		var x_offset = 0.0
		var y_offset = 0.0
		var card_spacing = Constants.CARD_SPACING_NORMAL

		# Use wider spacing for player 0 (bottom hand) so cards are readable
		if player_idx == 0:
			card_spacing = Constants.CARD_SPACING_PLAYER_0

		for card_idx in range(hand.cards.size()):
			var card = hand.cards[card_idx]
			var card_visual = card_scene.instantiate()

			# Mark player 0 cards as clickable, flip CPU cards
			if player_idx == 0:
				card_visual.set_card(card)
				card_visual.is_player_card = true
				card_visual.card_clicked.connect(_on_card_clicked)
			else:
				# Flip CPU player cards to show card back
				card_visual.card = card
				card_visual.show_card_back = true

			# Position cards in a row/column depending on player
			match player_idx:
				0:  # Bottom - horizontal row, right-aligned
					x_offset = -card_spacing * (hand.cards.size() - 1) / 2 + card_spacing * card_idx
					y_offset = 0
				1:  # Left - vertical column, top-aligned
					x_offset = 0
					y_offset = -card_spacing * (hand.cards.size() - 1) / 2 + card_spacing * card_idx
				2:  # Top - horizontal row, left-aligned
					x_offset = -card_spacing * (hand.cards.size() - 1) / 2 + card_spacing * card_idx
					y_offset = 0
				3:  # Right - vertical column, bottom-aligned
					x_offset = 0
					y_offset = -card_spacing * (hand.cards.size() - 1) / 2 + card_spacing * card_idx

			card_visual.position = Vector2(x_offset, y_offset)
			player_hand_nodes[player_idx].add_child(card_visual)
			card_visuals[player_idx].append(card_visual)

func _setup_table_display():
	"""Create the table area in center of screen"""
	table_display = Node2D.new()
	table_display.name = "TableDisplay"
	table_display.position = get_viewport().get_visible_rect().size / 2
	add_child(table_display)

func _setup_turn_timer():
	"""Create timer for turn delays"""
	turn_timer = Timer.new()
	turn_timer.wait_time = Constants.TURN_TIMER_WAIT_TIME
	turn_timer.timeout.connect(_on_turn_timer_timeout)
	add_child(turn_timer)

func _setup_player_buttons():
	"""Create Pass and Play buttons in the bottom right of the screen"""
	var viewport_size = get_viewport().get_visible_rect().size

	# Pass button (left)
	pass_button = Button.new()
	pass_button.text = "Pass"
	pass_button.custom_minimum_size = Constants.BUTTON_SIZE
	pass_button.position = viewport_size - Vector2(Constants.BUTTON_SIZE.x * 2 + Constants.BUTTON_SPACING + Constants.BUTTON_MARGIN, Constants.BUTTON_SIZE.y + Constants.BUTTON_MARGIN)
	pass_button.pressed.connect(_on_pass_pressed)
	add_child(pass_button)

	# Play button (right)
	play_button = Button.new()
	play_button.text = "Play"
	play_button.custom_minimum_size = Constants.BUTTON_SIZE
	play_button.position = viewport_size - Vector2(Constants.BUTTON_SIZE.x + Constants.BUTTON_MARGIN, Constants.BUTTON_SIZE.y + Constants.BUTTON_MARGIN)
	play_button.pressed.connect(_on_play_pressed)
	add_child(play_button)

# ============================================================================
# GAME FLOW & INPUT
# ============================================================================

func _on_card_clicked(card: Card):
	"""Handle card click - toggle selection"""
	if card in selected_cards:
		selected_cards.erase(card)
	else:
		selected_cards.append(card)

	if selected_cards.is_empty():
		print("Selected cards: none")
	else:
		print("Selected cards: %s" % Combination.combo_to_string(selected_cards))

func calculate_valid_playable_cards():
	"""Calculate which cards player 0 can play this round"""
	var players = game_manager.get_players()
	var hand = players[0]
	var table_combo = game_state.get_table_combo()

	valid_playable_cards.clear()

	# First turn of game - only first player must have 3♠
	if table_combo.is_empty() and first_turn_of_game and first_player_index == 0:
		var three_spades = hand.find_three_of_spades()
		if three_spades:
			valid_playable_cards.append(three_spades)
		return

	# If table is empty, any card can be played
	if table_combo.is_empty():
		valid_playable_cards = hand.cards.duplicate()
		return

	# Otherwise, find cards that can beat the current combo
	# For each card in hand, check if it can participate in a beating combo
	for card in hand.cards:
		if _can_card_participate_in_beating_combo(card, hand, table_combo):
			valid_playable_cards.append(card)

func _can_card_participate_in_beating_combo(card: Card, hand: Hand, table_combo: Array) -> bool:
	"""Check if a card can be part of any combo that beats the table"""
	# Try to find if this card can be part of a beating combo
	# This is a simplified check - could be enhanced

	var table_type = Combination.detect_type(table_combo)
	var table_strength = Combination.get_strength(table_combo)

	# Check bombs (can beat 2s)
	if Combination.detect_type([card]) == Combination.Type.QUAD:
		if Combination.beats([card], table_combo):
			return true

	# Simple approach: try single card, pair, triple
	if Combination.beats([card], table_combo):
		return true

	# Check pairs
	var same_rank = hand.get_cards_by_rank(card.rank)
	if same_rank.size() >= 2:
		if Combination.beats([same_rank[0], same_rank[1]], table_combo):
			return true

	# Check triples
	if same_rank.size() >= 3:
		if Combination.beats([same_rank[0], same_rank[1], same_rank[2]], table_combo):
			return true

	return false

func apply_valid_card_highlights():
	"""Apply visual indicators to cards that can be played"""
	var card_visuals_p0 = card_visuals[0]
	var hand = game_manager.get_players()[0]

	for card_visual in card_visuals_p0:
		if card_visual.card in valid_playable_cards:
			# Apply yellow tint to indicate it's playable
			card_visual.modulate = Color(1.3, 1.3, 0.5, 1.0)  # Yellowish tint
		else:
			# Reset modulation if not playable
			if not card_visual.selected:
				card_visual.modulate = Color.WHITE
			else:
				card_visual.modulate = Color(1.3, 1.3, 1.3)  # Keep selected color

func _on_pass_pressed():
	"""Handle pass button pressed"""
	if game_state.current_player != 0:
		return  # Not player's turn

	game_state.mark_player_passed()
	print("Player 0 passes")

	# Check if all others passed (reset round)
	if game_state.all_others_passed():
		print("All other players passed! Resetting round...")
		_reset_round_and_set_current_player(last_player_to_play)
		print("Round reset!")

	# Clear selection
	selected_cards.clear()
	_refresh_hand_display()

	# Move to next player and resume timer
	game_state.next_player()
	turn_timer.start()

func _on_play_pressed():
	"""Handle play button pressed"""
	if game_state.current_player != 0:
		return  # Not player's turn

	if game_state.has_current_player_passed():
		print("Player 0 has already passed this round!")
		return

	if selected_cards.is_empty():
		print("No cards selected!")
		return

	# Validate the play
	var is_valid = false

	if game_state.get_table_combo().is_empty():
		# First play of round - check validity
		var combo_type = Combination.detect_type(selected_cards)
		print("DEBUG: First play of round. Selected: %s, Type: %s" % [Combination.combo_to_string(selected_cards), Combination.type_to_string(combo_type)])
		is_valid = Combination.is_valid(selected_cards)
		print("DEBUG: is_valid after Combination.is_valid(): %s" % is_valid)
		# First turn of game must include 3♠ (only from first_player_index)
		if is_valid and first_turn_of_game and 0 == first_player_index:
			is_valid = Combination.contains_three_of_spades(selected_cards)
			print("DEBUG: is_valid after 3♠ check: %s" % is_valid)
	else:
		# Must beat existing combo
		is_valid = Combination.beats(selected_cards, game_state.get_table_combo())

	if is_valid:
		# Get player hand
		var hand = game_manager.get_players()[0]

		# Remove cards from hand
		hand.remove_cards(selected_cards)
		game_state.set_table_combo(selected_cards)
		game_state.mark_player_played()
		last_player_to_play = 0  # Track that player 0 made this play

		# Mark that we've passed the first turn of the game
		first_turn_of_game = false

		# Animate cards to table and update display
		await _animate_played_cards(0, selected_cards)
		_update_table_display()

		print("Player 0 plays: %s" % [Combination.combo_to_string(selected_cards)])

		# Check if player won
		if hand.is_empty():
			game_state.winner = 0
			game_over = true
			turn_timer.stop()
			# Wait for animations to finish before showing victory
			await get_tree().create_timer(Constants.VICTORY_DELAY).timeout
			_show_victory_overlay()
			return

		# Clear selection
		selected_cards.clear()
		_refresh_hand_display()

		# Move to next player and resume timer
		game_state.next_player()
		turn_timer.start()
	else:
		print("Invalid play!")
		# Could add visual feedback here (red flash, etc.)

func _on_start_pressed():
	"""Start the game when Start button is clicked"""
	game_manager.start_game()
	game_state = game_manager.get_current_state()
	$StartButton.visible = false
	is_playing = true
	game_over = false
	first_turn_of_game = true

	# Print game start message
	print("\n" + "=".repeat(80))
	print("TIẾN LÊN CARD GAME - Game Started")
	print("=".repeat(80) + "\n")

	# Find the first player (who has 3♠) and print initial hands
	var players = game_manager.get_players()
	print("Initial hands dealt:")
	for i in range(4):
		print("  Player %d (%d cards): %s" % [i, players[i].get_card_count(), players[i]._to_string()])
		if players[i].find_three_of_spades():
			first_player_index = i

	print("\nPlayer %d has 3♠ and will start!" % first_player_index)
	print("\n" + "-".repeat(80) + "\n")

	# If player 0 starts, show valid cards; otherwise start timer
	if game_state.current_player == 0:
		calculate_valid_playable_cards()
		apply_valid_card_highlights()
		print("Player 0's turn - waiting for input")
	else:
		turn_timer.start()

# ============================================================================
# TURN EXECUTION
# ============================================================================

func _on_turn_timer_timeout():
	"""Execute one turn of the game"""
	if game_over:
		turn_timer.stop()
		return

	# If it's player 0's turn, pause timer and wait for input
	if game_state.current_player == 0:
		# Check if all others have passed (round should reset)
		if game_state.all_others_passed() and not game_state.get_table_combo().is_empty():
			print("All other players passed! Resetting round...")
			_reset_round_and_set_current_player(last_player_to_play)
			print("Round reset!")
			# Continue to next iteration without stopping timer
			return

		# If player 0 already passed this round and table isn't empty, auto-pass
		if game_state.has_current_player_passed() and not game_state.get_table_combo().is_empty():
			print("Player 0 has already passed - auto-passing")
			game_state.next_player()
			# Don't call turn_timer.start() here - let the loop continue naturally
			return

		turn_timer.stop()
		calculate_valid_playable_cards()
		apply_valid_card_highlights()
		print("Player 0's turn - waiting for input")
		return

	var players = game_manager.get_players()
	var current_player = game_state.current_player
	var hand = players[current_player]
	var is_valid = false  # Track if this turn had a valid play

	# Get AI decision
	var is_first_turn = game_state.get_table_combo().is_empty() and first_turn_of_game and current_player == first_player_index
	var played_cards = SimpleAI.decide_play(hand, game_state, is_first_turn)

	var round_was_reset = false

	if played_cards.is_empty():
		# Player passes
		game_state.mark_player_passed()
		print("Player %d passes" % current_player)

		# Check if all others have passed
		if game_state.all_others_passed():
			print("All other players passed! Resetting round...")
			_reset_round_and_set_current_player(last_player_to_play)
			print("Round reset!")
			round_was_reset = true
	else:
		# Player plays
		is_valid = false

		if game_state.get_table_combo().is_empty():
			# First play of round - check validity
			is_valid = Combination.is_valid(played_cards)
			# First turn of game must include 3♠
			if is_valid and first_turn_of_game and current_player == first_player_index:
				is_valid = Combination.contains_three_of_spades(played_cards)
		else:
			# Must beat existing combo
			is_valid = Combination.beats(played_cards, game_state.get_table_combo())

		if is_valid:
			# Remove cards from hand
			hand.remove_cards(played_cards)
			game_state.set_table_combo(played_cards)
			game_state.mark_player_played()
			last_player_to_play = current_player  # Track that this player made this play

			# Mark that we've passed the first turn of the game
			first_turn_of_game = false

			# Animate cards to table and update display (don't await in timer callback)
			_animate_played_cards(current_player, played_cards)
			_update_table_display()

			print("Player %d plays: %s" % [current_player, Combination.combo_to_string(played_cards)])

			# Check if player won
			print("DEBUG: Player %d hand after remove: %d cards remaining" % [current_player, hand.cards.size()])
			if hand.is_empty():
				game_state.winner = current_player
				game_over = true
				turn_timer.stop()
				# Wait for animations to finish before showing victory
				await get_tree().create_timer(Constants.VICTORY_DELAY).timeout
				_show_victory_overlay()
				return
		else:
			# Invalid play - treat as pass
			game_state.mark_player_passed()
			print("Player %d passes" % current_player)

			# Check if all others have passed
			if game_state.all_others_passed():
				print("All other players passed! Resetting round...")
				_reset_round_and_set_current_player(last_player_to_play)
				print("Round reset!")
				round_was_reset = true

	# Refresh hand display (deferred to let animation start first)
	_refresh_hand_display.call_deferred()

	# Move to next player only if round wasn't reset
	# (If round was reset, current_player is already set to the round winner)
	if not round_was_reset:
		game_state.next_player()

# ============================================================================
# ROUND MANAGEMENT
# ============================================================================

func _reset_round_and_set_current_player(player: int) -> void:
	"""Reset the round and set the current player to the one who won it"""
	game_state.reset_round()
	game_state.current_player = player
	# Clear table display when round resets
	for child in table_display.get_children():
		child.queue_free()

# ============================================================================
# ANIMATIONS & DISPLAY UPDATES
# ============================================================================

func _animate_played_cards(player_idx: int, played_cards: Array):
	"""Animate cards from player hand to center table (one at a time)"""

	for card in played_cards:
		# Find the card visual from player's hand
		for card_visual in card_visuals[player_idx]:
			# Check if this visual still exists and has the matching card
			if is_instance_valid(card_visual) and card_visual.card == card:
				# Flip CPU player cards face-up before animating
				if player_idx != 0 and card_visual.show_card_back:
					card_visual.set_card(card)

				# Reset selection (move back to original position before animating)
				card_visual.position = card_visual.original_position

				# Animate to table using global coordinates
				var tween = create_tween()
				tween.set_trans(Tween.TRANS_QUAD)
				tween.set_ease(Tween.EASE_IN_OUT)
				tween.tween_property(card_visual, "global_position", table_display.global_position, Constants.CARD_ANIMATION_DURATION)

				# Wait for this card's animation to complete before moving to the next
				await tween.finished

				# Clean up this card
				card_visual.queue_free()
				card_visuals[player_idx].erase(card_visual)
				break

func _update_table_display():
	"""Update the table display with current combo"""
	# Clear old cards from table
	for child in table_display.get_children():
		child.queue_free()

	# Display new cards stacked on top of each other
	var table_combo = game_state.get_table_combo()
	if table_combo.is_empty():
		return

	var card_index = 0
	for card in table_combo:
		var card_visual = card_scene.instantiate()
		card_visual.set_card(card)
		# Stack cards: each card offset slightly to the right and down
		var x_offset = card_index * 15.0
		var y_offset = card_index * 5.0
		card_visual.position = Vector2(x_offset, y_offset)
		table_display.add_child(card_visual)
		card_index += 1

func _refresh_hand_display():
	"""Refresh all hand displays after cards are removed"""
	# Reposition cards in each hand to account for removed cards
	var players = game_manager.get_players()

	for player_idx in range(4):
		var hand = players[player_idx]
		var card_spacing = Constants.CARD_SPACING_NORMAL

		if player_idx == 0:
			card_spacing = Constants.CARD_SPACING_PLAYER_0

		var x_offset = 0.0
		var y_offset = 0.0
		var card_count = 0

		# Update positions of remaining cards
		for card_visual in card_visuals[player_idx]:
			if is_instance_valid(card_visual):
				match player_idx:
					0:
						x_offset = -card_spacing * (hand.cards.size() - 1) / 2 + card_spacing * card_count
						y_offset = 0
					1:
						x_offset = 0
						y_offset = -card_spacing * (hand.cards.size() - 1) / 2 + card_spacing * card_count
					2:
						x_offset = -card_spacing * (hand.cards.size() - 1) / 2 + card_spacing * card_count
						y_offset = 0
					3:
						x_offset = 0
						y_offset = -card_spacing * (hand.cards.size() - 1) / 2 + card_spacing * card_count

				card_visual.position = Vector2(x_offset, y_offset)
				card_visual.original_position = Vector2(x_offset, y_offset)
				card_count += 1

# ============================================================================
# VICTORY & RESET
# ============================================================================

func _print_game_over_summary():
	"""Print a nice game over summary to the console"""
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
		var players = game_manager.get_players()
		print("Final hand states:")
		for i in range(4):
			var status = "OUT OF CARDS (WINNER)" if i == game_state.winner else "%d cards remaining" % players[i].get_card_count()
			print("  Player %d: %s" % [i, status])
			if not players[i].is_empty():
				print("    Remaining: %s" % players[i]._to_string())

		# Final confirmation
		print("\n" + "-".repeat(80))
		print("🏆 Player %d wins the game! 🏆" % game_state.winner)
		print("-".repeat(80) + "\n")
	else:
		print("No winner determined!")
		print("\n" + "=".repeat(80) + "\n")

func _show_victory_overlay():
	"""Show victory screen overlay with padding and bounds checking"""
	# Print game over summary
	_print_game_over_summary()

	# Create a VBoxContainer to hold both elements
	var vbox = VBoxContainer.new()
	vbox.layout_mode = 2
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.custom_minimum_size = Constants.VICTORY_OVERLAY_SIZE

	# Position at the winning player's hand
	var winner_hand_pos = player_hand_nodes[game_state.winner].position
	var overlay_width = vbox.custom_minimum_size.x
	var overlay_height = vbox.custom_minimum_size.y
	var viewport_size = get_viewport().get_visible_rect().size

	# Calculate position with bounds checking for padding
	var position_x = winner_hand_pos.x - overlay_width / 2
	var position_y = winner_hand_pos.y - overlay_height / 2

	# Clamp to keep padding from edges
	position_x = clamp(position_x, Constants.VICTORY_OVERLAY_PADDING, viewport_size.x - overlay_width - Constants.VICTORY_OVERLAY_PADDING)
	position_y = clamp(position_y, Constants.VICTORY_OVERLAY_PADDING, viewport_size.y - overlay_height - Constants.VICTORY_OVERLAY_PADDING)

	vbox.position = Vector2(position_x, position_y)

	victory_overlay = vbox

	# WINNER text label
	var winner_label = Label.new()
	winner_label.text = "WINNER"
	winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_label.add_theme_font_size_override("font_size", Constants.VICTORY_LABEL_FONT_SIZE)
	winner_label.add_theme_color_override("font_color", Color.WHITE)
	winner_label.custom_minimum_size = Constants.VICTORY_LABEL_SIZE
	winner_label.add_theme_constant_override("margin_left", Constants.VICTORY_LABEL_MARGIN)
	winner_label.add_theme_constant_override("margin_right", Constants.VICTORY_LABEL_MARGIN)
	vbox.add_child(winner_label)

	# Play Again button
	var reset_button = Button.new()
	reset_button.text = "Play Again"
	reset_button.custom_minimum_size = Constants.VICTORY_BUTTON_SIZE
	reset_button.pressed.connect(_on_reset_pressed)
	vbox.add_child(reset_button)

	add_child(victory_overlay)

func _on_reset_pressed():
	"""Reset game and start over"""
	# Clear all card visuals
	for visual_array in card_visuals:
		for card_visual in visual_array:
			if is_instance_valid(card_visual):
				card_visual.queue_free()
	card_visuals.clear()

	# Clear table display
	for child in table_display.get_children():
		child.queue_free()

	# Reset game
	game_manager.reset_game()
	game_state = game_manager.get_current_state()

	# Redisplay hands
	display_hands()

	# Show start button again
	$StartButton.visible = true

	# Remove victory overlay
	if victory_overlay:
		victory_overlay.queue_free()

	is_playing = false
	game_over = false
