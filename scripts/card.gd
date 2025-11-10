class_name Card
## Represents a single playing card with rank and suit
##
## Ranks are ordered from 3 (lowest) to 2 (highest) as per Tiến Lên rules.
## Suits are ordered from Spades (lowest) to Hearts (highest) for tiebreaking.

## Rank enum: 3 is lowest (value 0), 2 is highest (value 12)
enum Rank {
	THREE = 0,
	FOUR = 1,
	FIVE = 2,
	SIX = 3,
	SEVEN = 4,
	EIGHT = 5,
	NINE = 6,
	TEN = 7,
	JACK = 8,
	QUEEN = 9,
	KING = 10,
	ACE = 11,
	TWO = 12
}

## Suit enum: Spades is lowest, Hearts is highest
enum Suit {
	SPADES = 0,
	CLUBS = 1,
	DIAMONDS = 2,
	HEARTS = 3
}

var rank: Rank
var suit: Suit

## Construct a card with the given rank and suit
func _init(p_rank: Rank, p_suit: Suit) -> void:
	rank = p_rank
	suit = p_suit

## Convert rank enum to string symbol (e.g., THREE->3, JACK->J, TWO->2)
func rank_to_string() -> String:
	match rank:
		Rank.THREE:
			return "3"
		Rank.FOUR:
			return "4"
		Rank.FIVE:
			return "5"
		Rank.SIX:
			return "6"
		Rank.SEVEN:
			return "7"
		Rank.EIGHT:
			return "8"
		Rank.NINE:
			return "9"
		Rank.TEN:
			return "10"
		Rank.JACK:
			return "J"
		Rank.QUEEN:
			return "Q"
		Rank.KING:
			return "K"
		Rank.ACE:
			return "A"
		Rank.TWO:
			return "2"
	return ""

## Convert suit enum to symbol (♠, ♣, ♦, ♥)
func suit_to_string() -> String:
	match suit:
		Suit.SPADES:
			return "♠"
		Suit.CLUBS:
			return "♣"
		Suit.DIAMONDS:
			return "♦"
		Suit.HEARTS:
			return "♥"
	return ""

## Get full card representation (e.g., "3♠", "K♥", "2♣")
func _to_string() -> String:
	return rank_to_string() + suit_to_string()

## Compare this card to another card by rank, then suit for tiebreaking
## Returns: 1 if this > other, -1 if this < other, 0 if equal
func compare_to(other: Card) -> int:
	if rank != other.rank:
		if rank > other.rank:
			return 1
		else:
			return -1
	# Same rank, compare suit
	if suit > other.suit:
		return 1
	elif suit < other.suit:
		return -1
	else:
		return 0

## Check if this card beats another single card in ranking
func beats(other: Card) -> bool:
	return compare_to(other) > 0

## Check if this card is the 3 of Spades (required to start the game)
func is_three_of_spades() -> bool:
	return rank == Rank.THREE and suit == Suit.SPADES

## Check if this card is a 2 (highest non-bomb single card)
func is_two() -> bool:
	return rank == Rank.TWO
