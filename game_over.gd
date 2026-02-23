extends Node

## Game Over scene controller — phased cinematic reveal
## Phase 1: Hold black (player death fade already did the transition)
## Phase 2: Fade overlay to dark background + "Game Over" text fire-dissolves in
## Phase 3: Resume button fire-dissolves in
## Phase 4: Quit label fades in, interaction enabled
## Phase 5: Input — Resume → restart, Quit → main menu

# ── Timing ────────────────────────────────────────────────────────
const HOLD_BLACK_DURATION: float = 0.6
const OVERLAY_FADE_DURATION: float = 1.0
const TEXT_DISSOLVE_DURATION: float = 2.5
const RESUME_DISSOLVE_DELAY: float = 0.4
const RESUME_DISSOLVE_DURATION: float = 1.8
const QUIT_FADE_DELAY: float = 0.3
const QUIT_FADE_DURATION: float = 0.6

# ── Fire dissolve settings ────────────────────────────────────────
const NOISE_SCALE: float = 1.0
const DISSOLVE_COLOR_FROM: Color = Color(1.0, 0.9, 0.4, 1.0)
const DISSOLVE_COLOR_TO: Color = Color(1.0, 0.4, 0.1, 1.0)
const DISSOLVE_COLOR_STRENGTH: float = 1.0
const DISSOLVE_BORDER_SIZE: float = 0.1

# ── Background tint (dark, not fully black) ───────────────────────
const BG_COLOR: Color = Color(0.06, 0.04, 0.08, 0.92)

# ── Node references ──────────────────────────────────────────────
@onready var canvas_layer: CanvasLayer = $CanvasLayer if has_node("CanvasLayer") else null
@onready var game_over_label: Label = get_node_or_null("CanvasLayer/game over")
@onready var quit_label: Label = get_node_or_null("CanvasLayer/quit")
@onready var resume_button: TextureButton = get_node_or_null("CanvasLayer/Retry")

func _ready() -> void:
	# Hide everything initially
	if game_over_label:
		game_over_label.modulate.a = 0.0
	if quit_label:
		quit_label.modulate.a = 0.0
	if resume_button:
		resume_button.modulate.a = 0.0

	_play_sequence()

func _play_sequence() -> void:
	# ── Phase 1: Hold black ───────────────────────────────────────
	# Create full-screen black overlay (player death fade already transitioned us here)
	var overlay := ColorRect.new()
	overlay.color = Color.BLACK
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = -1  # Behind text and buttons
	if canvas_layer:
		canvas_layer.add_child(overlay)
		# Move overlay to be the first child so it renders behind everything
		canvas_layer.move_child(overlay, 0)
	else:
		add_child(overlay)

	await get_tree().create_timer(HOLD_BLACK_DURATION).timeout

	# ── Phase 2: Fade overlay to dark bg + fire-dissolve "Game Over" text ──
	var bg_tween := create_tween()
	bg_tween.tween_property(overlay, "color", BG_COLOR, OVERLAY_FADE_DURATION)

	# Slight delay then fire-dissolve the title text
	await get_tree().create_timer(0.3).timeout
	if game_over_label:
		_fire_reveal(game_over_label, TEXT_DISSOLVE_DURATION)

	# Wait for text dissolve to mostly finish before showing buttons
	await get_tree().create_timer(TEXT_DISSOLVE_DURATION * 0.7).timeout

	# ── Phase 3: Resume button fire-dissolves in ──────────────────
	await get_tree().create_timer(RESUME_DISSOLVE_DELAY).timeout
	if resume_button:
		_fire_reveal(resume_button, RESUME_DISSOLVE_DURATION)

	# ── Phase 4: Quit label fades in ─────────────────────────────
	await get_tree().create_timer(QUIT_FADE_DELAY).timeout
	if quit_label:
		var quit_tween := create_tween()
		quit_tween.tween_property(quit_label, "modulate:a", 1.0, QUIT_FADE_DURATION)
		await quit_tween.finished

	# ── Phase 5: Enable interaction ──────────────────────────────
	if resume_button and "interaction_enabled" in resume_button:
		resume_button.interaction_enabled = true
	if quit_label and "interaction_enabled" in quit_label:
		quit_label.interaction_enabled = true


# ──────────────────────────────────────────────────────────────────
#  FIRE DISSOLVE helper (same pattern as title_screen.gd)
# ──────────────────────────────────────────────────────────────────
func _create_dissolve_shader() -> ShaderMaterial:
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
	if not node:
		return
	node.modulate.a = 1.0
	var shader := _create_dissolve_shader()
	shader.set_shader_parameter("time", 1.0)
	node.material = shader

	var tween := create_tween()
	tween.tween_method(
		func(value: float) -> void:
			shader.set_shader_parameter("time", value),
		1.0, 0.0, duration
	)
	await tween.finished
