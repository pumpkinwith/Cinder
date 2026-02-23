extends AnimatedSprite2D

## Oil Gauge HUD — listens to player's oil_changed signal
## Plays one of 7 animations: Empty, 1, 2, 3, 4, 5, 6

var _player: Node = null

func _ready() -> void:
	call_deferred("_bind_player")

func _bind_player() -> void:
	if _player and is_instance_valid(_player):
		return

	_player = get_tree().get_first_node_in_group("player")
	if not _player:
		await get_tree().process_frame
		_player = get_tree().get_first_node_in_group("player")
	if not _player:
		return

	if _player.has_signal("oil_changed"):
		var callable := Callable(self, "_on_oil_changed")
		if not _player.is_connected("oil_changed", callable):
			_player.connect("oil_changed", callable)

	# Sync to current oil state
	var oil_val: Variant = _player.get("oil_percent")
	if oil_val != null and _player.has_method("get_oil_stage"):
		_set_stage(_player.get_oil_stage())

func _on_oil_changed(new_stage: int) -> void:
	_set_stage(new_stage)

func _set_stage(stage: int) -> void:
	var anim_name: String = "Empty" if stage == 0 else str(stage)
	if sprite_frames and sprite_frames.has_animation(anim_name):
		if animation != anim_name:
			play(anim_name)
