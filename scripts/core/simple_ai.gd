class_name SimpleAI
## AI decision-making engine for CPU players in Tiến Lên
##
## Implements a conservative "play lowest valid combo" strategy for CPU opponents.
## The AI always attempts to play the weakest possible combination that beats the table,
## conserving stronger cards for later. On first turn, plays the 3♠ as required.
##
## Strategy summary:
## - First turn: Play 3♠ alone (required by game rules)
## - Empty table: Play lowest single card (start new round conservatively)
## - Table has cards: Find lowest valid combo to beat it
## - Cannot beat normally: Try bombs (quad or consecutive pairs) if table has 2s
## - Cannot beat at all: Pass
##
## All methods are static - this class has no instance state.

## ============================================================================
## MAIN DECISION LOGIC
## ============================================================================

## Decide which cards the AI should play based on current game state
## @param hand: The AI player's current hand
## @param game_state: Current game state (table combo, turn info, etc.)
## @param is_first_turn: True if this is the first turn of the entire game (3♠ required)
## @return: Array of Card objects to play, or empty array to pass
static func decide_play(hand: Hand, game_state: GameState, is_first_turn: bool) -> Array:
	# If hand is empty, player can't play
	if hand.is_empty():
		return []

	# First turn in game: must include 3♠
	if is_first_turn:
		var three_spades = hand.find_three_of_spades()
		if three_spades:
			# Start with just 3♠
			return [three_spades]

	# If table is empty, start a new round
	if game_state.get_table_combo().is_empty():
		var best_opening_play = find_best_opening_play(hand)
		return best_opening_play

	# Try to beat the table combo
	var table_combo = game_state.get_table_combo()
	var combo_type = Combination.detect_type(table_combo)

	var all_beating_combos = find_all_beating_combos(hand, table_combo)
	var best_play: Array = []
	var highest_score = -INF

	for play in all_beating_combos:
		var score = evaluate_play(play as Array[Card], hand)
		if score > highest_score:
			highest_score = score
			best_play = play

	if not best_play.is_empty():
		# --- Strategic Passing Logic ---
		# If the AI has many cards and the best play uses high-value cards unnecessarily,
		# consider passing to save them.
		var should_consider_strategic_pass = hand.get_card_count() > 6 # Arbitrary threshold for "many cards"
		var best_play_uses_high_cards = _contains_high_value_cards(best_play)
		var table_has_twos = _table_contains_twos(table_combo)

		# Only consider strategic pass if not forced to play a 2 (i.e., table doesn't have 2s)
		# and if the best play would use high cards.
		if should_consider_strategic_pass and best_play_uses_high_cards and not table_has_twos:
			# Evaluate the "cost" of playing best_play vs. passing
			var play_cost = _calculate_play_cost(best_play)
			var pass_benefit = _calculate_pass_benefit(hand) # Benefit of saving cards

			# If the benefit of passing outweighs the cost of playing, then pass
			if pass_benefit > play_cost:
				return [] # Return empty array to indicate a pass

		return best_play

	# If we couldn't beat it normally, check if table has a 2 and try bombs
	# This bomb logic is a special case and should still be considered if no other plays are found
	if combo_type == Combination.Type.SINGLE or combo_type == Combination.Type.PAIR:
		var first_card = table_combo[0] as Card
		if first_card.is_two():
			var bomb = find_lowest_beating_bomb(hand, table_combo) # find_lowest_beating_bomb still useful for specific bomb logic
			if bomb and not bomb.is_empty():
				return bomb

	# Can't beat it, pass
	return []

## Helper to check if a combo contains high-value cards (2s or Aces)
static func _contains_high_value_cards(combo: Array) -> bool:
	for card in combo:
		if card.rank == Card.Rank.TWO or card.rank == Card.Rank.ACE:
			return true
	return false

## Helper to check if the table combo contains 2s
static func _table_contains_twos(table_combo: Array) -> bool:
	for card in table_combo:
		if card.rank == Card.Rank.TWO:
			return true
	return false

## Calculate a "cost" for playing a combo, higher for valuable cards
static func _calculate_play_cost(play_cards: Array) -> int:
	var cost = 0
	for card in play_cards:
		if card.rank == Card.Rank.TWO:
			cost += 100 # High cost for 2s
		elif card.rank == Card.Rank.ACE:
			cost += 50  # Moderate cost for Aces
		elif card.rank >= Card.Rank.TEN: # 10, J, Q, K
			cost += 10  # Small cost for other high cards
	return cost

