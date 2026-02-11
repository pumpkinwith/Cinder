extends Node2D

## Game Over scene controller

func _ready() -> void:
	# Any initialization for game over screen
	pass

func _input(event: InputEvent) -> void:
	# Handle input to restart or return to menu
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("Attack"):
		# Restart the game
		get_tree().change_scene_to_file("res://Tutorial Land.tscn")
	elif event.is_action_pressed("ui_cancel"):
		# Return to title screen
		get_tree().change_scene_to_file("res://main_menu.tscn")
