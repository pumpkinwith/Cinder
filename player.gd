extends CharacterBody2D

# Use centralized config
const DAMAGE_TEXT_SCENE = preload("res://DamageText.tscn")

# Y-sort for isometric depth
const USE_Y_SORT: bool = true

@export var move_speed: float = 40
@export var attack_cooldown_time: float = 0.4
@export var health: int = 100
@export var max_health: int = 100
@export var elevation: float = 0.0  # Current elevation level (0 = ground, 1 = platform, etc.)
@export var max_elevation_step: float = 1.0  # Maximum elevation difference player can climb
@export var fall_damage_threshold: float = 2.0  # Elevation difference that causes fall damage

# Signals for better event handling
signal health_changed(new_health: int, max_health: int)
signal oil_changed(new_stage: int)
signal died

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area: Area2D = $Attack if has_node("Attack") else null
@onready var hitbox: Area2D = $"Hit Box" if has_node("Hit Box") else null
@onready var footstep_sound: AudioStreamPlayer = $FootstepSound if has_node("FootstepSound") else null
@onready var camera: Camera2D = $Camera2D if has_node("Camera2D") else null
@onready var sword_swing_sound: AudioStreamPlayer = $SwordSwingSound if has_node("SwordSwingSound") else null
@onready var attack_voice_sound: AudioStreamPlayer = $AttackVoiceSound if has_node("AttackVoiceSound") else null
@onready var crit_sound: AudioStreamPlayer = $CritSound if has_node("CritSound") else null
@onready var damage_sound: AudioStreamPlayer = $DamageSound if has_node("DamageSound") else null

# Terrain references (all elevation levels)
var terrain_0: TileMapLayer = null
var terrain_1: TileMapLayer = null
var terrain_2: TileMapLayer = null
var current_terrain: TileMapLayer = null  # The terrain layer player is currently on

var is_moving: bool = false
var target_pos: Vector2
var previous_pos: Vector2
var current_direction: String = "SE"
var is_stunned: bool = false
var stun_timer: float = 0.2
var is_attacking: bool = false
var attack_cooldown: float = 0.1
var is_knockback: bool = false
var knockback_velocity: Vector2 = Vector2.ZERO
var is_dead: bool = false
var is_invincible: bool = false
var invincibility_timer: float = 0.0
var camera_shake_strength: float = 0.0
var camera_shake_decay: float = 5.0
var move_input: Vector2 = Vector2.ZERO  # Continuous movement input
var input_buffer_time: float = 0.0
var move_stuck_timer: float = 0.0
@export var camera_smoothing_speed: float = 6.0
@export var camera_lookahead: float = 12.0
@export var camera_max_lookahead_speed: float = 200.0
var current_crit_chance: float = 0.05  # Current crit chance (starts at 5%)
var crit_boost_timer: float = 0.0  # Timer to track time since last hit
var combo_count: int = 0  # Number of consecutive hits in combo
var has_hit_enemy: bool = false  # Track if we're in a combo
var spawn_reveal_active: bool = false  # Track if spawn reveal is happening
var is_on_slope: bool = false  # Track if player is on a slope tile
var was_on_slope: bool = false  # Track previous slope state
var slope_elevation_offset: float = 0.0  # Current elevation offset from slope
var slope_target_elevation: float = 0.0  # Target elevation offset
var slope_up_dir: Vector2 = Vector2.ZERO
var slope_sprite_rotation: float = 0.0  # Character lean on slopes
var slope_sprite_target_rotation: float = 0.0  # Target rotation
var base_animation_speed: float = 1.0  # Store original animation speed
var shadow_rect: ColorRect = null  # Blob shadow reference for slope tracking

# Oil Gauge system (Hollow Knight-style heal resource)
var oil_percent: float = 0.0       # 0.0 to 100.0
var is_channeling: bool = false    # True while holding heal key
var channel_timer: float = 0.0     # Accumulator for channel time
const MAX_OIL: float = 100.0
const OIL_STAGE_SIZE: float = 100.0 / 6.0  # ~16.67% per stage
const HEAL_AMOUNT: int = 15
const CHANNEL_TIME: float = 0.8

const KNOCKBACK_FRICTION: float = 500.0
const KNOCKBACK_STRENGTH: float = 120.0
const INVINCIBILITY_TIME: float = 1.0
const BLINK_DURATION: float = 0.02
const CAMERA_SHAKE_BASE: float = 3.0
const MOVE_STUCK_TIMEOUT: float = 0.16
const MOVE_MIN_PROGRESS: float = 0.02
const SLOPE_MAX_VISUAL_OFFSET: float = 16.0  # Vertical movement on slopes (increased for visibility)
const SLOPE_UPHILL_SPEED_MULT: float = 0.92  # 8% slower uphill
const SLOPE_DOWNHILL_SPEED_MULT: float = 1.05  # 5% faster downhill
const SLOPE_ROTATION_DEGREES: float = 2.0  # Subtle lean (1-2 pixels)
const SLOPE_UPHILL_ANIM_SPEED: float = 0.85  # Slower, compressed steps uphill
const SLOPE_DOWNHILL_ANIM_SPEED: float = 1.15  # Faster steps downhill
const SLOPE_INPUT_LOCK_DOT: float = 0.8
const SLOPE_PATH_SNAP_RATE: float = 0.45
const GAME_OVER_SCENE_CANDIDATES: Array[String] = [
	"res://game over.tscn",
	"res://game_over.tscn",
	"res://gameover.tscn"
]