## Calculate a "benefit" for passing, based on cards saved
static func _calculate_pass_benefit(hand: Hand) -> int:
	var benefit = 0
	# The more high cards we have, the more beneficial it is to save them
	for card in hand.cards:
		if card.rank == Card.Rank.TWO:
			benefit += 70 # Benefit from saving a 2
		elif card.rank == Card.Rank.ACE:
			benefit += 30 # Benefit from saving an Ace
	# If we have many cards, the benefit of saving is higher
	benefit += hand.get_card_count() * 5
	return benefit

## ============================================================================
## COMBO BEATING LOGIC
## ============================================================================

## Assign a strategic score to a given play
## Higher score means a better play.
static func evaluate_play(play_cards: Array[Card], hand: Hand) -> int:
	var score = 0

	# Base score: prioritize playing more cards
	score += play_cards.size() * 100

	# Penalty for high cards (2s, Aces) if not ending the game or bombing
	var is_bomb = Combination.detect_type(play_cards) == Combination.Type.QUAD or \
				  Combination.detect_type(play_cards) == Combination.Type.CONSECUTIVE_PAIRS
	var is_emptying_hand = (hand.get_card_count() - play_cards.size()) == 0

	# Calculate penalties for high cards
	for i in range(play_cards.size()):
		var card = play_cards[i] as Card
		if card.rank == Card.Rank.TWO:
			if not is_bomb and not is_emptying_hand:
				score -= 500 # Heavy penalty for playing 2s unnecessarily
		elif card.rank == Card.Rank.ACE:
			if not is_emptying_hand:
				score -= 200 # Moderate penalty for playing Aces unnecessarily

	# Bonus for playing low cards (3s, 4s, 5s)
	for i in range(play_cards.size()):
		var card = play_cards[i] as Card
		if card.rank <= Card.Rank.FIVE: # 3, 4, 5
			score += 20 # Small bonus for getting rid of low cards

	# Penalty for cards remaining in hand (fewer cards left is better)
	score -= (hand.get_card_count() - play_cards.size()) * 10

	# Bonus for emptying hand
	if is_emptying_hand:
		score += 1000 # Significant bonus for winning the round

	return score


## Find all valid combinations from the hand that can beat the table combo
static func find_all_beating_combos(hand: Hand, table_combo: Array[Card]) -> Array:
	var beating_combos: Array = []

	var all_singles = _find_all_singles(hand)
	for combo in all_singles:
		if Combination.beats(combo as Array[Card], table_combo):
			beating_combos.append(combo)

	var all_pairs = _find_all_pairs(hand)
	for combo in all_pairs:
		if Combination.beats(combo as Array[Card], table_combo):
			beating_combos.append(combo)

	var all_triples = _find_all_triples(hand)
	for combo in all_triples:
		if Combination.beats(combo as Array[Card], table_combo):
			beating_combos.append(combo)

	var all_quads = _find_all_quads(hand)
	for combo in all_quads:
		if Combination.beats(combo as Array[Card], table_combo):
			beating_combos.append(combo)

	var all_straights = _find_all_straights(hand)
	for combo in all_straights:
		if Combination.beats(combo as Array[Card], table_combo):
			beating_combos.append(combo)

	var all_consecutive_pairs = _find_all_consecutive_pairs(hand)
	for combo in all_consecutive_pairs:
		if Combination.beats(combo as Array[Card], table_combo):
			beating_combos.append(combo)

	return beating_combos

## Find the lowest valid combination that beats the table combo
## Delegates to specialized methods based on table combination type
## @param hand: The AI player's hand
## @param table_combo: Current cards on the table to beat
## @param table_type: Type of the table combination
## @return: Array of cards that beats the table, or empty if cannot beat
static func find_lowest_beating_combo(hand: Hand, table_combo: Array, table_type: Combination.Type) -> Array:
	match table_type:
		Combination.Type.SINGLE:
			return find_lowest_beating_single(hand, table_combo[0])

		Combination.Type.PAIR:
			return find_lowest_beating_pair(hand, table_combo)

		Combination.Type.TRIPLE:
			return find_lowest_beating_triple(hand, table_combo)

		Combination.Type.STRAIGHT:
			return find_lowest_beating_straight(hand, table_combo)

		Combination.Type.QUAD:
			return find_lowest_beating_bomb(hand, table_combo)

		Combination.Type.CONSECUTIVE_PAIRS:
			return find_lowest_beating_bomb(hand, table_combo)

	return []

## Find the weakest single card in hand that beats the table card
## @param hand: The AI player's hand
## @param table_card: Single card on the table to beat
## @return: Array containing one card, or empty if cannot beat
static func find_lowest_beating_single(hand: Hand, table_card: Card) -> Array[Card]:
	var lowest: Card = null
	for card in hand.cards:
		if card.beats(table_card):
			if lowest == null or card.compare_to(lowest) < 0:
				lowest = card
	# Only return if we found a card
	if lowest:
		return [lowest]
	return []

