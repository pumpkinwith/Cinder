extends Area2D

## Detection range for Ted enemy
## Sets player_in_detection_zone flag on parent when player enters/exits

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Debug: print detection range is ready
	var parent = get_parent()
	print("[DetectionRange] Ready on: ", parent.name if parent else "no parent")

func _on_body_entered(body: Node2D) -> void:
	print("[DetectionRange] Body entered: ", body.name, " Type: ", body.get_class(), " Groups: ", body.get_groups())
	# Only detect CharacterBody2D that is in player group (not TileMaps or other bodies)
	if body is CharacterBody2D and body.is_in_group("player"):
		var parent = get_parent()
		if parent and "player_in_detection_zone" in parent:
			parent.player_in_detection_zone = true
			print("[DetectionRange] Player detected! Set flag on: ", parent.name)

func _on_body_exited(body: Node2D) -> void:
	print("[DetectionRange] Body exited: ", body.name)
	# Only detect CharacterBody2D that is in player group
	if body is CharacterBody2D and body.is_in_group("player"):
		var parent = get_parent()
		if parent and "player_in_detection_zone" in parent:
			parent.player_in_detection_zone = false
			print("[DetectionRange] Player left detection zone")
