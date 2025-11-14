extends Node2D
## DeckVisual - Manages the visual deck and card dealing animation

signal deal_started
signal card_dealt(card_visual: Node)

var _remaining_cards: int = 52
var _card_visuals: Array[Node] = []  # All card visuals in the deck stack
var _cards_dealt_total: int = 0  # Track total cards dealt
var _dealt_cards: Array[Node] = []  # Animated cards to clean up after dealing

func _ready() -> void:
	# Create the initial deck of 52 card backs at runtime
	for i in range(52):
		var card_visual = preload("res://scenes/card.tscn").instantiate() as Node
		add_child(card_visual)

		# Position all cards in a stack (same position)
		card_visual.position = Vector2.ZERO

		# Set to show card back
		if card_visual.has_method("set_show_back"):
			card_visual.set_show_back(true)

		# Hide shadows for deck cards
		if card_visual.has_method("set_shadow_visible"):
			card_visual.set_shadow_visible(false)

		# Add to card visuals array
		_card_visuals.append(card_visual)

	_remaining_cards = _card_visuals.size()

	# Add interactivity at runtime
	_setup_click_detection()


func _setup_click_detection() -> void:
	"""Add an Area2D for click detection on the deck"""
	# Check if Area2D already exists
	var area = get_node_or_null("Area2D")
	if area == null:
		area = Area2D.new()
		area.name = "Area2D"
		add_child(area)

		# Create collision shape
		var collision = CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		var shape = RectangleShape2D.new()
		shape.size = Vector2(
			Constants.CARD_BASE_WIDTH * 1.5,
			Constants.CARD_BASE_HEIGHT * 1.5
		)
		collision.shape = shape
		area.add_child(collision)

		# Connect click detection
		if not area.input_event.is_connected(_on_deck_clicked):
			area.input_event.connect(_on_deck_clicked)


func _on_deck_clicked(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	"""Handle deck click"""
	if event is InputEventMouseButton and event.pressed:
		emit_signal("deal_started")


func deal_card_animated(target_pos: Vector2, player_idx: int) -> void:
	"""
	Animate a card from deck to target position
	This is purely visual - the card is a temporary animation effect
	Args:
		target_pos: Where the card should animate to
		player_idx: Which player (0=player, 1=top, 2=left, 3=right)
	"""
	# Create a temporary card visual for the dealing animation
	var card: Node

	# First 47 cards: instantiate temporary cards, deck stays full
	# Last 5 cards (48-52): pop from the deck visual stack
	if _cards_dealt_total >= 47 and _card_visuals.size() > 0:
		# Last 5 cards: use and remove from the placeholder deck cards
		card = _card_visuals.pop_back()
		_remaining_cards = _card_visuals.size()
	else:
		# First 47 cards: instantiate new temporary cards
		card = preload("res://scenes/card.tscn").instantiate() as Node
		add_child(card)
		card.position = Vector2.ZERO
		if card.has_method("set_show_back"):
			card.set_show_back(true)

	# Increment total dealt count
	_cards_dealt_total += 1

	# Always show card back during dealing animation
	if card.has_method("set_shadow_visible"):
		card.set_shadow_visible(false)

	# Animate from deck position to target with rotation for left/right
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)

	# Set target rotation based on player position
	var target_rotation = 0.0
	if player_idx == 2:  # Left
		target_rotation = PI / 2
	elif player_idx == 3:  # Right
		target_rotation = -PI / 2

	tween.tween_property(card, "global_position", target_pos, 0.15)
	if target_rotation != 0.0:
		tween.parallel().tween_property(card, "rotation", target_rotation, 0.15)

	# Wait for animation to complete
	await tween.finished
	emit_signal("card_dealt", card)

	# Store the dealt card for cleanup at the end of dealing (prevents disappear/reappear glitch)
	_dealt_cards.append(card)


func get_remaining_card_count() -> int:
	"""Return how many cards are left in the deck"""
	return _remaining_cards


func cleanup_dealt_cards() -> void:
	"""Clean up all animated cards after dealing completes"""
	for card in _dealt_cards:
		card.queue_free()
	_dealt_cards.clear()
