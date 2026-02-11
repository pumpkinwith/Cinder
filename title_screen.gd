extends Control

## Title screen with animated reveal sequence
## Background → Title (fire) → Start Button (fire) → Quit Label

# Timing constants
const BG_DELAY: float = 0.5
const BG_FADE_DURATION: float = 1.5
const TITLE_DELAY: float = 1.0
const TITLE_REVEAL_DURATION: float = 2.5
const BUTTON_DELAY: float = 0.5
const BUTTON_REVEAL_DURATION: float = 0.8
const QUIT_FADE_DURATION: float = 0.5
const BURNOUT_BUTTON_DURATION: float = 0.5
const BURNOUT_TITLE_DURATION: float = 0.7
const BURNOUT_BG_DURATION: float = 0.5

# Fire shader constants
const NOISE_SCALE: float = 1.5
const DISSOLVE_BORDER_SIZE: float = 0.3
const DISSOLVE_COLOR_STRENGTH: float = 1.5
const DISSOLVE_COLOR_FROM: Color = Color(1.0, 0.9, 0.4, 1.0)
const DISSOLVE_COLOR_TO: Color = Color(1.0, 0.4, 0.1, 1.0)

@onready var camera: Camera2D = $Camera2D if has_node("Camera2D") else null
@onready var background_sprite: AnimatedSprite2D = get_node_or_null("BG")
@onready var title_sprite: Node = get_node_or_null("Title")
@onready var start_button: Node = get_node_or_null("Start")
@onready var bgm: AudioStreamPlayer = get_node_or_null("Main BGM demo")

var fade_overlay: ColorRect  # Created programmatically

func _ready() -> void:
	# Setup camera
	if camera:
		camera.enabled = true
		camera.make_current()
	
	# Initialize background (already visible)
	if background_sprite:
		background_sprite.modulate.a = 1.0
		if background_sprite.sprite_frames:
			background_sprite.play()
	
	# Create fade overlay covering entire viewport (matching BG2 ColorRect size)
	fade_overlay = ColorRect.new()
	fade_overlay.color = Color.BLACK
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_overlay.z_index = 100
	
	# Match the BG2 ColorRect dimensions from the scene
	fade_overlay.position = Vector2(-5462.0, -6250.0)
	fade_overlay.size = Vector2(9111.0 - (-5462.0), 8323.0 - (-6250.0))
	
	add_child(fade_overlay)
	
	# Initialize title and button (start invisible)
	if title_sprite:
		title_sprite.modulate.a = 0.0
	if start_button:
		start_button.modulate.a = 0.0
	
	# Begin reveal sequence
	_reveal_sequence()

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

func _fire_reveal(node: Node, duration: float) -> void:
	"""Reveal a node using fire dissolve effect"""
	if not node:
		return
	
	# Make visible and apply shader
	node.modulate.a = 1.0
	var shader := _create_dissolve_shader()
	shader.set_shader_parameter("time", 1.0)  # Start hidden
	node.material = shader
	
	# Animate from hidden (1.0) to visible (0.0)
	var tween := create_tween()
	tween.tween_method(
		func(value: float) -> void:
			shader.set_shader_parameter("time", value),
		1.0, 0.0, duration
	)
	await tween.finished

func _reveal_sequence() -> void:
	"""Orchestrate the reveal: BG → Title → Button → Quit"""
	# Step 1: Wait then fade out black overlay
	await get_tree().create_timer(BG_DELAY).timeout
	if fade_overlay:
		var bg_tween := create_tween()
		bg_tween.tween_property(fade_overlay, "color", Color(0.0, 0.0, 0.0, 0.0), BG_FADE_DURATION)
		await bg_tween.finished
		fade_overlay.visible = false
	
	# Step 2: Fire reveal title
	await get_tree().create_timer(TITLE_DELAY).timeout
	if title_sprite:
		await _fire_reveal(title_sprite, TITLE_REVEAL_DURATION)
	
	# Step 3: Fire reveal start button
	await get_tree().create_timer(BUTTON_DELAY).timeout
	if start_button:
		await _fire_reveal(start_button, BUTTON_REVEAL_DURATION)
		start_button.material = null  # Remove shader after reveal
		
		# Enable interaction
		if "interaction_enabled" in start_button:
			start_button.interaction_enabled = true
	
	# Step 4: Play BGM after all reveals complete
	if bgm and bgm.has_method("play"):
		bgm.volume_db = -5.0  # Slightly lower than default
		bgm.play()
		print("[TitleScreen] BGM started playing at volume: ", bgm.volume_db)
	else:
		print("[TitleScreen] BGM not found or cannot play")

func _fire_burnout(node: Node, duration: float) -> void:
	"""Burn out a node using fire dissolve effect"""
	if not node:
		return
	
	var shader := _create_dissolve_shader()
	shader.set_shader_parameter("time", 0.0)  # Start visible
	node.material = shader
	
	# Animate from visible (0.0) to hidden (1.0)
	var tween := create_tween()
	tween.tween_method(
		func(value: float) -> void:
			shader.set_shader_parameter("time", value),
		0.0, 1.0, duration
	)
	await tween.finished

func _on_start_pressed() -> void:
	"""Reverse fire effect to burn out UI before scene change"""
	# Burn out button
	if start_button:
		await _fire_burnout(start_button, BURNOUT_BUTTON_DURATION)
		start_button.modulate.a = 0.0
	
	# Burn out title
	if title_sprite:
		await _fire_burnout(title_sprite, BURNOUT_TITLE_DURATION)
		title_sprite.modulate.a = 0.0
	
	# Fade to black
	if fade_overlay:
		fade_overlay.visible = true
		fade_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
		fade_overlay.z_index = 200
		var fade_tween := get_tree().create_tween()
		fade_tween.tween_property(fade_overlay, "color", Color.BLACK, BURNOUT_BG_DURATION)
		await fade_tween.finished
	
	# Change to Tutorial Land scene
	get_tree().change_scene_to_file("res://Tutorial Land.tscn")