func _ready() -> void:
	add_to_group("player")
	target_pos = global_position
	previous_pos = global_position
	animated_sprite.play("Idle_" + current_direction)
	
	# Find all terrain levels
	var parent = get_parent()
	if parent:
		terrain_0 = parent.get_node_or_null("Terrain 0")
		terrain_1 = parent.get_node_or_null("Terrain 1")
		terrain_2 = parent.get_node_or_null("Terrain 2")
		# Start on ground level
		current_terrain = terrain_0
		if terrain_0:
			elevation = 0.0
	
	# Create blob shadow under feet (double dither shader)
	_create_blob_shadow()
	
	# Ensure all walk animations are set to loop
	if animated_sprite.sprite_frames:
		for direction in ["SE", "NW", "SW", "NE"]:
			var walk_anim: String = "Walk_" + direction
			if animated_sprite.sprite_frames.has_animation(walk_anim):
				animated_sprite.sprite_frames.set_animation_loop(walk_anim, true)
	
	# Apply fire reveal effect on spawn
	_apply_spawn_reveal()
	
	
	if hitbox:
		# Ensure the hitbox knows its source (this player) and let the hit_box script handle area_entered
		hitbox.source = self
	
	# (Attack animation handling removed — hitbox now controls attack window)
	
	# Setup audio players if they don't exist
	if not footstep_sound:
		footstep_sound = AudioStreamPlayer.new()
		footstep_sound.name = "FootstepSound"
		footstep_sound.stream = load("res://Sound/Effect/Grass_Footstep.mp3")
		footstep_sound.volume_db = -20.0
		add_child(footstep_sound)
	
	if not sword_swing_sound:
		sword_swing_sound = AudioStreamPlayer.new()
		sword_swing_sound.name = "SwordSwingSound"
		sword_swing_sound.stream = load("res://Sound/Effect/Sword_Swing.mp3")
		sword_swing_sound.volume_db = -6.0
		add_child(sword_swing_sound)
	
	if not attack_voice_sound:
		attack_voice_sound = AudioStreamPlayer.new()
		attack_voice_sound.name = "AttackVoiceSound"
		attack_voice_sound.stream = load("res://Sound/Effect/OWW.mp3")
		attack_voice_sound.volume_db = -10.0
		add_child(attack_voice_sound)
	
	if not crit_sound:
		crit_sound = AudioStreamPlayer.new()
		crit_sound.name = "CritSound"
		crit_sound.stream = load("res://Sound/Effect/OW.mp3")
		crit_sound.volume_db = -6.0
		add_child(crit_sound)
	
	if not damage_sound:
		damage_sound = AudioStreamPlayer.new()
		damage_sound.name = "DamageSound"
		damage_sound.stream = load("res://Sound/Effect/OW.mp3")
		damage_sound.volume_db = -12.0
		add_child(damage_sound)
	
	# Emit initial health
	# Ensure sensible default volumes even if the nodes already exist in the scene
	if sword_swing_sound:
		sword_swing_sound.volume_db = -6.0
	if attack_voice_sound:
		attack_voice_sound.volume_db = -10.0
	if crit_sound:
		crit_sound.volume_db = -6.0


func _create_blob_shadow() -> void:
	var shadow := ColorRect.new()
	shadow.name = "ShadowRect"
	shadow.size = Vector2(12, 4)
	shadow.position = Vector2(-6, 6)
	shadow.z_index = -1
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = load("res://Shaders/Double_Dither.gdshader")
	shader_mat.set_shader_parameter("center", Vector2(0.5, 0.5))
	shader_mat.set_shader_parameter("radius", 0.45)
	shader_mat.set_shader_parameter("pixel_size", 1.0)
	shader_mat.set_shader_parameter("resolution", Vector2(12, 4))
	shader_mat.set_shader_parameter("bayer_size", 0)
	shader_mat.set_shader_parameter("interpolate", true)
	shader_mat.set_shader_parameter("falloff", 2.0)
	shader_mat.set_shader_parameter("color", Color(0, 0, 0, 0.35))
	shader_mat.set_shader_parameter("invert", false)
	shadow.material = shader_mat
	
	add_child(shadow)
	shadow_rect = shadow

	health_changed.emit(health, max_health)


