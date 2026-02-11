extends CharacterBody2D

# Use centralized config
const DAMAGE_TEXT_SCENE = preload("res://DamageText.tscn")

# Y-sort for isometric depth
const USE_Y_SORT: bool = true

@export var move_speed: float = 55.0
@export var attack_cooldown_time: float = 1.0
@export var health: int = 30  # 4 hit points * 8 health each
@export var max_health: int = 30
@export var elevation: float = 0.0  # Current elevation level (0 = ground, 1 = platform, etc.)
@export var max_elevation_step: float = 1.0  # Maximum elevation difference player can climb
@export var fall_damage_threshold: float = 2.0  # Elevation difference that causes fall damage

# Signals for better event handling
signal health_changed(new_health: int, max_health: int)
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

# Terrain reference (ground level)
var terrain_0: TileMapLayer = null

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
@export var camera_smoothing_speed: float = 6.0
@export var camera_lookahead: float = 12.0
@export var camera_max_lookahead_speed: float = 200.0
var current_crit_chance: float = 0.05  # Current crit chance (starts at 5%)
var crit_boost_timer: float = 0.0  # Timer to track time since last hit
var combo_count: int = 0  # Number of consecutive hits in combo
var has_hit_enemy: bool = false  # Track if we're in a combo
var spawn_reveal_active: bool = false  # Track if spawn reveal is happening

const KNOCKBACK_FRICTION: float = 500.0
const KNOCKBACK_STRENGTH: float = 120.0
const INVINCIBILITY_TIME: float = 1.0
const BLINK_DURATION: float = 0.02
const CAMERA_SHAKE_BASE: float = 3.0

func _ready() -> void:
	add_to_group("player")
	target_pos = global_position
	previous_pos = global_position
	animated_sprite.play("Idle_" + current_direction)
	
	# Find terrain ground level
	var parent = get_parent()
	if parent:
		terrain_0 = parent.get_node_or_null("Terrain 0")
	
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
	if crit_sound:
		crit_sound.volume_db = 2.0

	# Enforce hit and sword swing volumes in case the nodes were present already
	if sword_swing_sound:
		sword_swing_sound.volume_db = -6.0
	if attack_voice_sound:
		attack_voice_sound.volume_db = -10.0

	# Lower crit sound volume to prevent it being too loud
	if crit_sound:
		crit_sound.volume_db = -6.0

	health_changed.emit(health, max_health)

func _physics_process(delta: float) -> void:
	# Update z-index for proper depth sorting in isometric view
	# Use Y position of sprite bottom (feet) for sorting, minus elevation for 3D effect
	# Add base offset to ensure player renders above ground tiles (which have z_index = 1)
	z_index = 1000 + int(global_position.y + 4 - elevation)
	
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
		# Activate this camera node using the API-safe method
		if not camera.is_current():
			camera.make_current()
		# Calculate lookahead in movement direction so camera leads the player
		var look := Vector2.ZERO
		if velocity.length() > 1.0:
			look = velocity.normalized() * camera_lookahead * min(velocity.length() / camera_max_lookahead_speed, 1.0)
		var target_cam_pos := global_position + look
		# Smoothly interpolate camera position toward target (leading the player)
		camera.global_position = camera.global_position.lerp(target_cam_pos, clamp(camera_smoothing_speed * delta, 0.0, 1.0))
		# Apply shake offset on top of follow
		camera.offset = shake_offset
	
	# Don't process if dead
	if is_dead:
		return
	
	# Handle knockback
	if is_knockback:
		velocity = knockback_velocity
		move_and_slide()
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_FRICTION * delta)
		
		if knockback_velocity.length() < 1.0:
			is_knockback = false
			knockback_velocity = Vector2.ZERO
			velocity = Vector2.ZERO
			# Snap to nearest tile to maintain grid alignment
			var nearest_tile = _snap_to_nearest_tile(global_position)
			global_position = nearest_tile
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
	
	# Tile-based movement - tap moves one tile, hold keeps moving
	# Only pick next tile if not currently moving
	if not is_moving:
		var move_offset = Vector2.ZERO
		
		# Check for individual key presses (priority: W > A > S > D)
		# Holding key will keep moving tile by tile
		var step = _get_move_step()
		if Input.is_key_pressed(KEY_W):
			move_offset = Vector2(step.x, -step.y)  # NE
			current_direction = "NE"
		elif Input.is_key_pressed(KEY_A):
			move_offset = Vector2(-step.x, -step.y)  # NW
			current_direction = "NW"
		elif Input.is_key_pressed(KEY_S):
			move_offset = Vector2(-step.x, step.y)  # SW
			current_direction = "SW"
		elif Input.is_key_pressed(KEY_D):
			move_offset = Vector2(step.x, step.y)  # SE
			current_direction = "SE"
		
		# Start movement to target tile if input detected
		if move_offset != Vector2.ZERO:
			target_pos = global_position + move_offset
			
			# Check if terrain_0 allows movement to this position
			if terrain_0 and terrain_0.can_move_to(target_pos):
				# Start smooth movement to target
				is_moving = true
				previous_pos = global_position
				
				# Only start walking animation if not already walking in this direction
				var walk_anim = "Walk_" + current_direction
				if animated_sprite.animation != walk_anim:
					animated_sprite.play(walk_anim)
				
				# Play footstep sound
				if footstep_sound and not footstep_sound.playing:
					footstep_sound.play()
	
	# Handle smooth interpolation during tile movement
	if is_moving:
		var distance_to_target = global_position.distance_to(target_pos)
		
		if distance_to_target < 0.5:
			# Snap to target when close enough
			global_position = target_pos
			is_moving = false
			velocity = Vector2.ZERO
			
			# Only play idle if no movement keys are pressed
			if not Input.is_key_pressed(KEY_W) and not Input.is_key_pressed(KEY_A) and not Input.is_key_pressed(KEY_S) and not Input.is_key_pressed(KEY_D):
				animated_sprite.play("Idle_" + current_direction)
		else:
			# Smoothly move toward target
			var direction = (target_pos - global_position).normalized()
			velocity = direction * move_speed
			move_and_slide()
	else:
		velocity = Vector2.ZERO
		
		# Play idle animation if not already playing and no movement keys pressed
		if not animated_sprite.animation.begins_with("Idle_"):
			if not Input.is_key_pressed(KEY_W) and not Input.is_key_pressed(KEY_A) and not Input.is_key_pressed(KEY_S) and not Input.is_key_pressed(KEY_D):
				animated_sprite.play("Idle_" + current_direction)

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

		# Freeze the game for 1 second after death animation
		get_tree().paused = true
		await get_tree().create_timer(1.0).timeout
		get_tree().paused = false

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

		var fade_time = 0.0
		var fade_duration = 1.0
		while fade_time < fade_duration:
			await get_tree().process_frame
			fade_time += get_process_delta_time()
			var alpha = min(fade_time / fade_duration, 1.0)
			fade.color.a = alpha

		# Switch to GAMEOVER scene
		get_tree().change_scene_to_file("res://gameover.tscn")
		return

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
	# Snap a world position to the nearest tile center
	# Calculate which tile this position is closest to
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

func _get_move_step() -> Vector2:
	if terrain_0 and terrain_0.has_method("get_move_step"):
		return terrain_0.get_move_step()
	return Vector2(8, 16)
