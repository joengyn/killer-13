class_name Combination
## Validates card combinations and determines their type and strength
##
## Handles all valid combination types in Tiến Lên: singles, pairs, triples,
## straights, and bombs (4-of-a-kind and consecutive pairs). Provides comparison
## logic to determine if one combination beats another.

## Combination type enumeration
enum Type {
	INVALID,
	SINGLE,                # 1 card
	PAIR,                  # 2 cards of same rank
	TRIPLE,                # 3 cards of same rank
	STRAIGHT,              # 4+ consecutive ranks (no 2s allowed)
	QUAD,                  # Four of a kind (bomb)
	CONSECUTIVE_PAIRS      # 3+ consecutive pairs (bomb)
}

## Detect the type of card combination
## Returns Type enum value indicating the combination type
static func detect_type(cards: Array) -> Type:
	if cards.is_empty():
		return Type.INVALID

	# Early exit for single cards (no sorting needed)
	if cards.size() == 1:
		return Type.SINGLE

	# Sort once for all further checks
	var sorted_cards = cards.duplicate()
	(sorted_cards as Array[Card]).sort_custom(func(a: Card, b: Card) -> bool:
		return a.rank < b.rank
	)

	# Check by size
	match cards.size():
		2:
			if (sorted_cards[0] as Card).rank == (sorted_cards[1] as Card).rank:
				return Type.PAIR
			return Type.INVALID

		3:
			if (sorted_cards[0] as Card).rank == (sorted_cards[1] as Card).rank and (sorted_cards[1] as Card).rank == (sorted_cards[2] as Card).rank:
				return Type.TRIPLE
			return Type.INVALID

		4:
			# Check for four of a kind
			var first_rank = (sorted_cards[0] as Card).rank
			var all_same = true
			for card in sorted_cards:
				if (card as Card).rank != first_rank:
					all_same = false
					break
			if all_same:
				return Type.QUAD

			# Check for straight (sorted cards already prepared)
			if is_straight(sorted_cards):
				return Type.STRAIGHT

			return Type.INVALID

	# 5+ cards: check for straight or consecutive pairs
	if cards.size() >= 5:
		if is_straight(sorted_cards):
			return Type.STRAIGHT

		# Check for consecutive pairs (special bomb)
		if is_consecutive_pairs(sorted_cards):
			return Type.CONSECUTIVE_PAIRS

	return Type.INVALID

## Check if cards form a valid straight (4+ consecutive ranks, no 2s allowed)
## Accepts pre-sorted cards for efficiency
static func is_straight(cards: Array) -> bool:
	if cards.size() < 4:
		return false

	# Straights cannot contain 2s
	for card in cards:
		if (card as Card).rank == Card.Rank.TWO:
			return false

	# Check if consecutive (assumes cards are already sorted)
	for i in range(1, cards.size()):
		var prev_rank = (cards[i - 1] as Card).rank
		var curr_rank = (cards[i] as Card).rank
		if curr_rank != prev_rank + 1:
			return false

	return true

## Check if cards form consecutive pairs (bomb type)
## e.g., 3-3 4-4 5-5 or 3-3 4-4 5-5 6-6 (6+ cards, must be pairs in consecutive ranks)
## Accepts pre-sorted cards for efficiency
static func is_consecutive_pairs(cards: Array) -> bool:
	if cards.size() < 6 or cards.size() % 2 != 0:
		return false

	# Check pairs and consecutive ranks (assumes cards are already sorted)
	for i in range(0, cards.size(), 2):
		var first_card = cards[i] as Card
		var second_card = cards[i + 1] as Card

		# Must be a pair
		if first_card.rank != second_card.rank:
			return false

		# Check if next pair is consecutive
		if i + 2 < cards.size():
			var next_card = cards[i + 2] as Card
			if next_card.rank != first_card.rank + 1:
				return false

	return true

## Check if a combination is valid (returns true if it's a recognized combination type)
static func is_valid(cards: Array) -> bool:
	return detect_type(cards) != Type.INVALID

## Check if a combination includes the 3 of spades (required for first turn validation)
static func contains_three_of_spades(cards: Array) -> bool:
	for card in cards:
		if (card as Card).is_three_of_spades():
			return true
	return false

## Get the "strength" of a combination for comparison purposes
## Returns the rank of the highest or representative card
static func get_strength(cards: Array) -> int:
	if cards.is_empty():
		return -1

	var sorted_cards = cards.duplicate()
	(sorted_cards as Array[Card]).sort_custom(func(a: Card, b: Card) -> bool:
		return a.rank < b.rank
	)

	# For straights, use the high card
	# For pairs/triples/quads, use the rank value
	return (sorted_cards[-1] as Card).rank

## Check if one combination beats another
## Returns true if combo1 beats combo2 according to game rules
static func beats(combo1: Array, combo2: Array) -> bool:
	var type1 = detect_type(combo1)
	var type2 = detect_type(combo2)

	# Must be same type or bomb vs something
	if type1 == Type.INVALID or type2 == Type.INVALID:
		return false

	# Same type, compare strength
	if type1 == type2:
		return get_strength(combo1) > get_strength(combo2)

	# Different types: only bombs can beat non-bombs
	# QUAD (4 of a kind) and CONSECUTIVE_PAIRS can beat 2s
	if type1 == Type.QUAD or type1 == Type.CONSECUTIVE_PAIRS:
		# Check if combo2 is a 2
		if type2 == Type.SINGLE:
			var card = combo2[0] as Card
			return card.rank == Card.Rank.TWO
		if type2 == Type.PAIR:
			var first_card = combo2[0] as Card
			var second_card = combo2[1] as Card
			return first_card.rank == Card.Rank.TWO and second_card.rank == Card.Rank.TWO

	return false

# Get a string representation of combo type
static func type_to_string(combo_type: Type) -> String:
	match combo_type:
		Type.SINGLE:
			return "Single"
		Type.PAIR:
			return "Pair"
		Type.TRIPLE:
			return "Triple"
		Type.STRAIGHT:
			return "Straight"
		Type.QUAD:
			return "Four of a Kind"
		Type.CONSECUTIVE_PAIRS:
			return "Consecutive Pairs Bomb"
		_:
			return "Invalid"

## Get a string representation of a combination
static func combo_to_string(cards: Array) -> String:
	var result = ""
	for i in range(cards.size()):
		result += (cards[i] as Card)._to_string()
		if i < cards.size() - 1:
			result += " "
	return result
