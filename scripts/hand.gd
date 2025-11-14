class_name Hand
## Represents a player's hand
##
## Maintains an ordered collection of cards, automatically sorted by rank
## and suit. Provides query and manipulation methods for card management.

var cards: Array[Card] = []

## Initialize hand with cards and automatically sort
func _init(initial_cards: Array[Card]) -> void:
	for card in initial_cards:
		cards.append(card as Card)
	sort_hand()

## Sort hand by rank (ascending), then by suit for tiebreaking
func sort_hand() -> void:
	cards.sort_custom(func(a: Card, b: Card) -> bool:
		if a.rank != b.rank:
			return a.rank < b.rank
		return a.suit < b.suit
	)

## Get number of cards in hand
func get_card_count() -> int:
	return cards.size()

## Check if hand is empty
func is_empty() -> bool:
	return cards.is_empty()

## Find and return the 3 of Spades card, or null if not in hand
func find_three_of_spades() -> Card:
	for card in cards:
		if card.is_three_of_spades():
			return card
	return null

## Check if hand contains a specific card
func has_card(card: Card) -> bool:
	return card in cards

## Check if hand contains all cards in the given array
func has_cards(check_cards: Array) -> bool:
	for card in check_cards:
		if not has_card(card):
			return false
	return true

## Remove cards from hand (after playing them) and re-sort
## Returns true if successful, false if cards don't exist
func remove_cards(played_cards: Array) -> bool:
	if not has_cards(played_cards):
		return false

	for card in played_cards:
		cards.erase(card)

	sort_hand()
	return true

## Get hand as a formatted string for console output
## Example: "3♠ 4♠ 5♠ 6♣ 7♦ 8♥ 9♠ 10♣ J♦ Q♥ K♠ A♣ 2♦"
func _to_string() -> String:
	var hand_str = ""
	for i in range(cards.size()):
		hand_str += cards[i]._to_string()
		if i < cards.size() - 1:
			hand_str += " "
	return hand_str

## Get all cards of a specific rank
func get_cards_by_rank(rank: Card.Rank) -> Array[Card]:
	var result: Array[Card] = []
	for card in cards:
		if card.rank == rank:
			result.append(card)
	return result

## Get highest card in hand
func get_highest_card() -> Card:
	if cards.is_empty():
		return null
	var highest = cards[0]
	for card in cards:
		if card.compare_to(highest) > 0:
			highest = card
	return highest

## Get lowest card in hand (hand is always sorted, so returns first card)
func get_lowest_card() -> Card:
	if cards.is_empty():
		return null
	return cards[0]
