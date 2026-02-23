extends Area2D

func _ready() -> void:
	# This hitbox is intentionally disabled for Ted in the main script.
	# Keeping a minimal stub so scenes referencing the script remain valid.
	monitoring = false

func start_attack(_direction: String) -> void:
	pass

func stop_attack() -> void:
	pass