## Find the weakest pair in hand that beats the table pair
## @param hand: The AI player's hand
## @param table_combo: Pair on the table to beat
## @return: Array containing two cards of same rank, or empty if cannot beat
static func find_lowest_beating_pair(hand: Hand, table_combo: Array) -> Array[Card]:
	var table_rank = (table_combo[0] as Card).rank

	# Find all pairs in hand
	for rank in range(table_rank + 1, 13):
		var cards = hand.get_cards_by_rank(rank)
		if cards.size() >= 2:
			return [cards[0], cards[1]]

	return []

## Find the weakest triple in hand that beats the table triple
## @param hand: The AI player's hand
## @param table_combo: Triple on the table to beat
## @return: Array containing three cards of same rank, or empty if cannot beat
static func find_lowest_beating_triple(hand: Hand, table_combo: Array) -> Array[Card]:
	var table_rank = (table_combo[0] as Card).rank

	# Find all triples in hand
	for rank in range(table_rank + 1, 13):
		var cards = hand.get_cards_by_rank(rank)
		if cards.size() >= 3:
			return [cards[0], cards[1], cards[2]]

	return []

## Find the weakest straight in hand that beats the table straight
## Tries same-length straights first, then longer ones
## @param hand: The AI player's hand
## @param table_combo: Straight on the table to beat
## @return: Array of cards forming a straight, or empty if cannot beat
static func find_lowest_beating_straight(hand: Hand, table_combo: Array) -> Array[Card]:
	var table_len = table_combo.size()
	var table_high_rank = (table_combo[-1] as Card).rank

	# For simplicity, try straights of same length first, then longer ones
	# Find straights starting from higher base ranks
	for start_rank in range(table_high_rank, 13):
		var straight = try_build_straight(hand, start_rank, table_len)
		if not straight.is_empty():
			return straight

	# Try longer straights if we can't match
	for longer_len in range(table_len + 1, 10):
		for start_rank in range(0, 13 - longer_len):
			var straight = try_build_straight(hand, start_rank, longer_len)
			if not straight.is_empty():
				return straight

	return []

## ============================================================================
## HELPER METHODS
## ============================================================================

## Attempt to build a straight of specified length starting from a given rank
## @param hand: The AI player's hand
## @param start_rank: Starting rank for the straight (Card.Rank enum value)
## @param length: Number of consecutive cards needed
## @return: Array of cards forming the straight, or empty if cannot build
static func try_build_straight(hand: Hand, start_rank: int, length: int) -> Array[Card]:
	if start_rank + length > 13:
		return []  # Can't build straight that long from this rank

	var straight: Array[Card] = []
	for i in range(length):
		var rank = start_rank + i
		if rank == Card.Rank.TWO:
			return []  # Straights can't contain 2s

		var cards = hand.get_cards_by_rank(rank)
		if cards.is_empty():
			return []  # Missing a rank
		straight.append(cards[0])

	return straight

## Find a bomb (quad or consecutive pairs) to beat the table
## Bombs can beat 2s when normal plays cannot
## @param hand: The AI player's hand
## @param table_combo: Cards on the table (typically contains a 2)
## @return: Array forming a bomb combo, or empty if no bomb available
static func find_lowest_beating_bomb(hand: Hand, table_combo: Array) -> Array[Card]:
	# First, try 4 of a kind
	for rank in range(0, 13):
		var cards = hand.get_cards_by_rank(rank)
		if cards.size() == 4:
			# Check if it beats the table
			if Combination.beats(cards, table_combo):
				return [cards[0], cards[1], cards[2], cards[3]]

	# Then try consecutive pairs
	for start_rank in range(0, 11):  # Start from 0, go up to 10 (can have at most 4 pairs)
		var consecutive = try_build_consecutive_pairs(hand, start_rank, 3)
		if not consecutive.is_empty() and Combination.beats(consecutive, table_combo):
			return consecutive

	return []

## Find all possible quads (four of a kind) in the hand
static func _find_all_quads(hand: Hand) -> Array:
	var all_quads: Array = []
	for rank in range(Card.Rank.THREE, Card.Rank.TWO + 1): # All ranks
		var cards_of_rank = hand.get_cards_by_rank(rank)
		if cards_of_rank.size() >= 4:
			var quad_combo: Array[Card] = [cards_of_rank[0], cards_of_rank[1], cards_of_rank[2], cards_of_rank[3]]
			all_quads.append(quad_combo)
	return all_quads

