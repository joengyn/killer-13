class_name Deck
## Manages a standard 52-card deck for Tiến Lên
##
## Creates all 52 cards (4 suits × 13 ranks), shuffles them, and deals
## cards to players. Uses Fisher-Yates algorithm for proper randomization.

var cards: Array[Card] = []

## Create all 52 cards in the deck
func _init() -> void:
	# Create all 52 cards (4 suits × 13 ranks)
	for suit_val in range(4):
		for rank_val in range(13):
			cards.append(Card.new(rank_val, suit_val))

## Shuffle the deck using Fisher-Yates algorithm
func shuffle() -> void:
	var n = cards.size()
	for i in range(n - 1, 0, -1):
		var j = randi() % (i + 1)
		# Swap
		var temp = cards[i]
		cards[i] = cards[j]
		cards[j] = temp

## Deal cards to players (13 cards per player)
## Returns array of hands, one per player
func deal(num_players: int = 4) -> Array[Array]:
	var hands: Array[Array] = []

	# Initialize empty hands
	for i in range(num_players):
		hands.append(Array())

	# Deal 13 cards to each player
	var card_index = 0
	for player in range(num_players):
		var hand = Array()
		for i in range(13):
			hand.append(cards[card_index])
			card_index += 1
		hands[player] = hand

	return hands
