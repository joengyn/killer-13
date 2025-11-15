extends PanelContainer

@onready var label: Label = $Label

var _current_round_cards: Array = []

func _ready() -> void:
	# Connect to GameManager signals
	if GameManager:
		GameManager.round_started.connect(_on_round_started)
	
	visible = false
	update_label()

func _on_round_started() -> void:
	_current_round_cards.clear()
	visible = false
	update_label()

func _on_card_play_visual_complete(_player_index: int, cards: Array) -> void:
	_current_round_cards.append(cards)
	visible = true
	update_label()

func update_label() -> void:
	if _current_round_cards.is_empty():
		label.text = ""
		return

	var round_text = ""
	for i in range(_current_round_cards.size()):
		var combo = _current_round_cards[i]
		var combo_text = ""
		for card in combo:
			combo_text += card._to_string() + " "
		
		round_text += combo_text.strip_edges()
		if i < _current_round_cards.size() - 1:
			round_text += ", "
			
	label.text = round_text

	# Wait for the container to resize before calculating pivot
	await get_tree().process_frame
	pivot_offset = size / 2.0
