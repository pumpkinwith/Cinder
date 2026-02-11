extends Node2D

## Tutorial Land scene with fade-in transition and automatic boundary placement

const FADE_IN_DURATION: float = 1.0
const PLAYER_REVEAL_DURATION: float = 2.0

# Fire shader constants (matching title screen)
const NOISE_SCALE: float = 1.5
const DISSOLVE_BORDER_SIZE: float = 0.3
const DISSOLVE_COLOR_STRENGTH: float = 1.5
const DISSOLVE_COLOR_FROM: Color = Color(1.0, 0.9, 0.4, 1.0)
const DISSOLVE_COLOR_TO: Color = Color(1.0, 0.4, 0.1, 1.0)

var fade_overlay: ColorRect
@onready var player: Node = get_node_or_null("Player")
@onready var ted: Node = get_node_or_null("Ted")
@onready var terrain0: TileMapLayer = $"Terrain 0"
@onready var terrain1: TileMapLayer = $"Terrain 1"
@onready var terrain2: TileMapLayer = $"Terrain 2"

func _ready() -> void:
	
	# Hide Ted (enemy) during reveal
	if ted:
		ted.visible = false
		# Lower Ted's detection range if he has that property
		if "detection_radius" in ted:
			ted.detection_radius = 0.0
	
	# Create black overlay that stays visible
	fade_overlay = ColorRect.new()
	fade_overlay.color = Color.BLACK
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_overlay.z_index = 100  # High enough to cover scene
	
	# Make it cover a large area (centered on world origin)
	fade_overlay.position = Vector2(-10000, -10000)
	fade_overlay.size = Vector2(20000, 20000)
	add_child(fade_overlay)
	
	# Wait a moment, then fire reveal the player
	await get_tree().create_timer(0.3).timeout
	if player:
		await _fire_reveal_player(player, PLAYER_REVEAL_DURATION)
	
	# After player reveal, fade out the black overlay
	await get_tree().create_timer(0.2).timeout
	var tween := get_tree().create_tween()
	tween.tween_property(fade_overlay, "color", Color(0.0, 0.0, 0.0, 0.0), FADE_IN_DURATION)
	await tween.finished
	fade_overlay.queue_free()
	
	# Show Ted and restore detection after overlay is gone
	if ted:
		ted.visible = true
		# Restore Ted's detection range
		if "detection_radius" in ted:
			ted.detection_radius = 150.0  # Default detection radius

func _create_dissolve_shader() -> ShaderMaterial:
	"""Create configured fire dissolve shader"""
	var shader := ShaderMaterial.new()
	shader.shader = load("res://Shaders/pixel-art-shaders/shaders/dissolve.gdshader")
	shader.set_shader_parameter("noise_texture", load("res://Shaders/pixel-art-shaders/burn-noise.tres"))
	shader.set_shader_parameter("noise_scale", NOISE_SCALE)
	shader.set_shader_parameter("palette_shift", false)
	shader.set_shader_parameter("use_dissolve_color", true)
	shader.set_shader_parameter("dissolve_color_from", DISSOLVE_COLOR_FROM)
	shader.set_shader_parameter("dissolve_color_to", DISSOLVE_COLOR_TO)
	shader.set_shader_parameter("dissolve_color_strength", DISSOLVE_COLOR_STRENGTH)
	shader.set_shader_parameter("dissolve_border_size", DISSOLVE_BORDER_SIZE)
	shader.set_shader_parameter("pixelization", 0)
	return shader

func _fire_reveal_player(node: Node, duration: float) -> void:
	"""Reveal player using fire dissolve effect"""
	if not node:
		return
	
	# Apply shader
	var shader := _create_dissolve_shader()
	shader.set_shader_parameter("time", 1.0)  # Start hidden
	node.material = shader
	
	# Animate from hidden (1.0) to visible (0.0)
	var tween := get_tree().create_tween()
	tween.tween_method(
		func(value: float) -> void:
			shader.set_shader_parameter("time", value),
		1.0, 0.0, duration
	)
	await tween.finished

func _place_boundaries() -> void:
	"""Place invisible collision tiles around platform edges (like GitHub example)"""
