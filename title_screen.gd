extends Control

## Main Menu — 6-phase animated reveal with mouse parallax
## Phase 1: Big title on black
## Phase 2: Background fades in, menu bar fades in
## Phase 3: Title flies to final position with motion trail
## Phase 4: Start button fire-dissolves in, quit label fades in, BGM fades in
## Phase 5: Mouse parallax (always active after Phase 3)
## Phase 6: Start pressed — burn out and transition

# ── Timing Constants ──────────────────────────────────────────────
const TITLE_HOLD_DELAY: float = 0.4          # Phase 1 — pause before fire reveal
const TITLE_REVEAL_DURATION: float = 2.5     # Phase 1 — title fire-dissolves in
const POST_REVEAL_HOLD: float = 1.0          # Phase 1 — hold after reveal
const BG_FADE_DURATION: float = 2.0          # Phase 2 — overlay fades DURING fly
const MENU_BAR_FADE_DURATION: float = 1.5    # Phase 2 — menu bar appears
const FLY_DURATION: float = 1.4              # Phase 2 — title flight (slower)
const TRAIL_FADE_DURATION: float = 0.5       # Phase 2 — ghost fade after landing
const BUTTON_DELAY: float = 0.6              # Phase 3 — pause before button
const BUTTON_REVEAL_DURATION: float = 1.0    # Phase 3 — fire reveal
const BGM_FADE_IN_DURATION: float = 2.0      # Phase 3 — music fade
const BGM_FADE_START_DB: float = -40.0
const BGM_TARGET_DB: float = -5.0
const QUIT_REVEAL_MAX_WAIT: float = 12.0

# Burnout (Phase 6)
const BURNOUT_BUTTON_DURATION: float = 0.5
const BURNOUT_TITLE_DURATION: float = 0.7
const BURNOUT_BG_DURATION: float = 0.5

# Fire shader
const NOISE_SCALE: float = 1.5
const DISSOLVE_BORDER_SIZE: float = 0.3
const DISSOLVE_COLOR_STRENGTH: float = 1.5
const DISSOLVE_COLOR_FROM: Color = Color(1.0, 0.9, 0.4, 1.0)
const DISSOLVE_COLOR_TO: Color = Color(1.0, 0.4, 0.1, 1.0)

# Title fly — scale multiplier for the "big" state
const TITLE_BIG_SCALE_MULT: float = 1.68

# Trail ghosts
const TRAIL_COUNT: int = 9
const TRAIL_HISTORY_LENGTH: int = 55  # frames of position history

# Parallax strengths (px offset at full mouse deflection)
const PARALLAX_BG: float = 6.0
const PARALLAX_MENU_BAR: float = 10.0
const PARALLAX_QUIT: float = 16.0
const PARALLAX_START: float = 18.0
const PARALLAX_TITLE: float = 22.0
const PARALLAX_SMOOTHING: float = 6.0

# ── Node References ───────────────────────────────────────────────
@onready var camera: Camera2D = $Camera2D if has_node("Camera2D") else null
@onready var background_sprite: AnimatedSprite2D = get_node_or_null("BG")
@onready var title_sprite: Node = get_node_or_null("Title")
@onready var start_button: Node = get_node_or_null("Start")
@onready var quit_label: Label = get_node_or_null("Quit game")
@onready var menu_bar: Node = get_node_or_null("Menu Bar")
@onready var bgm: Node = get_node_or_null("BGM")

# ── Parallax State ────────────────────────────────────────────────
var parallax_active: bool = false
var parallax_offset: Vector2 = Vector2.ZERO
var base_pos_bg: Vector2
var base_pos_menu_bar: Vector2
var base_pos_start: Vector2
var base_pos_title: Vector2
var base_pos_quit_offset_left: float
var base_pos_quit_offset_top: float

# Trail sprites (used during fly AND parallax idle)
var trail_sprites: Array[Sprite2D] = []
var trail_history: Array[Vector2] = []     # position ring buffer for idle trail
var trail_scale_history: Array[Vector2] = []

