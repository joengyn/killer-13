extends Control
## MainMenu - Entry point for the Killer 13 card game
##
## This is the first screen players see when launching the game. It provides
## navigation to different game modes and settings, and serves as the hub for
## the application.
##
## Menu structure:
## - Play button: Starts a new game (transitions to game_screen.tscn)
## - Settings button: Opens settings menu (not yet implemented)
## - Exit button: Quits the application
##
## Scene flow:
## MainMenu (this) → GameScreen (game_screen.tscn) → back to MainMenu (on game end)
##
## This is intentionally kept simple and minimal - it's just a navigation layer
## between the OS and the actual game.

# ============================================================================
# LIFECYCLE METHODS
# ============================================================================

func _ready() -> void:
	# Currently no initialization needed
	# Future: Could add menu animations, music, version display, etc.
	pass

func _process(_delta: float) -> void:
	# Currently no per-frame updates needed
	# Future: Could add animated background, particle effects, etc.
	pass

# ============================================================================
# BUTTON HANDLERS - Menu Navigation
# ============================================================================

func _on_play_button_pressed() -> void:
	## Handle Play button click - start a new game
	##
	## Transitions to the main game scene where dealing and gameplay occur.
	## This is the primary action for the menu - starting a game.
	get_tree().change_scene_to_file("res://scenes/main/game_screen.tscn")

func _on_settings_button_pressed() -> void:
	## Handle Settings button click - open settings menu
	##
	## TODO: Implement settings screen
	## Future settings could include:
	## - Sound/music volume
	## - Card back designs
	## - AI difficulty
	## - Animation speed
	## - Display options
	print("Settings button pressed")

func _on_exit_button_pressed() -> void:
	## Handle Exit button click - quit the application
	##
	## Cleanly exits the game, triggering Godot's shutdown sequence.
	get_tree().quit()
