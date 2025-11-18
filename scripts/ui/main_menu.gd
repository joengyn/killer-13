extends Control

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func _on_play_button_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game_screen.tscn")


func _on_settings_button_pressed() -> void:
	print("Settings button pressed")


func _on_exit_button_pressed() -> void:
	get_tree().quit()
