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
	$VBoxContainer/HBoxContainer/StartButton.pressed.connect(_on_start_pressed)

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
			card_visual.set_card(card)

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
	var pass_button = Button.new()
	pass_button.text = "Pass"
	pass_button.custom_minimum_size = Constants.BUTTON_SIZE
	pass_button.position = viewport_size - Vector2(Constants.BUTTON_SIZE.x * 2 + Constants.BUTTON_SPACING + Constants.BUTTON_MARGIN, Constants.BUTTON_SIZE.y + Constants.BUTTON_MARGIN)
	pass_button.pressed.connect(_on_pass_pressed)
	add_child(pass_button)

	# Play button (right)
	var play_button = Button.new()
	play_button.text = "Play"
	play_button.custom_minimum_size = Constants.BUTTON_SIZE
	play_button.position = viewport_size - Vector2(Constants.BUTTON_SIZE.x + Constants.BUTTON_MARGIN, Constants.BUTTON_SIZE.y + Constants.BUTTON_MARGIN)
	play_button.pressed.connect(_on_play_pressed)
	add_child(play_button)

# ============================================================================
# GAME FLOW & INPUT
# ============================================================================

func _on_pass_pressed():
	"""Handle pass button pressed"""
	pass

func _on_play_pressed():
	"""Handle play button pressed"""
	pass

func _on_start_pressed():
	"""Start the game when Start button is clicked"""
	game_manager.start_game()
	game_state = game_manager.get_current_state()
	$VBoxContainer/HBoxContainer/StartButton.visible = false
	is_playing = true
	game_over = false
	turn_timer.start()

# ============================================================================
# TURN EXECUTION
# ============================================================================

func _on_turn_timer_timeout():
	"""Execute one turn of the game"""
	if game_over:
		turn_timer.stop()
		return

	var players = game_manager.get_players()
	var current_player = game_state.current_player
	var hand = players[current_player]

	# Get AI decision
	var is_first_turn = game_state.get_table_combo().is_empty() and game_state.consecutive_passes == 0
	var played_cards = SimpleAI.decide_play(hand, game_state, is_first_turn)

	if played_cards.is_empty():
		# Player passes
		game_state.mark_player_passed()
		print("Player %d passes" % current_player)

		# Check if all others passed (reset round)
		if game_state.all_others_passed():
			game_state.reset_round()
			# Clear table display when round resets
			for child in table_display.get_children():
				child.queue_free()
			print("Round reset!")
	else:
		# Player plays
		var is_valid = false

		if game_state.get_table_combo().is_empty():
			# First play of round - check validity
			is_valid = Combination.is_valid(played_cards)
			# First turn of game must include 3♠
			var is_first_turn_game = game_state.table_combo.is_empty() and game_state.consecutive_passes == 0
			if is_valid and is_first_turn_game:
				is_valid = Combination.contains_three_of_spades(played_cards)
		else:
			# Must beat existing combo
			is_valid = Combination.beats(played_cards, game_state.get_table_combo())

		if is_valid:
			# Remove cards from hand
			hand.remove_cards(played_cards)
			game_state.set_table_combo(played_cards)
			game_state.mark_player_played()

			# Animate cards to table and update display
			_animate_played_cards(current_player, played_cards)
			_update_table_display()

			print("Player %d plays: %s" % [current_player, Combination.combo_to_string(played_cards)])

			# Check if player won
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

			# Check if all others passed (reset round)
			if game_state.all_others_passed():
				game_state.reset_round()
				# Clear table display when round resets
				for child in table_display.get_children():
					child.queue_free()
				print("Round reset!")

	# Refresh hand display
	_refresh_hand_display()

	# Move to next player
	game_state.next_player()

# ============================================================================
# ANIMATIONS & DISPLAY UPDATES
# ============================================================================

func _animate_played_cards(player_idx: int, played_cards: Array):
	"""Animate cards from player hand to center table (runs in parallel)"""
	var tweens = []

	for card in played_cards:
		# Find the card visual from player's hand
		for card_visual in card_visuals[player_idx]:
			# Check if this visual still exists and has the matching card
			if is_instance_valid(card_visual) and card_visual.card == card:
				# Create tween animation (don't await yet)
				var tween = create_tween()
				tween.set_trans(Tween.TRANS_QUAD)
				tween.set_ease(Tween.EASE_IN_OUT)
				tween.tween_property(card_visual, "position", Vector2(0, 0), Constants.CARD_ANIMATION_DURATION)
				tweens.append(tween)
				break

	# Wait for all animations to complete
	for tween in tweens:
		await tween.finished

	# Clean up animated cards
	for card in played_cards:
		for card_visual in card_visuals[player_idx]:
			if is_instance_valid(card_visual) and card_visual.card == card:
				card_visual.queue_free()
				card_visuals[player_idx].erase(card_visual)
				break

func _update_table_display():
	"""Update the table display with current combo"""
	# Clear old cards from table
	for child in table_display.get_children():
		child.queue_free()

	# Display new cards
	var table_combo = game_state.get_table_combo()
	if table_combo.is_empty():
		return

	var x_offset = Constants.TABLE_CARD_START_X
	for card in table_combo:
		var card_visual = card_scene.instantiate()
		card_visual.set_card(card)
		card_visual.position = Vector2(x_offset, 0)
		table_display.add_child(card_visual)
		x_offset += Constants.TABLE_CARD_SPACING

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
				card_count += 1

# ============================================================================
# VICTORY & RESET
# ============================================================================

func _show_victory_overlay():
	"""Show victory screen overlay with padding and bounds checking"""
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
	$VBoxContainer/HBoxContainer/StartButton.visible = true

	# Remove victory overlay
	if victory_overlay:
		victory_overlay.queue_free()

	is_playing = false
	game_over = false