# Final (scene) positions & scales
var title_final_pos: Vector2
var title_final_scale: Vector2

var fade_overlay: ColorRect

# Title fire-dissolve shader (kept for burnout)
var title_shader: ShaderMaterial = null

# ──────────────────────────────────────────────────────────────────
#  READY
# ──────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Camera
	if camera:
		camera.enabled = true
		camera.make_current()

	# Record final (scene-authored) positions for parallax base
	if background_sprite:
		base_pos_bg = background_sprite.position
		background_sprite.modulate.a = 1.0
		if background_sprite.sprite_frames:
			background_sprite.play()

	if menu_bar:
		base_pos_menu_bar = menu_bar.position
		menu_bar.modulate.a = 0.0  # hidden until Phase 2

	if start_button:
		base_pos_start = start_button.position
		start_button.modulate.a = 0.0

	if title_sprite:
		title_final_pos = title_sprite.position
		title_final_scale = title_sprite.scale
		# Phase 1: big & centered on camera, starts HIDDEN (fire reveal)
		var center: Vector2 = camera.global_position if camera else Vector2.ZERO
		title_sprite.position = center
		title_sprite.scale = title_final_scale * TITLE_BIG_SCALE_MULT
		title_sprite.modulate.a = 0.0  # hidden — fire reveal will show it
		title_sprite.z_index = 150  # above fade overlay (z=100) during Phase 1
		base_pos_title = title_final_pos  # parallax uses final pos

	if quit_label:
		base_pos_quit_offset_left = quit_label.offset_left
		base_pos_quit_offset_top = quit_label.offset_top
		quit_label.modulate.a = 0.0  # quit_label.gd handles its own fade-in

	# Prevent early BGM
	if bgm and "autoplay" in bgm:
		bgm.autoplay = false

	# Create fade overlay (covers everything)
	fade_overlay = ColorRect.new()
	fade_overlay.color = Color.BLACK
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_overlay.z_index = 100
	fade_overlay.position = Vector2(-5462.0, -6250.0)
	fade_overlay.size = Vector2(9111.0 + 5462.0, 8323.0 + 6250.0)
	add_child(fade_overlay)

	# Create trail ghost sprites (same texture as Title)
	_create_trail_sprites()

	# Gooo0o0ooo0o
	_reveal_sequence()


# ──────────────────────────────────────────────────────────────────
#  PROCESS — Phase 5 parallax
# ──────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not parallax_active:
		return

	var vp_size: Vector2 = get_viewport_rect().size
	if vp_size.x == 0.0 or vp_size.y == 0.0:
		return

	var mouse_norm: Vector2 = (get_viewport().get_mouse_position() / vp_size - Vector2(0.5, 0.5)) * 2.0
	parallax_offset = parallax_offset.lerp(mouse_norm, delta * PARALLAX_SMOOTHING)

	if background_sprite:
		background_sprite.position = base_pos_bg + parallax_offset * PARALLAX_BG
	if menu_bar:
		menu_bar.position = base_pos_menu_bar + parallax_offset * PARALLAX_MENU_BAR
	if start_button:
		start_button.position = base_pos_start + parallax_offset * PARALLAX_START
	if title_sprite:
		title_sprite.position = base_pos_title + parallax_offset * PARALLAX_TITLE
	if quit_label:
		quit_label.offset_left = base_pos_quit_offset_left + parallax_offset.x * PARALLAX_QUIT
		quit_label.offset_top = base_pos_quit_offset_top + parallax_offset.y * PARALLAX_QUIT

	# Always-on parallax trail — ghost sprites follow title with delay
	_update_idle_trail()


