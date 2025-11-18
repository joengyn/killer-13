class_name Deck
## Deck - Creates and manages a standard 52-card deck for Tiến Lên
##
## Handles deck creation (all combinations of 13 ranks × 4 suits),
## shuffling (Fisher-Yates algorithm), and dealing to multiple players.

## Array of all 52 Card objects in the deck
var cards: Array[Card] = []

## Initialize a new deck with all 52 cards
func _init() -> void:
	_create_deck()

## Internal: Create all 52 cards (13 ranks × 4 suits)
func _create_deck() -> void:
	for suit in [Card.Suit.SPADES, Card.Suit.HEARTS, Card.Suit.DIAMONDS, Card.Suit.CLUBS]:
		for rank in [Card.Rank.THREE, Card.Rank.FOUR, Card.Rank.FIVE, Card.Rank.SIX,
					 Card.Rank.SEVEN, Card.Rank.EIGHT, Card.Rank.NINE, Card.Rank.TEN,
					 Card.Rank.JACK, Card.Rank.QUEEN, Card.Rank.KING, Card.Rank.ACE, Card.Rank.TWO]:
			cards.append(Card.new(rank, suit))

## Shuffle the deck using Fisher-Yates algorithm (randomizes card order)
func shuffle() -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j = randi() % (i + 1)
		var temp = cards[i]
		cards[i] = cards[j]
		cards[j] = temp

## Deal 13 cards to each player in round-robin fashion
## @param num_players: Number of players to deal to (typically 4)
## @return: Array of Arrays, where each sub-array contains 13 Card objects for one player
func deal(num_players: int) -> Array:
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