# ──────────────────────────────────────────────────────────────────
#  OIL GAUGE — Hollow Knight-style heal resource
# ──────────────────────────────────────────────────────────────────
func get_oil_stage() -> int:
	"""Return current stage 0-6 based on oil_percent."""
	return mini(int(oil_percent / OIL_STAGE_SIZE), 6)


func update_oil_ui() -> void:
	"""Emit oil_changed signal so the HUD Oil sprite can update."""
	oil_changed.emit(get_oil_stage())


func _handle_healing(delta: float) -> void:
	"""Hold-to-heal: drains one oil stage per CHANNEL_TIME, restores HEAL_AMOUNT HP."""
	var can_heal := get_oil_stage() >= 1 and health < max_health

	if Input.is_action_pressed("heal") and can_heal and not is_attacking and not is_knockback and not is_stunned:
		is_channeling = true
		channel_timer += delta

		if channel_timer >= CHANNEL_TIME:
			oil_percent = maxf(oil_percent - OIL_STAGE_SIZE, 0.0)
			health = mini(health + HEAL_AMOUNT, max_health)
			health_changed.emit(health, max_health)
			channel_timer = 0.0
			update_oil_ui()
	else:
		is_channeling = false
		channel_timer = 0.0


func _physics_process(delta: float) -> void:
	# Update z-index for proper depth sorting in isometric view
	# Use Y position of sprite bottom (feet) for sorting, minus elevation for 3D effect
	# Add base offset to ensure player renders above ground tiles (which have z_index = 1)
	z_index = 1000 + int(global_position.y + 4 - elevation)
	
	# Smoothly interpolate slope elevation offset only when moving
	# This prevents animation from continuing when player stops
	if velocity.length() > 0.1:  # Only animate when actually moving
		slope_elevation_offset = lerp(slope_elevation_offset, slope_target_elevation, delta * 2.5)
		slope_sprite_rotation = lerp(slope_sprite_rotation, slope_sprite_target_rotation, delta * 4.0)
	
	# Apply slope visual effects to sprite
	if animated_sprite:
		animated_sprite.position.y = slope_elevation_offset  # Vertical offset
		animated_sprite.rotation_degrees = slope_sprite_rotation  # Subtle lean
	
	# Keep shadow on the slope surface (follows sprite feet)
	if shadow_rect:
		shadow_rect.position.y = 6 + slope_elevation_offset
	
	# Handle attack cooldown
	if attack_cooldown > 0:
		attack_cooldown -= delta
	

	# Handle invincibility timer
	if is_invincible:
		invincibility_timer -= delta
		if invincibility_timer <= 0:
			is_invincible = false
	
	# Handle camera shake
	var shake_offset := Vector2.ZERO
	if camera_shake_strength > 0:
		camera_shake_strength = max(camera_shake_strength - camera_shake_decay * delta, 0.0)
		shake_offset = Vector2(
			randf_range(-camera_shake_strength, camera_shake_strength),
			randf_range(-camera_shake_strength, camera_shake_strength)
		)
	else:
		shake_offset = Vector2.ZERO

	# Smooth camera follow with lookahead based on player velocity
	if camera:
		if not camera.is_current():
			camera.make_current()
		# Calculate lookahead in movement direction
		var look := Vector2.ZERO
		if velocity.length_squared() > 1.0:
			var speed_ratio := minf(velocity.length() / camera_max_lookahead_speed, 1.0)
			look = velocity.normalized() * camera_lookahead * speed_ratio
		
		var target_cam_pos := global_position + look
		var smoothing_factor := clampf(camera_smoothing_speed * delta * 1.5, 0.0, 1.0)
		camera.global_position = camera.global_position.lerp(target_cam_pos, smoothing_factor)
		camera.offset = shake_offset
	
	# Don't process if dead
	if is_dead:
		return
	
	# Oil gauge — add oil on input, handle healing channel
	if Input.is_action_just_pressed("add_oil"):
		oil_percent = minf(oil_percent + 10.0, MAX_OIL)
		update_oil_ui()
	_handle_healing(delta)
	
	# Handle knockback
	if is_knockback:
		velocity = knockback_velocity
		move_and_slide()
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_FRICTION * delta)
		
		if knockback_velocity.length() < 1.0:
			is_knockback = false
			knockback_velocity = Vector2.ZERO
			velocity = Vector2.ZERO
			# Note: Removed position snapping to let camera follow smoothly
			return
	
	# Handle stun timer
	if is_stunned:
		stun_timer -= delta
		
		# End stun
		if stun_timer <= 0:
			is_stunned = false
		return
	
	# Don't process input if attacking
	if is_attacking:
		return
	
	# Check attack input
	if Input.is_action_just_pressed("Attack") and attack_cooldown <= 0:
		attack()
		return
	
	# Continuous movement (no tile-based stepping)
	var move_direction = Vector2.ZERO
	var step = _get_move_step()
	
	if Input.is_key_pressed(KEY_W):
		move_direction = Vector2(step.x, -step.y).normalized()
		current_direction = "NE"
	elif Input.is_key_pressed(KEY_A):
		move_direction = Vector2(-step.x, -step.y).normalized()
		current_direction = "NW"
	elif Input.is_key_pressed(KEY_S):
		move_direction = Vector2(-step.x, step.y).normalized()
		current_direction = "SW"
	elif Input.is_key_pressed(KEY_D):
		move_direction = Vector2(step.x, step.y).normalized()
		current_direction = "SE"
	
	# Treat slope tiles as directional bridges (no sideways movement).
	move_direction = _lock_slope_input(move_direction)
	if move_direction != Vector2.ZERO:
		current_direction = _direction_from_vector(move_direction)
	
	# Apply movement
	if move_direction != Vector2.ZERO:
		var intended_pos: Vector2 = global_position + move_direction * move_speed * delta
		if not _can_step_to_position(intended_pos):
			velocity = Vector2.ZERO
			if not animated_sprite.animation.begins_with("Idle_"):
				animated_sprite.play("Idle_" + current_direction)
			return

		velocity = move_direction * move_speed
		
		# Check elevation transition BEFORE moving
		var old_elevation = elevation
		_update_elevation_layer()
		
		# Check if on slope and apply speed/visual adjustments
		var current_speed_mult = 1.0
		var is_on_slope_tile = _check_if_on_slope(intended_pos)
		
		if is_on_slope_tile:
			var moving_up = (elevation > old_elevation) or (move_direction.y < 0 and is_on_slope)
			var moving_down = (elevation < old_elevation) or (move_direction.y > 0 and is_on_slope)
			
			# Calculate slope height based on elevation difference
			var elevation_diff = abs(elevation - old_elevation)
			if elevation_diff == 0.0:
				elevation_diff = 1.0  # Default for slopes within same elevation
			
			# REALISTIC SLOPE ANIMATION using Pythagorean theorem
			# Tile: 8x8 pixels, diagonal slope = sqrt(8² + 8²) ≈ 11.31 ≈ 12 pixels
			const TILE_SIZE = 8.0
			const SLOPE_DIAGONAL = 12.0  # sqrt(8² + 8²) rounded
			
			# Calculate slope movement based on player's actual direction
			# When moving diagonally (e.g., NW), player moves:
			# - Horizontal: 8 tiles in direction (NW)
			# - Vertical: 12 tiles upward (North) to simulate climbing
			
			var horizontal_movement = move_direction.normalized() * TILE_SIZE * elevation_diff
			var vertical_climb = Vector2(0, -SLOPE_DIAGONAL * elevation_diff)  # Always climb up (negative Y)
			
			# Combine horizontal movement with vertical climb for realistic slope traversal
			var total_slope_offset = horizontal_movement + vertical_climb
			
			if moving_up:
				# Uphill: slower speed, compressed steps, lean forward
				current_speed_mult = SLOPE_UPHILL_SPEED_MULT
				slope_target_elevation = total_slope_offset.y  # Use calculated vertical climb
				slope_sprite_target_rotation = -SLOPE_ROTATION_DEGREES * elevation_diff
				if animated_sprite:
					animated_sprite.speed_scale = SLOPE_UPHILL_ANIM_SPEED
					base_animation_speed = SLOPE_UPHILL_ANIM_SPEED
			elif moving_down:
				# Downhill: faster speed, quicker steps, lean back
				current_speed_mult = SLOPE_DOWNHILL_SPEED_MULT
				slope_target_elevation = -total_slope_offset.y  # Invert for going down
				slope_sprite_target_rotation = SLOPE_ROTATION_DEGREES * elevation_diff
				if animated_sprite:
					animated_sprite.speed_scale = SLOPE_DOWNHILL_ANIM_SPEED
					base_animation_speed = SLOPE_DOWNHILL_ANIM_SPEED
			else:
				# On slope but moving sideways - gradually return to center
				slope_target_elevation = lerp(slope_target_elevation, 0.0, 0.3)
				slope_sprite_target_rotation = 0.0
				if animated_sprite:
					animated_sprite.speed_scale = 1.0
					base_animation_speed = 1.0
			is_on_slope = true
			was_on_slope = true
		else:
			# Just exited slope - smoothly finish animation to neutral position
			if was_on_slope:
				# Let animation finish by transitioning to neutral (0.0)
				slope_target_elevation = 0.0
				slope_sprite_target_rotation = 0.0
				
				# Reset flags
				was_on_slope = false
				is_on_slope = false
			else:
				# Completely off slope - ensure neutral position
				slope_target_elevation = 0.0
				slope_sprite_target_rotation = 0.0
				is_on_slope = false
			
			if animated_sprite:
				animated_sprite.speed_scale = 1.0
				base_animation_speed = 1.0
		
		# Apply speed multiplier and move (ALWAYS, not just off-slope)
		velocity *= current_speed_mult
		move_and_slide()
		
		# Constrain to slope centerline when on/near slopes
		if is_on_slope:
			_constrain_to_slope_path()
		
		# Play walking animation
		var current_walk_anim: String = "Walk_" + current_direction
		if animated_sprite.animation != current_walk_anim:
			animated_sprite.play(current_walk_anim)
		
		# Play footstep sound
		if footstep_sound and not footstep_sound.playing:
			footstep_sound.play()
	else:
		velocity = Vector2.ZERO
		
		# When stopped, freeze slope animation if still on slope
		# This prevents snapping when stopping on/near slope edges
		var current_tile_is_slope = _check_if_on_slope(global_position)
		if current_tile_is_slope:
			# Freeze the slope animation - don't change target values
			# Player must move in a direction that can exit the slope to continue animation
			pass  # Keep current slope_target_elevation and slope_sprite_target_rotation
		elif not current_tile_is_slope and was_on_slope:
			# Only reset the was_on_slope flag, keep visual offset
			was_on_slope = false
		
		# Play idle animation
		if not animated_sprite.animation.begins_with("Idle_"):
			animated_sprite.play("Idle_" + current_direction)

