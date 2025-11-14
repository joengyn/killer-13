extends Node2D
## PlayerHand - Manages the player's hand of cards

const CARD_SPACING: float = 115.0  # Horizontal spacing between cards
const THRESHOLD_PADDING: float = 20.0  # Extra padding around hand bounds for threshold
const HAND_Z_INDEX_BASE: int = 20  # Base z-index for hand cards (above PlayZone cards)

var _cards_in_hand: Array[Node] = []  # Track which cards are still in the hand
var _card_original_index: Dictionary = {}  # Map each card to its original scene tree index


func _ready() -> void:
	# At runtime, remove any preview cards that may exist in the scene
	for child in get_children():
		child.queue_free()


func _arrange_cards() -> void:
	"""Arrange cards in a straight horizontal line, centered (only in-hand cards)"""
	if _cards_in_hand.size() == 0:
		return

	var card_count = _cards_in_hand.size()
	# Calculate total width and center offset
	var total_width = (card_count - 1) * CARD_SPACING
	var start_x = -total_width / 2.0

	for idx in range(card_count):
		var child = _cards_in_hand[idx]
		var x = start_x + (idx * CARD_SPACING)
		child.position = Vector2(x, 0)

		# Update base position for hover animation
		var interaction = child.get_node_or_null("Interaction")
		if interaction and interaction.has_method("update_base_position"):
			interaction.update_base_position()




func _get_hand_bounds() -> Rect2:
	"""Calculate the bounding rectangle of the hand with padding"""
	var card_width = Constants.CARD_WIDTH
	var card_height = Constants.CARD_HEIGHT

	if _cards_in_hand.size() == 0:
		return Rect2(Vector2.ZERO, Vector2(card_width, card_height))

	var card_count = _cards_in_hand.size()

	# Total width of the hand
	var total_width = (card_count - 1) * CARD_SPACING + card_width
	var half_width = total_width / 2.0

	# Create bounds rect centered at origin with padding
	var bounds = Rect2(
		Vector2(-half_width - THRESHOLD_PADDING, -card_height / 2.0 - THRESHOLD_PADDING),
		Vector2(total_width + THRESHOLD_PADDING * 2, card_height + THRESHOLD_PADDING * 2)
	)

	return bounds


func _add_card_back(card: Node) -> void:
	"""Add a card back to the hand at its original position"""
	# Safety check: don't add if already in hand
	if card in _cards_in_hand:
		return

	# Find the correct insertion point based on original index
	var original_idx = _card_original_index.get(card, -1)
	if original_idx == -1:
		return

	# Insert at the position that maintains original order
	var insert_pos = 0
	for in_hand_card in _cards_in_hand:
		var in_hand_original_idx = _card_original_index.get(in_hand_card, -1)
		if in_hand_original_idx < original_idx:
			insert_pos += 1

	_cards_in_hand.insert(insert_pos, card)

	_update_z_indices()
	_arrange_cards()


func _update_z_indices() -> void:
	"""Recalculate z_indices for remaining in-hand cards"""
	for idx in range(_cards_in_hand.size()):
		_cards_in_hand[idx].z_index = HAND_Z_INDEX_BASE + idx


func add_card(card_data: Card) -> Node:
	"""Add a single card to the hand (used during dealing). Returns the created card visual node."""
	var card_visual = preload("res://scenes/card.tscn").instantiate() as Node
	add_child(card_visual)

	# Set the card data
	if card_visual.has_method("set_card"):
		card_visual.set_card(card_data)

	# Set up interaction
	var interaction = card_visual.get_node_or_null("Interaction")
	if interaction:
		interaction.is_player_card = true
		# Update base position for hover animations
		if interaction.has_method("update_base_position"):
			interaction.update_base_position()

	# Hide shadows
	if card_visual.has_method("set_shadow_visible"):
		card_visual.set_shadow_visible(false)

	# Track the card
	var new_idx = _cards_in_hand.size()
	_cards_in_hand.append(card_visual)
	_card_original_index[card_visual] = new_idx

	# Update z indices and arrange
	_update_z_indices()
	_arrange_cards()

	return card_visual


func clear_and_populate(cards: Array[Card]) -> void:
	"""Remove all child cards and populate with new Card data (runtime use)"""
	# Remove all existing card nodes
	for card in get_children():
		card.queue_free()

	_cards_in_hand.clear()
	_card_original_index.clear()

	# Create new CardVisual nodes for each card data
	for idx in range(cards.size()):
		var card_data = cards[idx]
		var card_visual = preload("res://scenes/card.tscn").instantiate() as Node
		add_child(card_visual)

		# Set the card data
		if card_visual.has_method("set_card"):
			card_visual.set_card(card_data)

		# Set up interaction
		var interaction = card_visual.get_node_or_null("Interaction")
		if interaction:
			interaction.is_player_card = true
			# Update base position for hover animations
			if interaction.has_method("update_base_position"):
				interaction.update_base_position()

		# Track the card
		_cards_in_hand.append(card_visual)
		_card_original_index[card_visual] = idx

		# Hide shadows
		if card_visual.has_method("set_shadow_visible"):
			card_visual.set_shadow_visible(false)

	# Update z indices and arrange
	_update_z_indices()
	_arrange_cards()
