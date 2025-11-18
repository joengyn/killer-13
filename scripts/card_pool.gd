@tool
extends Node
## CardPool - Object pooling for card instances to reduce GC pressure
##
## Maintains a pool of reusable Card scenes to avoid frequent instantiation/destruction.
## When a card is no longer needed, return it to the pool instead of queue_free().
## The pool recycles cards for future use, significantly reducing garbage collection overhead.

## Maximum number of cards to keep in the pool
@export var max_pool_size: int = 60

var _available_cards: Array[Node] = []
var _card_scene = preload("res://scenes/card.tscn")


## Get a card from the pool (or instantiate new if pool is empty)
## @return: A card node ready to use
func get_card() -> Node:
	if _available_cards.is_empty():
		# Pool is empty, create a new card
		return _card_scene.instantiate()

	# Return a card from the pool
	return _available_cards.pop_back()


## Return a card to the pool for reuse
## Resets the card's state before returning to pool
## @param card: The card node to return to the pool
func return_card(card: Node) -> void:
	# Remove from current parent if it has one
	if card.get_parent():
		card.get_parent().remove_child(card)

	# Only keep cards in pool if we haven't reached max capacity
	if _available_cards.size() < max_pool_size:
		# Reset card state
		card.position = Vector2.ZERO
		card.rotation = 0.0
		card.scale = Vector2.ONE
		card.z_index = 0

		# Reset visibility
		if card.has_method("set_show_back"):
			card.set_show_back(false)
		if card.has_method("set_shadow_visible"):
			card.set_shadow_visible(false)

		# Return to pool
		_available_cards.append(card)
	else:
		# Pool is full, free the card
		card.queue_free()


## Get current number of available cards in the pool
## @return: Number of cards ready to be used
func get_available_count() -> int:
	return _available_cards.size()


## Pre-populate the pool with a number of card instances
## Useful to avoid allocation spikes during gameplay
## @param count: Number of cards to pre-create
func prewarm(count: int) -> void:
	for i in range(count):
		if _available_cards.size() < max_pool_size:
			_available_cards.append(_card_scene.instantiate())


## Clear the pool and free all cards
func clear() -> void:
	for card in _available_cards:
		if is_instance_valid(card):
			card.queue_free()
	_available_cards.clear()


## Clean up when node is freed
func _exit_tree() -> void:
	clear()