func _cancel_blocked_tile_move() -> void:
	is_moving = false
	move_stuck_timer = 0.0
	velocity = Vector2.ZERO
	# Note: Removed position snapping to let camera follow smoothly
	target_pos = global_position

func attack() -> void:
	is_attacking = true
	attack_cooldown = attack_cooldown_time

	if sword_swing_sound:
		sword_swing_sound.play()

	# Freeze movement during attack
	is_moving = false
	velocity = Vector2.ZERO

	var attack_anim := "Attack_" + current_direction

	# If an attack animation exists, play it and use its duration to time the hitbox
	if animated_sprite.sprite_frames.has_animation(attack_anim):
		# Ensure non-looping
		animated_sprite.sprite_frames.set_animation_loop(attack_anim, false)
		animated_sprite.play(attack_anim)

		# Delay hitbox activation to match visual swing (wait for wind-up frames)
		# Start hitbox at 30% through animation (after wind-up)
		var anim_length = _get_animation_length(attack_anim)
		var windup_delay = anim_length * 0.3
		var active_window = anim_length * 0.4  # 40% of animation is active hitbox
		
		await get_tree().create_timer(windup_delay).timeout
		
		if hitbox:
			hitbox.start_attack(current_direction)

		# Active attack window
		await get_tree().create_timer(active_window).timeout

		# Disable hitbox after active window
		if hitbox and hitbox.has_method("stop_attack"):
			hitbox.stop_attack()

		is_attacking = false
		# Animation continues playing, but player can move again
		return

	# Fallback: if no animation, use short timed window
	if not hitbox:
		is_attacking = false
		return

	if hitbox and hitbox.has_method("start_attack"):
		hitbox.start_attack(current_direction)

	var window_time: float = 0.2
	await get_tree().create_timer(window_time).timeout

	if hitbox and hitbox.has_method("stop_attack"):
		hitbox.stop_attack()

	is_attacking = false

