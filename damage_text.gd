extends Node2D

## Floating damage text that appears when entities take damage
## Animates upward with fade out effect

const LIFETIME: float = 1.0
const FADE_TIME: float = 0.5
const DECELERATION: float = 20.0

@onready var label: Label = $Label

var velocity: Vector2 = Vector2(0, -15)

func _ready() -> void:
	# Apply a smaller random spawn offset so numbers stay close to hit position
	# Use symmetric small ranges to keep the text near the impact point
	global_position += Vector2(randf_range(-4, 4), randf_range(-2, 2))

	# Randomize a subtle scale so text varies a bit
	scale = Vector2.ONE * randf_range(0.72, 0.95)

	# Slight random rotation to avoid perfectly-aligned stacks
	rotation = randf_range(-0.08, 0.08)

	# Start fading after initial display
	await get_tree().create_timer(LIFETIME - FADE_TIME).timeout

	# Fade out
	var tween: Tween = create_tween()
	tween.tween_property(label, "modulate:a", 0.0, FADE_TIME)
	tween.finished.connect(queue_free)

func _process(delta: float) -> void:
	# Float upward
	global_position += velocity * delta
	velocity.y += DECELERATION * delta  # Slight deceleration

func setup(damage: float, is_critical: bool = false) -> void:
	"""Configure damage text appearance"""
	# Show with one decimal place (e.g., 10.0)
	label.text = "%.1f" % damage

	if is_critical:
		# Red for critical hits, make slightly larger than normal but smaller than previous
		label.add_theme_color_override("font_color", Color(1.0, 0.0, 0.0))
		label.add_theme_font_size_override("font_size", 10)
		label.text = ("%.1f" % damage) + "!"

		# Make critical text float up faster and modestly bigger to emphasize
		velocity = Vector2(0, -36)
		scale = scale * 1.15
	else:
		# White for normal damage, use a slightly smaller base size
		label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
		label.add_theme_font_size_override("font_size", 8)
