extends PanelContainer
## RoundTracker - Visual display of card plays within the current round
##
## This UI component shows a history of all plays made in the current round,
## providing players with a visual reference of what has been played so far.
##
## What is a "round" in Killer 13?
## A round is a sequence of plays that starts when the first player places cards
## and ends when all players pass consecutively. At the start of a new round,
## the play history resets and this tracker shows the fresh sequence of plays.
##
## Purpose:
## - Shows each combination played in order (e.g., "Pair of 5s", "Three 8s")
## - Helps players remember what was played earlier in the round
## - Resets at the start of each new round
## - Currently hidden by default (visible = false per user request)
##
## Integration: Connects to GameManager.round_started signal and receives
## play updates from GameScreen via _on_card_play_visual_complete().

# ============================================================================
# REFERENCES - UI Components
# ============================================================================

## Container that holds individual play labels
@onready var plays_container: HBoxContainer = $PlaysContainer

# ============================================================================
# STATE VARIABLES
# ============================================================================

## Array tracking all card combinations played in the current round
## Each element is an array of Cards representing one play
var _current_round_cards: Array = []

# ============================================================================
# LIFECYCLE METHODS
# ============================================================================

func _ready() -> void:
	# Connect to GameManager signals to detect round resets
	if GameManager:
		GameManager.round_started.connect(_on_round_started)

	# Hidden by default per user request
	visible = false
	update_plays_display()

# ============================================================================
# UPDATE METHODS - Display Management
# ============================================================================

func update_plays_display() -> void:
	## Rebuild the visual display of all plays in the current round
	##
	## Clears all existing play labels and creates new ones for each play.
	## Each play is shown as a bracketed list of cards, e.g., "[3♠, 3♥]"

	# Clear existing play labels
	for child in plays_container.get_children():
		child.queue_free()

	if _current_round_cards.is_empty():
		return

	# Create a panel and label for each play
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

		# Build text representation of the card combination
		var combo_text = ""
		for card in combo:
			combo_text += card._to_string() + ", "

		# Remove trailing comma and space, then wrap in brackets
		play_label.text = "[" + combo_text.strip_edges().trim_suffix(",") + "]"

	# Wait for the container to resize before calculating pivot
	# This ensures proper centering/anchoring of the UI element
	await get_tree().process_frame
	pivot_offset = size / 2.0

# ============================================================================
# SIGNAL HANDLERS - Round and Play Events
# ============================================================================

func _on_round_started() -> void:
	## Handle when a new round starts - reset the play history
	##
	## Called by GameManager.round_started signal. Clears all tracked plays
	## and hides the tracker (since there's nothing to show yet).
	_current_round_cards.clear()
	visible = false
	update_plays_display()

func _on_card_play_visual_complete(_player_index: int, cards: Array) -> void:
	## Handle when a card play animation completes - add play to history
	##
	## This is called by GameScreen after the visual animation of cards being
	## played finishes. The play is added to the round history and display updated.
	##
	## @param _player_index: Index of player who made the play (unused currently)
	## @param cards: Array of Cards that were played
	_current_round_cards.append(cards)
	# visible = true # Currently commented out - hidden by user request
	update_plays_display()
