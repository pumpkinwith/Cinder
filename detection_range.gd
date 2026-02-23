extends Area2D

## Detection range for Ted enemy
## Sets player_in_detection_zone flag on parent when player enters/exits
var _is_shutting_down: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node2D) -> void:
	if _is_shutting_down or not is_inside_tree():
		return
	# Only detect CharacterBody2D that is in player group (not TileMaps or other bodies)
	if body is CharacterBody2D and body.is_in_group("player"):
		var parent = get_parent()
		if parent and parent.is_inside_tree() and "player_in_detection_zone" in parent:
			parent.player_in_detection_zone = true

func _on_body_exited(body: Node2D) -> void:
	if _is_shutting_down or not is_inside_tree():
		return
	# Only detect CharacterBody2D that is in player group
	if body is CharacterBody2D and body.is_in_group("player"):
		var parent = get_parent()
		if parent and parent.is_inside_tree() and "player_in_detection_zone" in parent:
			parent.player_in_detection_zone = false

func _exit_tree() -> void:
	_is_shutting_down = true