# Helper to get animation length in seconds
func _get_animation_length(anim_name: String) -> float:
	if not animated_sprite or not animated_sprite.sprite_frames:
		return 0.0
	if not animated_sprite.sprite_frames.has_animation(anim_name):
		return 0.0
	var frame_count = animated_sprite.sprite_frames.get_frame_count(anim_name)
	var fps = animated_sprite.sprite_frames.get_animation_speed(anim_name)
	if fps <= 0:
		return 0.0
	return float(frame_count) / fps


func take_damage(knockback_direction: Vector2 = Vector2.ZERO, damage: float = 20.0, is_critical: bool = false) -> void:
	# Prevent taking damage if already dead
	if is_dead:
		return
	
	# Prevent taking damage during invincibility frames
	if is_invincible:
		return
	
	health -= int(damage)
	health = max(health, 0)  # Clamp to 0
	
	# Cancel healing channel if hit
	is_channeling = false
	channel_timer = 0.0
	
	health_changed.emit(health, max_health)  # Signal health change
	
	# Play damage sound (crit sound if critical hit)
	if is_critical and crit_sound:
		crit_sound.play()
	elif damage_sound:
		damage_sound.play()
	
	# Blink effect when damaged
	if animated_sprite:
		# Red tint for critical, lighter for normal damage
		var damage_color = Color(1, 0.3, 0.3, 1) if is_critical else Color(1, 0.5, 0.5, 1)
		animated_sprite.modulate = damage_color
		await get_tree().create_timer(BLINK_DURATION).timeout
		if not is_dead:
			animated_sprite.modulate = Color(1, 1, 1, 1)  # Back to normal
	
	# Always apply knockback - use provided direction or fallback to random
	var kb_dir: Vector2 = knockback_direction
	if kb_dir.length() < 0.1:
		# Use a random direction as fallback
		kb_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()

	# Quantize knockback to nearest isometric straight line (NE, SE, SW, NW)
	var directions = [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]
	var best_dir = directions[0]
	var best_dot = -INF
	for dir in directions:
		var dot = kb_dir.normalized().dot(dir.normalized())
		if dot > best_dot:
			best_dot = dot
			best_dir = dir
	kb_dir = best_dir.normalized()

	is_knockback = true
	is_moving = false
	knockback_velocity = kb_dir * KNOCKBACK_STRENGTH
	velocity = Vector2.ZERO
	
	is_stunned = true
	stun_timer = 0.25
	is_moving = false
	target_pos = global_position
	
	# Grant invincibility frames
	is_invincible = true
	invincibility_timer = INVINCIBILITY_TIME
	
	# Trigger camera shake
	camera_shake_strength = CAMERA_SHAKE_BASE
	
	if health <= 0:
		is_dead = true
		died.emit()  # Signal that player died
		
		# Stop all movement
		is_knockback = false
		is_moving = false
		velocity = Vector2.ZERO
		knockback_velocity = Vector2.ZERO
		
		# Play death animation and pause on last frame
		if animated_sprite.sprite_frames.has_animation("Death"):
			animated_sprite.play("Death")
			# Set to not loop so it stays on last frame
			animated_sprite.sprite_frames.set_animation_loop("Death", false)
			await animated_sprite.animation_finished
			# Keep it on the last frame
			animated_sprite.stop()
			animated_sprite.frame = animated_sprite.sprite_frames.get_frame_count("Death") - 1
		else:
			# Fallback if Death animation doesn't exist
			await get_tree().create_timer(0.5).timeout

		# Brief hold after death animation (without pausing SceneTree)
		await get_tree().create_timer(0.6).timeout

		# Fade out transition before switching to GAMEOVER scene
		var canvas_layer = CanvasLayer.new()
		canvas_layer.layer = 100
		canvas_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		var root_node = get_tree().get_root() if get_tree() else null
		if root_node:
			if canvas_layer.get_parent():
				canvas_layer.get_parent().remove_child(canvas_layer)
			root_node.add_child(canvas_layer)
		else:
			add_child(canvas_layer)

		var fade = ColorRect.new()
		fade.color = Color(0, 0, 0, 0)
		fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fade.process_mode = Node.PROCESS_MODE_ALWAYS
		canvas_layer.add_child(fade)

		var fade_tween := get_tree().create_tween()
		fade_tween.tween_property(fade, "color:a", 1.0, 1.0)
		await fade_tween.finished

		# Switch to Game Over scene
		_change_to_game_over_scene()
		return

