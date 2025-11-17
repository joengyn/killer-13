class_name Hand
## Represents a player's hand of cards in Tiến Lên
##
## Maintains an automatically-sorted collection of Card objects. Cards are always
## sorted by rank (3 lowest, 2 highest), with suit as tiebreaker (Spades → Hearts).
## Provides methods for querying, adding, removing, and analyzing cards.

## Array of Card objects in this hand (always kept sorted)
var cards: Array[Card] = []
var _needs_sort: bool = false

## Initialize a new hand with the given cards and sort them
## @param initial_cards: Array of Card objects to start with
func _init(initial_cards: Array[Card]) -> void:
	for card in initial_cards:
		cards.append(card as Card)
	_needs_sort = true

## Sort the hand by rank (ascending), then suit (Spades → Hearts)
## Called automatically after adding or removing cards
func sort_hand() -> void:
	cards.sort_custom(Card.compare_cards_lt)

## Get the number of cards currently in hand
## @return: Integer count of cards
func get_card_count() -> int:
	return cards.size()

## Check if hand is empty (no cards left)
## @return: True if hand has zero cards
func is_empty() -> bool:
	return cards.is_empty()

## Find and return the 3♠ card if present (required for first turn)
## @return: The Card object for 3♠, or null if not in hand
func find_three_of_spades() -> Card:
	for card in cards:
		if card.is_three_of_spades():
			return card
	return null

## Check if this hand contains a specific card
## @param card: The Card object to look for
## @return: True if the card is in this hand
func has_card(card: Card) -> bool:
	return card in cards

## Check if this hand contains all of the given cards
## @param check_cards: Array of Card objects to verify
## @return: True if all cards are present in this hand
func has_cards(check_cards: Array) -> bool:
	for card in check_cards:
		if not has_card(card):
			return false
	return true

## Remove cards from hand (called when cards are played) and re-sort
## @param played_cards: Array of Card objects to remove
## @return: True if all cards were found and removed, false otherwise
func remove_cards(played_cards: Array) -> bool:
	if not has_cards(played_cards):
		return false

	for card in played_cards:
		cards.erase(card)

	_needs_sort = true
	return true

## Get the sorted cards, sorting only if necessary
## @return: Array of Card objects, guaranteed to be sorted
func get_sorted_cards() -> Array[Card]:
	if _needs_sort:
		sort_hand()
		_needs_sort = false
	return cards

## Convert hand to a space-separated string for display/debugging
## Example output: "3♠ 4♠ 5♠ 6♣ 7♦ 8♥ 9♠ 10♣ J♦ Q♥ K♠ A♣ 2♦"
## @return: String representation of all cards in hand
func _to_string() -> String:
	var hand_str = ""
	var sorted_cards = get_sorted_cards()
	for i in range(sorted_cards.size()):
		hand_str += sorted_cards[i]._to_string()
		if i < sorted_cards.size() - 1:
			hand_str += " "
	return hand_str

## Get all cards of a specific rank (e.g., all 5s, all Kings)
## @param rank: The Card.Rank enum value to search for
## @return: Array of Card objects matching the rank
func get_cards_by_rank(rank: Card.Rank) -> Array[Card]:
	var result: Array[Card] = []
	for card in cards:
		if card.rank == rank:
			result.append(card)
	return result

## Get the highest ranking card in hand (by rank, then suit)
## @return: The Card object with highest rank and suit, or null if hand is empty
func get_highest_card() -> Card:
	var sorted_cards = get_sorted_cards()
	if sorted_cards.is_empty():
		return null
	return sorted_cards[sorted_cards.size() - 1]

## Get the lowest ranking card in hand (hand is always sorted)
## @return: The Card object with lowest rank and suit (first card), or null if hand is empty
func get_lowest_card() -> Card:
	var sorted_cards = get_sorted_cards()
	if sorted_cards.is_empty():
		return null
	return sorted_cards[0]

## Returns a new array of cards representing the hand after removing specified cards,
## without modifying the original hand.
## @param cards_to_remove: Array of Card objects to conceptually remove
## @return: New Array of Card objects
func get_cards_after_removing(cards_to_remove: Array[Card]) -> Array[Card]:
	var temp_cards = cards.duplicate(true) # Deep duplicate to avoid modifying original Card objects
	for card_to_remove in cards_to_remove:
		for i in range(temp_cards.size()):
			if temp_cards[i].is_equal_to(card_to_remove):
				temp_cards.remove_at(i)
				break
	return temp_cards