## Find all possible consecutive pairs (bombs) in the hand
static func _find_all_consecutive_pairs(hand: Hand) -> Array:
	var all_consecutive_pairs: Array = []
	# Iterate through possible starting ranks (3 to King, as Ace/2 cannot start a 3-pair consecutive)
	for start_rank in range(Card.Rank.THREE, Card.Rank.KING + 1):
		# Try to build consecutive pairs of length 3 or more
		for num_pairs in range(3, 7): # Max 6 pairs (12 cards), but 3-7 is reasonable range
			var consecutive = try_build_consecutive_pairs(hand, start_rank, num_pairs)
			if not consecutive.is_empty():
				all_consecutive_pairs.append(consecutive)
	return all_consecutive_pairs

## Find all possible singles in the hand
static func _find_all_singles(hand: Hand) -> Array:
	var all_singles: Array = []
	for card in hand.cards:
		var single_combo: Array[Card] = [card]
		all_singles.append(single_combo)
	return all_singles

## Find the best combination to play when the table is empty
## Prioritizes straights > triples > pairs > lowest single
static func find_best_opening_play(hand: Hand) -> Array[Card]:
	# 1. Prioritize playing the lowest single card
	var lowest_single = hand.get_lowest_card()
	if lowest_single:
		return [lowest_single]

	# 2. Then, try to play the lowest pair
	var all_pairs = _find_all_pairs(hand)
	if not all_pairs.is_empty():
		all_pairs.sort_custom(func(a, b):
			return Combination.get_strength(a) < Combination.get_strength(b) # Lowest strength first
		)
		return all_pairs[0]

	# 3. Then, try to play the lowest triple
	var all_triples = _find_all_triples(hand)
	if not all_triples.is_empty():
		all_triples.sort_custom(func(a, b):
			return Combination.get_strength(a) < Combination.get_strength(b) # Lowest strength first
		)
		return all_triples[0]

	# 4. Finally, try to play the lowest straight
	var all_straights = _find_all_straights(hand)
	if not all_straights.is_empty():
		all_straights.sort_custom(func(a, b):
			if a.size() != b.size():
				return a.size() < b.size() # Shortest first
			return Combination.get_strength(a) < Combination.get_strength(b) # Lowest strength first
		)
		return all_straights[0]

	# If nothing else, return empty (shouldn't happen if hand is not empty)
	return []

## Attempt to build consecutive pairs starting from a given rank
## @param hand: The AI player's hand
## @param start_rank: Starting rank for the consecutive pairs
## @param num_pairs: Number of consecutive pairs needed (minimum 3)
## @return: Array of cards forming consecutive pairs, or empty if cannot build
static func try_build_consecutive_pairs(hand: Hand, start_rank: int, num_pairs: int) -> Array[Card]:
	var pairs: Array[Card] = []
	for i in range(num_pairs):
		var rank = start_rank + i
		var cards = hand.get_cards_by_rank(rank)
		if cards.size() < 2:
			return []  # Not enough cards for a pair
		pairs.append(cards[0])
		pairs.append(cards[1])

	return pairs

## Find all possible straights in the hand
static func _find_all_straights(hand: Hand) -> Array:
	var all_straights: Array = []
	# Iterate through possible lengths (from 4 up to hand size)
	for length in range(4, hand.get_card_count() + 1):
		# Iterate through possible starting ranks (3 to Ace)
		for start_rank in range(Card.Rank.THREE, Card.Rank.TWO): # Up to Ace, as 2s cannot be in straights
			var straight = try_build_straight(hand, start_rank, length)
			if not straight.is_empty():
				all_straights.append(straight)
	return all_straights

## Find all possible triples in the hand
static func _find_all_triples(hand: Hand) -> Array:
	var all_triples: Array = []
	for rank in range(Card.Rank.THREE, Card.Rank.TWO + 1): # All ranks
		var cards_of_rank = hand.get_cards_by_rank(rank)
		if cards_of_rank.size() >= 3:
			var triple_combo: Array[Card] = [cards_of_rank[0], cards_of_rank[1], cards_of_rank[2]]
			all_triples.append(triple_combo)
	return all_triples

## Find all possible pairs in the hand
static func _find_all_pairs(hand: Hand) -> Array:
	var all_pairs: Array = []
	for rank in range(Card.Rank.THREE, Card.Rank.TWO + 1): # All ranks
		var cards_of_rank = hand.get_cards_by_rank(rank)
		if cards_of_rank.size() >= 2:
			var pair_combo: Array[Card] = [cards_of_rank[0], cards_of_rank[1]]
			all_pairs.append(pair_combo)
	return all_pairs