func _change_to_game_over_scene() -> void:
	for scene_path in GAME_OVER_SCENE_CANDIDATES:
		if ResourceLoader.exists(scene_path):
			get_tree().change_scene_to_file(scene_path)
			return
	push_error("No Game Over scene found. Checked: %s" % str(GAME_OVER_SCENE_CANDIDATES))

func spawn_damage_text(_damage: float, _is_critical: bool, _hit_pos: Vector2) -> void:
	"""Spawn floating damage text at specified position"""
	if is_dead:
		return
	var damage_text = DAMAGE_TEXT_SCENE.instantiate()
	# Place the damage text very close to the hit position with minimal jitter
	var jitter := Vector2(randf_range(-2, 2), randf_range(-1, 1))
	damage_text.global_position = _hit_pos + Vector2(0, -2) + jitter

	# Slight variation in size to give a subtle, smaller appearance
	damage_text.scale = Vector2.ONE * randf_range(0.75, 0.95)
	var root_node = get_tree().get_root() if get_tree() else null
	if root_node:
		root_node.add_child(damage_text)
	else:
		add_child(damage_text)
	damage_text.setup(_damage, _is_critical)

func trigger_camera_shake(strength: float) -> void:
	# Increase camera shake strength if requested; player camera logic will decay it
	camera_shake_strength = max(camera_shake_strength, strength)

func _snap_to_nearest_tile(pos: Vector2) -> Vector2:
	# Prefer TileMap conversion so snapping follows the actual map origin/layout.
	if terrain_0 and terrain_0.has_method("get_tile_coords") and terrain_0.has_method("get_world_pos"):
		var coords: Vector2i = terrain_0.get_tile_coords(pos)
		return terrain_0.get_world_pos(coords)
	# Fallback to step-based rounding when terrain is unavailable.
	var step = _get_move_step()
	var tile_x = round(pos.x / step.x) * step.x
	var tile_y = round(pos.y / step.y) * step.y
	return Vector2(tile_x, tile_y)