# ──────────────────────────────────────────────────────────────────
#  REVEAL SEQUENCE (Phases 1-4)
# ──────────────────────────────────────────────────────────────────
func _reveal_sequence() -> void:
	# ── Phase 1: fire-dissolve title in on black ──
	await get_tree().create_timer(TITLE_HOLD_DELAY).timeout
	if title_sprite:
		await _fire_reveal(title_sprite, TITLE_REVEAL_DURATION)
		# Keep the shader on title (we'll reuse for burnout), just set time=0
		title_shader = title_sprite.material as ShaderMaterial

	# Hold the big title on screen briefly
	await get_tree().create_timer(POST_REVEAL_HOLD).timeout

	# ── Phase 2: BG fades in WHILE title flies + shrinks to position ──
	# Start all three simultaneously: overlay fade, menu bar fade, title fly
	if fade_overlay:
		var bg_tween := create_tween()
		bg_tween.set_parallel(true)
		bg_tween.tween_property(fade_overlay, "color", Color(0, 0, 0, 0), BG_FADE_DURATION)
		if menu_bar:
			bg_tween.tween_property(menu_bar, "modulate:a", 1.0, MENU_BAR_FADE_DURATION)

	# Fly title to final position (runs alongside the BG fade)
	await _fly_title_to_position()

	# Make sure overlay is done and hidden
	if fade_overlay:
		fade_overlay.visible = false

	# Restore title z_index to normal now that overlay is gone
	if title_sprite:
		title_sprite.z_index = 2

	# Enable parallax + idle trail after title lands
	parallax_active = true
	_show_trail_sprites()

	# ── Phase 3: start button fire reveal, quit label, BGM ──
	await get_tree().create_timer(BUTTON_DELAY).timeout

	if start_button:
		await _fire_reveal(start_button, BUTTON_REVEAL_DURATION)
		start_button.material = null
		if "interaction_enabled" in start_button:
			start_button.interaction_enabled = true

	# Wait for quit label to finish its own fade-in, then start BGM
	await _wait_for_quit_reveal()
	_play_bgm_fade_in()


# ──────────────────────────────────────────────────────────────────
#  TRAIL SYSTEM — used during fly AND during parallax idle
# ──────────────────────────────────────────────────────────────────
func _create_trail_sprites() -> void:
	if not title_sprite or not title_sprite is Sprite2D:
		return

	var src: Sprite2D = title_sprite as Sprite2D
	for i in range(TRAIL_COUNT):
		var ghost := Sprite2D.new()
		ghost.texture = src.texture
		ghost.z_index = title_sprite.z_index - 1
		ghost.modulate.a = 0.0
		ghost.visible = false
		add_child(ghost)
		trail_sprites.append(ghost)

	# Initialize history buffers
	var init_pos: Vector2 = title_sprite.position
	var init_scale: Vector2 = title_sprite.scale
	for i in range(TRAIL_HISTORY_LENGTH):
		trail_history.append(init_pos)
		trail_scale_history.append(init_scale)


func _show_trail_sprites() -> void:
	"""Make trail ghosts visible for idle parallax trail."""
	for ghost in trail_sprites:
		ghost.visible = true


func _hide_trail_sprites() -> void:
	"""Hide all trail ghosts."""
	for ghost in trail_sprites:
		ghost.visible = false
		ghost.modulate.a = 0.0


func _push_trail_position(pos: Vector2, scl: Vector2) -> void:
	"""Push a position/scale into the ring buffer."""
	trail_history.push_front(pos)
	trail_scale_history.push_front(scl)
	if trail_history.size() > TRAIL_HISTORY_LENGTH:
		trail_history.pop_back()
		trail_scale_history.pop_back()


func _apply_trail_ghosts(opacity_mult: float = 1.0) -> void:
	"""Position trail ghosts from history with given opacity multiplier."""
	var max_i: int = maxi(TRAIL_COUNT - 1, 1)
	for i in range(TRAIL_COUNT):
		var sample_idx: int = mini((i + 1) * 5, trail_history.size() - 1)
		trail_sprites[i].position = trail_history[sample_idx]
		trail_sprites[i].scale = trail_scale_history[sample_idx]
		trail_sprites[i].modulate.a = lerpf(0.35, 0.04, float(i) / float(max_i)) * opacity_mult


