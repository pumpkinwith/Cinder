
extends Label

## Quit button label with hover behavior
## Uses Control-based positioning for click detection

const HOVER_COLOR: Color = Color(1.0, 0.588, 0.478, 1.0)  # ff967a peachy/salmon
const NORMAL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const VISIBILITY_THRESHOLD: float = 0.5

@export var fade_in_delay: float = 7.5  # Wait for Phases 1-3 to complete
@export var fade_in_duration: float = 0.5
@export var hit_padding: Vector2 = Vector2(6, 4)
var is_hovered: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 2
	# Start invisible - fade in after delay
	modulate.a = 0.0
	_fade_in()

func _fade_in() -> void:
	"""Fade in after title screen animations complete"""
	await get_tree().create_timer(fade_in_delay).timeout
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, fade_in_duration)

func _process(_delta: float) -> void:
	var mouse_pos: Vector2 = get_local_mouse_position()
	
	# Create expanded rect for hit detection
	var expanded_size: Vector2 = size + hit_padding * 2.0
	var label_rect := Rect2(-hit_padding, expanded_size)
	var was_hovered: bool = is_hovered
	var visible_enough: bool = modulate.a > VISIBILITY_THRESHOLD
	is_hovered = visible_enough and label_rect.has_point(mouse_pos)
	
	# Store current alpha
	var current_alpha: float = modulate.a
	
	if visible_enough:
		if is_hovered and not was_hovered:
			modulate = Color(HOVER_COLOR.r, HOVER_COLOR.g, HOVER_COLOR.b, current_alpha)
		elif not is_hovered and was_hovered:
			modulate = Color(NORMAL_COLOR.r, NORMAL_COLOR.g, NORMAL_COLOR.b, current_alpha)
	else:
		# If not yet visible, ensure base color (no hover)
		if was_hovered:
			modulate = Color(NORMAL_COLOR.r, NORMAL_COLOR.g, NORMAL_COLOR.b, current_alpha)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_hovered:
			get_tree().quit()
