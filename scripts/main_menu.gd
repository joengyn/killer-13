extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_startbutton_pressed() -> void:
	print("Start Pressed")
	get_tree().change_scene_to_file("res://scenes/game_screen.tscn")

func _on_optionsbutton_pressed() -> void:
	print("Options Pressed")

func _on_exitbutton_pressed() -> void:
	print("Exit Pressed")
	get_tree().quit()
	
