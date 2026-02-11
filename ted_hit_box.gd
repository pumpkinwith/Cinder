extends Area2D

@export var debug_print: bool = false

func _ready() -> void:
	# This hitbox is intentionally disabled for Ted in the main script.
	# Keeping a minimal stub so scenes referencing the script remain valid.
	monitoring = false

func start_attack(_direction: String) -> void:
	if debug_print:
		print("[ted_hit_box] start_attack called but Ted attack logic removed.")

func stop_attack() -> void:
	if debug_print:
		print("[ted_hit_box] stop_attack called but Ted attack logic removed.")