func _apply_spawn_reveal() -> void:
	spawn_reveal_active = true
	is_stunned = true  # Prevent movement during reveal

	# --- Player burning reveal as before ---
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
	
	animated_sprite.material = shader_material
	
	# Animate fire reveal (3.5 seconds - reverse from 1.0 to 0.0)
	var tween = create_tween()
	tween.tween_method(func(value): 
		shader_material.set_shader_parameter("time", value)
	, 1.0, 0.0, 3.5)
	await tween.finished
	
	# Remove shader
	animated_sprite.material = null
	
	spawn_reveal_active = false
	is_stunned = false  # Allow movement

# All tile checking logic moved to terrain_0.gd

func _update_elevation_layer() -> void:
	"""Check which terrain layer player is on and update elevation"""
	var player_pos = global_position
	
	# Slope tile is only a transition bridge; don't snap elevation while on it.
	if terrain_0:
		var tile_coords = terrain_0.get_tile_coords(player_pos)
		if _is_slope_tile(tile_coords):
			return
	
	# Check from highest to lowest
	if terrain_2 and terrain_2.has_tile_at(player_pos):
		if current_terrain != terrain_2:
			current_terrain = terrain_2
			elevation = 2.0
	elif terrain_1 and terrain_1.has_tile_at(player_pos):
		if current_terrain != terrain_1:
			current_terrain = terrain_1
			elevation = 1.0
	elif terrain_0 and terrain_0.has_tile_at(player_pos):
		if current_terrain != terrain_0:
			current_terrain = terrain_0
			elevation = 0.0
	
	# Track if we changed elevation
	# (elevation change tracking available for future use)

func _get_move_step() -> Vector2:
	if current_terrain and current_terrain.has_method("get_move_step"):
		return current_terrain.get_move_step()
	elif terrain_0 and terrain_0.has_method("get_move_step"):
		return terrain_0.get_move_step()
	# Safe isometric default when no tilemap is found
	return Vector2(8, 4)

func _can_step_to_position(next_pos: Vector2) -> bool:
	# If terrain layers are unavailable, keep existing movement behavior.
	if not terrain_0:
		return true
	if not terrain_0.has_method("get_tile_coords") or not terrain_0.has_method("get_world_pos"):
		return true

	var current_tile: Vector2i = terrain_0.get_tile_coords(global_position)
	var next_tile: Vector2i = terrain_0.get_tile_coords(next_pos)

	# Continuous movement within the same tile should never be blocked here.
	if current_tile == next_tile:
		return true

	var from_layer: TileMapLayer = _get_top_terrain_at_tile(current_tile)
	var to_layer: TileMapLayer = _get_top_terrain_at_tile(next_tile)

	# No destination tile means out-of-bounds/void; let collision + boundaries handle this.
	if not to_layer:
		return false
	if not from_layer or from_layer == to_layer:
		return true

	var from_elevation: float = _get_terrain_elevation(from_layer)
	var to_elevation: float = _get_terrain_elevation(to_layer)
	var elevation_delta: float = to_elevation - from_elevation

	if abs(elevation_delta) > max_elevation_step:
		return false

	# Going up requires destination tile to be marked as an elevation transition.
	if elevation_delta > 0.0:
		return _tile_is_elevation_transition(to_layer, next_tile)

	# Going down requires the current tile (or destination tile) to be marked.
	if elevation_delta < 0.0:
		return _tile_is_elevation_transition(from_layer, current_tile) or _tile_is_elevation_transition(to_layer, next_tile)

	return true

func _get_top_terrain_at_tile(tile_coords: Vector2i) -> TileMapLayer:
	var sample_world_pos: Vector2 = terrain_0.get_world_pos(tile_coords)
	if terrain_2 and terrain_2.has_tile_at(sample_world_pos):
		return terrain_2
	if terrain_1 and terrain_1.has_tile_at(sample_world_pos):
		return terrain_1
	if terrain_0 and terrain_0.has_tile_at(sample_world_pos):
		return terrain_0
	return null

func _get_terrain_elevation(layer: TileMapLayer) -> float:
	if layer == terrain_2:
		return 2.0
	if layer == terrain_1:
		return 1.0
	return 0.0

func _tile_is_elevation_transition(layer: TileMapLayer, tile_coords: Vector2i) -> bool:
	if not layer:
		return false
	var tile_data := layer.get_cell_tile_data(tile_coords)
	if not tile_data:
		return false

	# Check for custom data layer "Elevation Tile"
	# Custom data is accessed by the layer name you defined in the TileSet editor
	if tile_data.get_custom_data("Elevation Tile"):
		return true
	return false

