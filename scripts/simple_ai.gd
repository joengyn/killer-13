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
		# Play lowest card to start
		var lowest = hand.get_lowest_card()
		return [lowest] if lowest else []

	# Try to beat the table combo
	var table_combo = game_state.get_table_combo()
	var combo_type = Combination.detect_type(table_combo)

	var play = find_lowest_beating_combo(hand, table_combo, combo_type)
	if play and not play.is_empty():
		return play

	# If we couldn't beat it normally, check if table has a 2 and try bombs
	if combo_type == Combination.Type.SINGLE or combo_type == Combination.Type.PAIR:
		var first_card = table_combo[0] as Card
		if first_card.is_two():
			var bomb = find_lowest_beating_bomb(hand, table_combo)
			if bomb and not bomb.is_empty():
				return bomb

	# Can't beat it, pass
	return []

## ============================================================================
## COMBO BEATING LOGIC
## ============================================================================

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
static func find_lowest_beating_single(hand: Hand, table_card: Card) -> Array:
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
static func find_lowest_beating_pair(hand: Hand, table_combo: Array) -> Array:
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
static func find_lowest_beating_triple(hand: Hand, table_combo: Array) -> Array:
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
static func find_lowest_beating_straight(hand: Hand, table_combo: Array) -> Array:
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
static func try_build_straight(hand: Hand, start_rank: int, length: int) -> Array:
	if start_rank + length > 13:
		return []  # Can't build straight that long from this rank

	var straight: Array = []
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
static func find_lowest_beating_bomb(hand: Hand, table_combo: Array) -> Array:
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

## Attempt to build consecutive pairs starting from a given rank
## @param hand: The AI player's hand
## @param start_rank: Starting rank for the consecutive pairs
## @param num_pairs: Number of consecutive pairs needed (minimum 3)
## @return: Array of cards forming consecutive pairs, or empty if cannot build
static func try_build_consecutive_pairs(hand: Hand, start_rank: int, num_pairs: int) -> Array:
	var pairs: Array = []
	for i in range(num_pairs):
		var rank = start_rank + i
		var cards = hand.get_cards_by_rank(rank)
		if cards.size() < 2:
			return []  # Not enough cards for a pair
		pairs.append(cards[0])
		pairs.append(cards[1])

	return pairs
