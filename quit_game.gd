extends Label

## Quit Game label on Game Over screen
## Navigates to main menu when clicked (does NOT quit the application)

const HOVER_COLOR: Color = Color(1.0, 0.588, 0.478, 1.0)  # ff967a peachy/salmon
const NORMAL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const VISIBILITY_THRESHOLD: float = 0.5

@export var hit_padding: Vector2 = Vector2(6, 4)
var is_hovered: bool = false
var interaction_enabled: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 2
	# Start invisible — game_over.gd reveals us
	modulate.a = 0.0

func _process(_delta: float) -> void:
	if not interaction_enabled or modulate.a < VISIBILITY_THRESHOLD:
		return

	var mouse_pos: Vector2 = get_local_mouse_position()
	var expanded_size: Vector2 = size + hit_padding * 2.0
	var label_rect := Rect2(-hit_padding, expanded_size)
	var was_hovered: bool = is_hovered
	is_hovered = label_rect.has_point(mouse_pos)

	var current_alpha: float = modulate.a
	if is_hovered and not was_hovered:
		modulate = Color(HOVER_COLOR.r, HOVER_COLOR.g, HOVER_COLOR.b, current_alpha)
	elif not is_hovered and was_hovered:
		modulate = Color(NORMAL_COLOR.r, NORMAL_COLOR.g, NORMAL_COLOR.b, current_alpha)

func _input(event: InputEvent) -> void:
	if not interaction_enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_hovered:
			interaction_enabled = false
			get_tree().change_scene_to_file("res://main_menu.tscn")
