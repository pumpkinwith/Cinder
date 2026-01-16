extends Node2D

@onready var camera: Camera2D = $Camera2D if has_node("Camera2D") else null
@onready var background_sprite: AnimatedSprite2D = get_node_or_null("BG")
@onready var title_sprite: Node = get_node_or_null("Title")
@onready var start_button: Node = get_node_or_null("Start")
@onready var quit_label: Label = get_node_or_null("QuitLabel")

const BG_FADE_DURATION = 1.5
const TITLE_FADE_DURATION = 2.5
const BUTTON_FADE_DURATION = 1.5
const BG_DELAY = 0.5
const TITLE_DELAY = 1.0
const BUTTON_DELAY = 0.5

var interaction_enabled: bool = false

func _ready() -> void:
	# Create black background layer that fills everything
	var black_bg = ColorRect.new()
	black_bg.name = "BlackBackground"
	black_bg.color = Color.BLACK
	black_bg.z_index = -1000
	black_bg.position = Vector2(-50000, -50000)
	black_bg.size = Vector2(100000, 100000)
	add_child(black_bg)
	
	# Setup camera
	if camera:
		camera.enabled = true
		camera.position = Vector2.ZERO
		camera.zoom = Vector2.ONE
	
	# Play background animation if exists
	if background_sprite:
		background_sprite.modulate.a = 0  # Start invisible
		if background_sprite.sprite_frames:
			background_sprite.play()
	
	# Hide title and button initially
	if title_sprite:
		title_sprite.modulate.a = 0  # Start invisible
	if start_button:
		start_button.modulate.a = 0
	
	# Hide quit label initially
	if quit_label:
		quit_label.modulate.a = 0.0
	
	# Create fade overlay
	var fade_overlay = ColorRect.new()
	fade_overlay.name = "FadeOverlay"
	fade_overlay.color = Color.BLACK
	fade_overlay.z_index = 1000
	fade_overlay.position = Vector2(-50000, -50000)
	fade_overlay.size = Vector2(100000, 100000)
	add_child(fade_overlay)
	
	# Start reveal sequence
	_start_reveal_sequence(fade_overlay)

func _start_reveal_sequence(fade_overlay: ColorRect) -> void:
	# Wait initial delay
	await get_tree().create_timer(BG_DELAY).timeout
	
	# Remove black overlay
	fade_overlay.queue_free()
	
	# Fade in background
	if background_sprite:
		var tween = create_tween()
		tween.tween_property(background_sprite, "modulate:a", 1.0, BG_FADE_DURATION)
		await tween.finished
	
	# Wait before showing title
	await get_tree().create_timer(TITLE_DELAY).timeout
	
	# Apply fire reveal shader to title
	if title_sprite:
		# Make visible first
		title_sprite.modulate.a = 1.0
		
		var shader_material = ShaderMaterial.new()
		shader_material.shader = load("res://Shaders/pixel-art-shaders/shaders/dissolve.gdshader")
		shader_material.set_shader_parameter("noise_texture", load("res://Shaders/pixel-art-shaders/burn-noise.tres"))
		shader_material.set_shader_parameter("noise_scale", 1.5)
		shader_material.set_shader_parameter("palette_shift", false)
		shader_material.set_shader_parameter("use_dissolve_color", true)
		shader_material.set_shader_parameter("dissolve_color_from", Color(1.0, 0.9, 0.4, 1.0))  # Bright yellow
		shader_material.set_shader_parameter("dissolve_color_to", Color(1.0, 0.4, 0.1, 1.0))  # Orange
		shader_material.set_shader_parameter("dissolve_color_strength", 1.5)
		shader_material.set_shader_parameter("dissolve_border_size", 0.3)
		shader_material.set_shader_parameter("pixelization", 0)
		shader_material.set_shader_parameter("time", 1.0)  # Start hidden
		
		title_sprite.material = shader_material
		
		# Animate fire reveal (reverse from 1.0 to 0.0)
		var tween = create_tween()
		tween.tween_method(func(value): 
			shader_material.set_shader_parameter("time", value)
		, 1.0, 0.0, TITLE_FADE_DURATION)
		await tween.finished
	
	# Wait before showing button
	await get_tree().create_timer(BUTTON_DELAY).timeout
	
	# Finally reveal start button with dissolve effect (faster)
	if start_button:
		var button_shader = ShaderMaterial.new()
		button_shader.shader = load("res://Shaders/pixel-art-shaders/shaders/dissolve.gdshader")
		button_shader.set_shader_parameter("noise_texture", load("res://Shaders/pixel-art-shaders/burn-noise.tres"))
		button_shader.set_shader_parameter("noise_scale", 1.5)
		button_shader.set_shader_parameter("palette_shift", false)
		button_shader.set_shader_parameter("use_dissolve_color", true)
		button_shader.set_shader_parameter("dissolve_color_from", Color(1.0, 0.9, 0.4, 1.0))
		button_shader.set_shader_parameter("dissolve_color_to", Color(1.0, 0.4, 0.1, 1.0))
		button_shader.set_shader_parameter("dissolve_color_strength", 1.5)
		button_shader.set_shader_parameter("dissolve_border_size", 0.3)
		button_shader.set_shader_parameter("pixelization", 0)
		button_shader.set_shader_parameter("time", 1.0)  # Start hidden
		
		start_button.material = button_shader
		start_button.modulate.a = 1.0
		
		# Animate quickly (0.8 seconds)
		var tween = create_tween()
		tween.tween_method(func(value): 
			button_shader.set_shader_parameter("time", value)
		, 1.0, 0.0, 0.8)
		await tween.finished
		
		# Remove shader after reveal
		start_button.material = null
	
	# Show quit label with fade
	if quit_label:
		var quit_tween = create_tween()
		quit_tween.tween_property(quit_label, "modulate:a", 1.0, 0.5)
		await quit_tween.finished
	
	# Enable interactions after all animations complete
	interaction_enabled = true
	
	# Enable start button interaction
	if start_button:
		start_button.interaction_enabled = true