func _update_idle_trail() -> void:
	"""Called every frame during parallax — subtle trail behind title."""
	if trail_sprites.is_empty() or not title_sprite:
		return
	_push_trail_position(title_sprite.position, title_sprite.scale)
	_apply_trail_ghosts(0.6)  # subtle during idle


func _fly_title_to_position() -> void:
	if not title_sprite:
		return

	var start_pos: Vector2 = title_sprite.position
	var end_pos: Vector2 = title_final_pos
	var start_scale: Vector2 = title_sprite.scale
	var end_scale: Vector2 = title_final_scale

	# Reset history to start position
	trail_history.clear()
	trail_scale_history.clear()
	for i in range(TRAIL_HISTORY_LENGTH):
		trail_history.append(start_pos)
		trail_scale_history.append(start_scale)

	# Show ghost sprites
	for ghost in trail_sprites:
		ghost.visible = true
		ghost.modulate.a = 0.0

	# Manual per-frame animation using ease-out cubic
	var elapsed: float = 0.0
	while elapsed < FLY_DURATION:
		var delta: float = get_process_delta_time()
		elapsed += delta
		var progress: float = clampf(elapsed / FLY_DURATION, 0.0, 1.0)

		# Ease-out cubic: 1 - (1-t)^3
		var t: float = 1.0 - pow(1.0 - progress, 3.0)

		# Interpolate title
		title_sprite.position = start_pos.lerp(end_pos, t)
		title_sprite.scale = start_scale.lerp(end_scale, t)

		# Push into shared history
		_push_trail_position(title_sprite.position, title_sprite.scale)
		_apply_trail_ghosts(progress)  # ramp up opacity as it flies

		await get_tree().process_frame

	# Snap title to exact final
	title_sprite.position = end_pos
	title_sprite.scale = end_scale

	# Fade fly ghosts down to idle level (don't hide — idle trail takes over)
	var fade_tween := create_tween().set_parallel(true)
	for ghost in trail_sprites:
		fade_tween.tween_property(ghost, "modulate:a", ghost.modulate.a * 0.5, TRAIL_FADE_DURATION)
	await fade_tween.finished


# ──────────────────────────────────────────────────────────────────
#  FIRE DISSOLVE helpers
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


func _fire_burnout(node: Node, duration: float) -> void:
	if not node:
		return
	var shader := _create_dissolve_shader()
	shader.set_shader_parameter("time", 0.0)
	node.material = shader

	var tween := create_tween()
	tween.tween_method(
		func(value: float) -> void:
			shader.set_shader_parameter("time", value),
		0.0, 1.0, duration
	)
	await tween.finished


# ──────────────────────────────────────────────────────────────────
#  PHASE 4 — BGM & quit label
# ──────────────────────────────────────────────────────────────────
func _wait_for_quit_reveal() -> void:
	if not quit_label:
		return
	var elapsed := 0.0
	while elapsed < QUIT_REVEAL_MAX_WAIT and quit_label.modulate.a < 0.99:
		await get_tree().process_frame
		elapsed += get_process_delta_time()


func _play_bgm_fade_in() -> void:
	if not bgm or not bgm.has_method("play"):
		return
	if "volume_db" in bgm:
		bgm.volume_db = BGM_FADE_START_DB
	bgm.play()
	if "volume_db" in bgm:
		var tween := create_tween()
		tween.tween_property(bgm, "volume_db", BGM_TARGET_DB, BGM_FADE_IN_DURATION)


# ──────────────────────────────────────────────────────────────────
#  PHASE 6 — Start pressed exit sequence
# ──────────────────────────────────────────────────────────────────
func _on_start_pressed() -> void:
	# Stop parallax and hide trail
	parallax_active = false
	_hide_trail_sprites()

	# Disable start button interaction immediately
	if start_button and "interaction_enabled" in start_button:
		start_button.interaction_enabled = false

	# Burn out start button
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
		var fade_tween := create_tween()
		fade_tween.tween_property(fade_overlay, "color", Color.BLACK, BURNOUT_BG_DURATION)
		await fade_tween.finished

	get_tree().change_scene_to_file("res://Tutorial Land.tscn")
