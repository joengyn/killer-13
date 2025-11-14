class_name Card
## Represents an immutable playing card with rank and suit.
##
## Ranks are ordered from 3 (lowest) to 2 (highest) as per Tiến Lên rules.
## Suits are ordered from Spades (lowest) to Hearts (highest) for tiebreaking.
## See RULES.md for complete game rules and card rankings.

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

## Convert rank enum to string symbol (e.g., THREE->"3", JACK->"J", TWO->"2")
func rank_to_string() -> String:
	var rank_names = ["3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A", "2"]
	return rank_names[rank] if rank >= 0 and rank < rank_names.size() else ""

## Convert suit enum to symbol (♠, ♣, ♦, ♥)
func suit_to_string() -> String:
	var suit_names = ["♠", "♣", "♦", "♥"]
	return suit_names[suit] if suit >= 0 and suit < suit_names.size() else ""

## Get full card representation (e.g., "3♠", "K♥", "2♣")
func _to_string() -> String:
	return rank_to_string() + suit_to_string()

## Compare this card to another card by rank, then suit for tiebreaking
## Returns: 1 if this > other, -1 if this < other, 0 if equal
func compare_to(other: Card) -> int:
	if rank != other.rank:
		return 1 if rank > other.rank else -1
	if suit > other.suit:
		return 1
	elif suit < other.suit:
		return -1
	else:
		return 0

## Check if this card beats another single card in ranking
func beats(other: Card) -> bool:
	return compare_to(other) > 0

## Check if this card is a numbered card (3-10)
func is_number() -> bool:
	return rank >= Rank.THREE and rank <= Rank.TEN

## Check if this card is a face card (J, Q, K, A)
func is_face() -> bool:
	return rank >= Rank.JACK and rank <= Rank.ACE

## Get numeric height for sorting (3=3, 4=4, ..., J=11, Q=12, K=13, A=14, 2=15)
func get_height() -> int:
	if rank == Rank.TWO:
		return 15
	elif rank == Rank.ACE:
		return 14
	else:
		return rank + 3

## Check if this card is the 3 of Spades (required to start the game)
func is_three_of_spades() -> bool:
	return rank == Rank.THREE and suit == Suit.SPADES

## Check if this card is a 2 (highest non-bomb single card)
func is_two() -> bool:
	return rank == Rank.TWO

## Check if this card is identical to another card
func equals(other: Card) -> bool:
	return rank == other.rank and suit == other.suit

## Hash the card for use in dictionaries or sets
func _hash() -> int:
	return hash([rank, suit])

## Support the == operator for card comparison
func _equal(other) -> bool:
	return other is Card and equals(other)

## Create a card from a string representation (e.g., "3S", "KH", "A♠")
static func from_string(card_str: String) -> Card:
	if card_str.is_empty():
		return null

	# Extract rank (all but last character)
	var rank_str = card_str.substr(0, card_str.length() - 1).to_upper()
	# Extract suit (last character)
	var suit_str = card_str.substr(card_str.length() - 1).to_upper()

	# Map rank string to enum
	var rank_map = {
		"3": Rank.THREE, "4": Rank.FOUR, "5": Rank.FIVE, "6": Rank.SIX,
		"7": Rank.SEVEN, "8": Rank.EIGHT, "9": Rank.NINE, "10": Rank.TEN,
		"J": Rank.JACK, "Q": Rank.QUEEN, "K": Rank.KING, "A": Rank.ACE, "2": Rank.TWO
	}

	# Map suit string to enum (handles both symbols and letters)
	var suit_map = {
		"S": Suit.SPADES, "♠": Suit.SPADES,
		"C": Suit.CLUBS, "♣": Suit.CLUBS,
		"D": Suit.DIAMONDS, "♦": Suit.DIAMONDS,
		"H": Suit.HEARTS, "♥": Suit.HEARTS
	}

	if rank_str not in rank_map or suit_str not in suit_map:
		push_error("Invalid card string: %s" % card_str)
		return null

	return Card.new(rank_map[rank_str], suit_map[suit_str])