func _is_slope_tile(tile_coords: Vector2i) -> bool:
	for terrain in [terrain_0, terrain_1, terrain_2]:
		if terrain and _tile_is_elevation_transition(terrain, tile_coords):
			return true
	return false

func _check_if_on_slope(world_pos: Vector2) -> bool:
	"""Check if player is currently on a slope/elevation transition tile"""
	if not terrain_0:
		return false
	
	var tile_coords = terrain_0.get_tile_coords(world_pos)
	return _is_slope_tile(tile_coords)

func _direction_from_vector(dir: Vector2) -> String:
	if dir.x > 0 and dir.y > 0:
		return "SE"
	if dir.x < 0 and dir.y < 0:
		return "NW"
	if dir.x < 0 and dir.y > 0:
		return "SW"
	return "NE"

func _direction_string_to_vector(dir_name: String) -> Vector2:
	match dir_name.strip_edges().to_upper():
		"NE":
			return Vector2(1, -1).normalized()
		"NW":
			return Vector2(-1, -1).normalized()
		"SE":
			return Vector2(1, 1).normalized()
		"SW":
			return Vector2(-1, 1).normalized()
		_:
			return Vector2.ZERO

func _vector_to_tile_offset(dir: Vector2) -> Vector2i:
	if dir == Vector2.ZERO:
		return Vector2i.ZERO
	return Vector2i(1 if dir.x >= 0.0 else -1, 1 if dir.y >= 0.0 else -1)

func _get_tile_elevation(tile_coords: Vector2i) -> float:
	var layer: TileMapLayer = _get_top_terrain_at_tile(tile_coords)
	if not layer:
		return elevation
	return _get_terrain_elevation(layer)

func _get_slope_up_direction(_tile_coords: Vector2i, fallback_dir: Vector2) -> Vector2:
	# Slope direction is determined by movement direction, not tile data
	return fallback_dir.normalized() if fallback_dir != Vector2.ZERO else Vector2.ZERO

func _lock_slope_input(input_dir: Vector2) -> Vector2:
	if input_dir == Vector2.ZERO or not terrain_0:
		return input_dir
	
	var tile_coords: Vector2i = terrain_0.get_tile_coords(global_position)
	var probe_tile: Vector2i = terrain_0.get_tile_coords(global_position + input_dir * _get_move_step().length())
	var slope_tile: Vector2i = tile_coords
	if _is_slope_tile(tile_coords):
		slope_tile = tile_coords
	elif _is_slope_tile(probe_tile):
		slope_tile = probe_tile
	else:
		return input_dir
	
	var lock_dir: Vector2 = slope_up_dir
	if lock_dir == Vector2.ZERO:
		lock_dir = _get_slope_up_direction(slope_tile, input_dir)
	if lock_dir == Vector2.ZERO:
		return input_dir
	
	var forward_dot: float = input_dir.dot(lock_dir)
	var alignment: float = absf(forward_dot)
	if alignment < SLOPE_INPUT_LOCK_DOT:
		return Vector2.ZERO
	return lock_dir if forward_dot >= 0.0 else -lock_dir

func _constrain_to_slope_path() -> void:
	"""Project player to slope centerline to avoid side drift/flinging."""
	if not terrain_0:
		return
	
	var current_tile: Vector2i = terrain_0.get_tile_coords(global_position)
	var target_tile: Vector2i = current_tile
	var vel_dir: Vector2 = velocity.normalized() if velocity.length() > 0.01 else Vector2.ZERO
	
	if _is_slope_tile(current_tile):
		target_tile = current_tile
	elif vel_dir != Vector2.ZERO:
		var forward_tile: Vector2i = terrain_0.get_tile_coords(global_position + vel_dir * _get_move_step().length())
		if _is_slope_tile(forward_tile):
			target_tile = forward_tile
		else:
			return
	else:
		return
	
	var axis: Vector2 = _get_slope_up_direction(target_tile, vel_dir if vel_dir != Vector2.ZERO else slope_up_dir)
	if axis == Vector2.ZERO:
		return
	axis = axis.normalized()
	
	var center: Vector2 = terrain_0.get_world_pos(target_tile)
	var rel: Vector2 = global_position - center
	var along: float = rel.dot(axis)
	var _path_point: Vector2 = center + axis * along
	
	# Note: Removed direct position modification to prevent camera jumps
	# The slope constraint is now purely visual through sprite offset

func _custom_data_as_bool(value: Variant) -> bool:
	match typeof(value):
		TYPE_BOOL:
			return value
		TYPE_INT, TYPE_FLOAT:
			return value > 0
		TYPE_STRING:
			var normalized: String = String(value).strip_edges().to_lower()
			return normalized == "true" or normalized == "1" or normalized == "yes" or normalized == "up"
		_:
			return false

func _animate_elevation_change(_from_elevation: float, _to_elevation: float) -> void:
	pass

func _trigger_slope_camera() -> void:
	pass
