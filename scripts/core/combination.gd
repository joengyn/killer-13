class_name Combination
## Combination validator and comparator for Tiến Lên card game rules
##
## Core game logic class that validates card combinations, detects their type, and
## determines which combinations beat others. Handles all Tiến Lên combo types:
## singles, pairs, triples, straights (3-A only), and bombs (quads, consecutive pairs).
##
## Key rules:
## - Same type combos are compared by strength (highest card wins)
## - Bombs (quads, consecutive pairs) can beat single/pair 2s
## - Straights cannot contain 2s
## - All methods are static - this class has no instance data

## Enumeration of all valid combination types in Tiến Lên
enum Type {
	INVALID,
	SINGLE,                # 1 card
	PAIR,                  # 2 cards of same rank
	TRIPLE,                # 3 cards of same rank
	STRAIGHT,              # 4+ consecutive ranks (no 2s allowed)
	QUAD,                  # Four of a kind (bomb)
	CONSECUTIVE_PAIRS      # 3+ consecutive pairs (bomb)
}

## Analyze an array of cards and detect its combination type
## @param cards: Array of Card objects to analyze
## @return: Type enum value (INVALID if not a valid combination)
static func detect_type(cards: Array[Card]) -> Type:
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

## Check if cards form a valid straight (4+ consecutive ranks, no 2s)
## Straights in Tiến Lên can only use ranks 3-A; 2s are not allowed in straights.
## @param cards: Pre-sorted array of Card objects (assumed sorted by rank)
## @return: True if cards form a valid straight
static func is_straight(cards: Array[Card]) -> bool:
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

## Check if cards form consecutive pairs (a bomb combination)
## Must have 3+ pairs (6+ cards total) with consecutive ranks
## Example: 3♠3♥ 4♦4♣ 5♠5♥ (three pairs: 3-3, 4-4, 5-5)
## @param cards: Pre-sorted array of Card objects (assumed sorted by rank)
## @return: True if cards form valid consecutive pairs
static func is_consecutive_pairs(cards: Array[Card]) -> bool:
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

## Check if an array of cards forms any valid combination
## @param cards: Array of Card objects to validate
## @return: True if the combination is valid (not INVALID type)
static func is_valid(cards: Array[Card]) -> bool:
	return detect_type(cards) != Type.INVALID

## Check if a combination contains the 3 of spades
## Used for first turn validation (3♠ is required on game's opening play)
## @param cards: Array of Card objects to check
## @return: True if 3♠ is present in the combination
static func contains_three_of_spades(cards: Array[Card]) -> bool:
	for card in cards:
		if (card as Card).is_three_of_spades():
			return true
	return false

## Calculate the numeric strength of a combination for comparison
## Strength is based on the highest card: (rank * 10) + suit
## This ensures rank is primary factor, suit is tiebreaker
## @param cards: Array of Card objects
## @return: Integer strength value (-1 if empty, higher = stronger)
static func get_strength(cards: Array[Card]) -> int:
	if cards.is_empty():
		return -1

	var sorted_cards = cards.duplicate()
	(sorted_cards as Array[Card]).sort_custom(func(a: Card, b: Card) -> bool:
		# Sort by rank first, then by suit for same rank
		if a.rank != b.rank:
			return a.rank < b.rank
		return a.suit < b.suit
	)

	# Get the highest card
	var highest_card = sorted_cards[-1] as Card

	# Return composite strength: rank * 10 + suit
	# This ensures rank is primary, suit is tiebreaker
	return highest_card.rank * 10 + highest_card.suit

## Check if one combination beats another according to Tiến Lên rules
## Rules:
## - Same type: Compare strength (higher wins)
## - Bombs (quad/consecutive pairs) can beat single or pair 2s
## - Different types otherwise: Cannot beat
## @param combo1: First combination (attacker)
## @param combo2: Second combination (defender)
## @return: True if combo1 beats combo2
static func beats(combo1: Array[Card], combo2: Array[Card]) -> bool:
	var type1 = detect_type(combo1)
	var type2 = detect_type(combo2)

	# Must be same type or bomb vs something
	if type1 == Type.INVALID or type2 == Type.INVALID:
		return false

	# Same type, compare strength
	if type1 == type2:
		# For straights and consecutive pairs, size must also be equal
		if type1 == Type.STRAIGHT or type1 == Type.CONSECUTIVE_PAIRS:
			if combo1.size() != combo2.size():
				return false
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

## Convert a combination type enum to a human-readable string
## @param combo_type: Type enum value
## @return: String description of the type
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

## Convert a combination to a space-separated string (e.g., "3♠ 4♠ 5♠")
## @param cards: Array of Card objects
## @return: String representation with card symbols
static func combo_to_string(cards: Array[Card]) -> String:
	var inner_result = ""
	for i in range(cards.size()):
		inner_result += (cards[i] as Card)._to_string()
		if i < cards.size() - 1:
			inner_result += " "
	return "[" + inner_result + "]"
