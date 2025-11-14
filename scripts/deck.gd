class_name Deck
## Deck data class - Creates and manages a deck of 52 playing cards

var cards: Array[Card] = []

func _init():
	_create_deck()

func _create_deck() -> void:
	"""Create all 52 cards in a standard deck"""
	for suit in [Card.Suit.SPADES, Card.Suit.HEARTS, Card.Suit.DIAMONDS, Card.Suit.CLUBS]:
		for rank in [Card.Rank.THREE, Card.Rank.FOUR, Card.Rank.FIVE, Card.Rank.SIX,
					 Card.Rank.SEVEN, Card.Rank.EIGHT, Card.Rank.NINE, Card.Rank.TEN,
					 Card.Rank.JACK, Card.Rank.QUEEN, Card.Rank.KING, Card.Rank.ACE, Card.Rank.TWO]:
			cards.append(Card.new(rank, suit))

func shuffle() -> void:
	"""Shuffle the deck using Fisher-Yates algorithm"""
	for i in range(cards.size() - 1, 0, -1):
		var j = randi() % (i + 1)
		var temp = cards[i]
		cards[i] = cards[j]
		cards[j] = temp

func deal(num_players: int) -> Array:
	"""
	Deal cards to players
	Returns Array of Arrays, each containing 13 Card objects for a player
	"""
	var hands: Array = []

	# Create empty hand arrays for each player
	for i in range(num_players):
		var hand: Array[Card] = []
		hands.append(hand)

	# Deal 13 cards to each player
	var card_idx = 0
	for deal_round in range(13):
		for player_idx in range(num_players):
			if card_idx < cards.size():
				(hands[player_idx] as Array[Card]).append(cards[card_idx])
				card_idx += 1

	return hands
