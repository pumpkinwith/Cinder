extends TextureButton

## Resume / Retry button on Game Over screen
## Restarts the game when clicked

const HOVER_STRETCH: Vector2 = Vector2(1.08, 1.08)
const NORMAL_SCALE: Vector2 = Vector2.ONE
const SCALE_SPEED: float = 10.0

var interaction_enabled: bool = false
var _target_scale: Vector2 = NORMAL_SCALE

func _ready() -> void:
	# Start hidden — game_over.gd reveals us
	modulate.a = 0.0
	pivot_offset = size / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Connect signals
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	pressed.connect(_on_pressed)

func _process(delta: float) -> void:
	# Smooth scale toward target
	scale = scale.lerp(_target_scale, clampf(SCALE_SPEED * delta, 0.0, 1.0))

func _on_mouse_entered() -> void:
	if interaction_enabled and modulate.a > 0.5:
		_target_scale = HOVER_STRETCH

func _on_mouse_exited() -> void:
	_target_scale = NORMAL_SCALE

func _on_pressed() -> void:
	if not interaction_enabled:
		return
	interaction_enabled = false
	get_tree().change_scene_to_file("res://Tutorial Land.tscn")