func _process(_delta: float) -> void:
	# Keep background animation playing
	if background_sprite and not background_sprite.is_playing():
		background_sprite.play()
	
	# Handle quit label hover and click (area = label size only)
	if interaction_enabled and quit_label and quit_label.modulate.a > 0.5:
		var label_rect = quit_label.get_rect()
		var mouse_pos = quit_label.get_local_mouse_position()
		if label_rect.has_point(mouse_pos):
			quit_label.modulate = Color(1.0, 0.7, 0.3, 1.0)  # Orange hover
		else:
			quit_label.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _input(event: InputEvent) -> void:
	if not interaction_enabled:
		return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if quit_label and quit_label.modulate.a > 0.5:
			var label_rect = quit_label.get_rect()
			var mouse_pos = quit_label.get_local_mouse_position()
			if label_rect.has_point(mouse_pos):
				get_tree().quit()

func _on_start_pressed():
	await _start_burnout_transition()
	get_tree().change_scene_to_file("res://Tutorial Land.tscn")

func _start_burnout_transition() -> void:
	# Burn out start button first
	if start_button:
		var button_shader = ShaderMaterial.new()
		button_shader.shader = load("res://Shaders/pixel-art-shaders/shaders/dissolve.gdshader")
		button_shader.set_shader_parameter("noise_texture", load("res://Shaders/pixel-art-shaders/burn-noise.tres"))
		button_shader.set_shader_parameter("noise_scale", 1.5)
		button_shader.set_shader_parameter("palette_shift", false)
		button_shader.set_shader_parameter("use_dissolve_color", true)
		button_shader.set_shader_parameter("dissolve_color_from", Color(1.0, 0.9, 0.4, 1.0))
		button_shader.set_shader_parameter("dissolve_color_to", Color(1.0, 0.4, 0.1, 1.0))
		button_shader.set_shader_parameter("dissolve_color_strength", 1.5)
		button_shader.set_shader_parameter("dissolve_border_size", 0.3)
		button_shader.set_shader_parameter("pixelization", 0)
		button_shader.set_shader_parameter("time", 0.0)
		start_button.material = button_shader
		var tween = create_tween()
		tween.tween_method(func(value):
			button_shader.set_shader_parameter("time", value)
		, 0.0, 1.0, 0.5)
		await tween.finished
		start_button.modulate.a = 0.0
	
	# Burn out quit label next
	if quit_label:
		var quit_tween = create_tween()
		quit_tween.tween_property(quit_label, "modulate:a", 0.0, 0.4)
		await quit_tween.finished
	
	# Burn out title last
	if title_sprite:
		var shader_material = ShaderMaterial.new()
		shader_material.shader = load("res://Shaders/pixel-art-shaders/shaders/dissolve.gdshader")
		shader_material.set_shader_parameter("noise_texture", load("res://Shaders/pixel-art-shaders/burn-noise.tres"))
		shader_material.set_shader_parameter("noise_scale", 1.5)
		shader_material.set_shader_parameter("palette_shift", false)
		shader_material.set_shader_parameter("use_dissolve_color", true)
		shader_material.set_shader_parameter("dissolve_color_from", Color(1.0, 0.9, 0.4, 1.0))
		shader_material.set_shader_parameter("dissolve_color_to", Color(1.0, 0.4, 0.1, 1.0))
		shader_material.set_shader_parameter("dissolve_color_strength", 1.5)
		shader_material.set_shader_parameter("dissolve_border_size", 0.3)
		shader_material.set_shader_parameter("pixelization", 0)
		shader_material.set_shader_parameter("time", 0.0)
		title_sprite.material = shader_material
		var tween = create_tween()
		tween.tween_method(func(value):
			shader_material.set_shader_parameter("time", value)
		, 0.0, 1.0, 0.7)
		await tween.finished
		title_sprite.modulate.a = 0.0
	
	# Fade out background
	if background_sprite:
		var bg_tween = create_tween()
		bg_tween.tween_property(background_sprite, "modulate:a", 0.0, 0.5)
		await bg_tween.finished
