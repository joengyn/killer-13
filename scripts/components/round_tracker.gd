extends PanelContainer

@onready var plays_container: HBoxContainer = $PlaysContainer

var _current_round_cards: Array = []

func _ready() -> void:
	# Connect to GameManager signals
	if GameManager:
		GameManager.round_started.connect(_on_round_started)
	
	visible = false
	update_plays_display()

func _on_round_started() -> void:
	_current_round_cards.clear()
	visible = false
	update_plays_display()

func _on_card_play_visual_complete(_player_index: int, cards: Array) -> void:
	_current_round_cards.append(cards)
	# visible = true # Hidden by user request
	update_plays_display()

func update_plays_display() -> void:
	# Clear existing play labels
	for child in plays_container.get_children():
		child.queue_free()

	if _current_round_cards.is_empty():
		return

	for combo in _current_round_cards:
		var play_panel = PanelContainer.new()
		play_panel.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		plays_container.add_child(play_panel)

		var play_label = Label.new()
		play_label.set_theme(plays_container.get_theme()) # Inherit theme
		play_label.set_theme_type_variation("RoundTrackerPlayLabel") # Custom variation for styling
		play_label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
		play_label.set_v_size_flags(Control.SIZE_EXPAND_FILL)
		play_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_CENTER)
		play_label.set_vertical_alignment(VERTICAL_ALIGNMENT_CENTER)
		play_panel.add_child(play_label)

		var combo_text = ""
		for card in combo:
			combo_text += card._to_string() + ", "
		
		# Remove trailing comma and space, then wrap in brackets
		play_label.text = "[" + combo_text.strip_edges().trim_suffix(",") + "]"

	# Wait for the container to resize before calculating pivot
	await get_tree().process_frame
	pivot_offset = size / 2.0
