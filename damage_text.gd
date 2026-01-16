extends Node2D

@onready var label: Label = $Label

var velocity: Vector2 = Vector2(0, -15)
var lifetime: float = 1.0
var fade_time: float = 0.5

func _ready() -> void:
	# Start fading after initial display
	await get_tree().create_timer(lifetime - fade_time).timeout
	
	# Fade out
	var tween = create_tween()
	tween.tween_property(label, "modulate:a", 0.0, fade_time)
	tween.finished.connect(queue_free)

func _process(delta: float) -> void:
	# Float upward
	global_position += velocity * delta
	velocity.y += 20 * delta  # Slight deceleration

func setup(damage: float, is_critical: bool = false) -> void:
	"""Configure damage text appearance"""
	label.text = "%.1f" % damage  # Show one decimal place (e.g., 10.0)
	
	if is_critical:
		# Red for critical hits, slightly larger
		label.add_theme_color_override("font_color", Color(1.0, 0.0, 0.0))
		label.add_theme_font_size_override("font_size", 12)
		label.text = ("%.1f" % damage) + "!"
	else:
		# White for normal damage
		label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		label.add_theme_font_size_override("font_size", 10)
