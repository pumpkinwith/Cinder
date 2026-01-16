extends CharacterBody2D

# Use centralized config
const TILE_SIZE: Vector2 = Vector2(8, 4)
const PARTICLE_SCENE = preload("res://Particles.tscn")
const DAMAGE_TEXT_SCENE = preload("res://DamageText.tscn")

# Y-sort for isometric depth
const USE_Y_SORT: bool = true

@export var move_speed: float = 55.0
@export var attack_cooldown_time: float = 0.5
@export var health: int = 32  # 4 hit points * 8 health each
@export var max_health: int = 32
@export var base_damage: int = 10  # Level 1 dagger damage
@export var base_crit_chance: float = 0.05  # 5% base critical hit chance
@export var combo_crit_increase: float = 0.01  # 1% increase per combo hit
@export var max_crit_chance: float = 0.40  # 40% maximum crit chance
@export var crit_reset_time: float = 1.0  # Reset combo after 1 second of no attacks

# Signals for better event handling
signal health_changed(new_health: int, max_health: int)
signal died
signal attacked

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_area: Area2D = $Attack if has_node("Attack") else null
@onready var hitbox: Area2D = $"Hit Box" if has_node("Hit Box") else null
@onready var camera: Camera2D = $Camera2D if has_node("Camera2D") else null
@onready var footstep_sound: AudioStreamPlayer = $FootstepSound if has_node("FootstepSound") else null
@onready var sword_swing_sound: AudioStreamPlayer = $SwordSwingSound if has_node("SwordSwingSound") else null
@onready var attack_voice_sound: AudioStreamPlayer = $AttackVoiceSound if has_node("AttackVoiceSound") else null
@onready var crit_sound: AudioStreamPlayer = $CritSound if has_node("CritSound") else null
@onready var damage_sound: AudioStreamPlayer = $DamageSound if has_node("DamageSound") else null

var torch_light: PointLight2D

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
var current_crit_chance: float = 0.05  # Current crit chance (starts at 5%)
var crit_boost_timer: float = 0.0  # Timer to track time since last hit
var combo_count: int = 0  # Number of consecutive hits in combo
var has_hit_enemy: bool = false  # Track if we're in a combo
var spawn_reveal_active: bool = false  # Track if spawn reveal is happening

const KNOCKBACK_FRICTION: float = 500.0
const INVINCIBILITY_TIME: float = 1.0

func _ready() -> void:
	add_to_group("player")
	target_pos = global_position
	previous_pos = global_position
	animated_sprite.play("Idle_" + current_direction)
	
	# Create torch light
	_setup_torch_light()
	
	# Apply fire reveal effect on spawn
	_apply_spawn_reveal()
	
	# Setup camera if it doesn't exist
	if not camera:
		camera = Camera2D.new()
		add_child(camera)
	
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 5.0
	
	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)
	
	# Connect animation finished signal
	animated_sprite.animation_finished.connect(_on_animation_finished)
	
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
		attack_voice_sound.volume_db = -15.0
		add_child(attack_voice_sound)
	
	if not crit_sound:
		crit_sound = AudioStreamPlayer.new()
		crit_sound.name = "CritSound"
		crit_sound.stream = load("res://Sound/Effect/OW.mp3")
		crit_sound.volume_db = -3.0
		add_child(crit_sound)
	
	if not damage_sound:
		damage_sound = AudioStreamPlayer.new()
		damage_sound.name = "DamageSound"
		damage_sound.stream = load("res://Sound/Effect/OW.mp3")
		damage_sound.volume_db = 0.0
		add_child(damage_sound)
	
	# Emit initial health
	health_changed.emit(health, max_health)

func add_shadow() -> void:
	pass  # Shadow code removed

func _process(_delta: float) -> void:
	pass  # Shadow update code removed

func _physics_process(delta: float) -> void:
	# Update z-index for proper depth sorting in isometric view
	# Use Y position of sprite bottom (feet) for sorting
	# Add base offset to ensure player renders above ground tiles (which have z_index = 1)
	z_index = 1000 + int(global_position.y + 4)
	
	# Handle attack cooldown
	if attack_cooldown > 0:
		attack_cooldown -= delta
	
	# Handle critical hit chance boost timer
	if has_hit_enemy:
		crit_boost_timer += delta
		if crit_boost_timer >= crit_reset_time:
			# Reset combo and crit chance after 1 second of no attacks
			combo_count = 0
			current_crit_chance = base_crit_chance
			has_hit_enemy = false
			crit_boost_timer = 0.0
	
	# Handle invincibility timer
	if is_invincible:
		invincibility_timer -= delta
		if invincibility_timer <= 0:
			is_invincible = false
	
	# Handle camera shake
	if camera_shake_strength > 0:
		camera_shake_strength = max(camera_shake_strength - camera_shake_decay * delta, 0.0)
		if camera:
			camera.offset = Vector2(
				randf_range(-camera_shake_strength, camera_shake_strength),
				randf_range(-camera_shake_strength, camera_shake_strength)
			)
	else:
		if camera:
			camera.offset = Vector2.ZERO
	
	# Torch flickering effect
	if torch_light:
		var flicker_time = torch_light.get_meta("flicker_time", 0.0)
		flicker_time += delta * 8.0  # Flicker speed
		torch_light.set_meta("flicker_time", flicker_time)
		
		# Subtle energy variation for torch flicker
		var flicker_offset = sin(flicker_time) * 0.1 + sin(flicker_time * 2.3) * 0.05
		torch_light.energy = 1.5 + flicker_offset
	
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
			# Snap to nearest tile after knockback
			global_position = (global_position / TILE_SIZE).round() * TILE_SIZE
			return
	
	# Handle stun timer
	if is_stunned:
		stun_timer -= delta
		
		# End stun
		if stun_timer <= 0:
			is_stunned = false
		return
	
	# If moving, interpolate smoothly to target
	if is_moving:
		# Check attack input even while moving
		if Input.is_action_just_pressed("Attack") and attack_cooldown <= 0 and not is_attacking:
			attack()
			# Don't return, continue moving
		
		var direction = (target_pos - global_position).normalized()
		velocity = direction * move_speed
		move_and_slide()
		
		# If blocked by barrier, stop immediately and snap to tile
		if get_slide_collision_count() > 0:
			velocity = Vector2.ZERO
			is_moving = false
			global_position = (global_position / TILE_SIZE).round() * TILE_SIZE
			return
		
		# Always stay on track to target tile
		if global_position.distance_to(target_pos) < 0.5:
			# Ensure we land exactly on the target tile
			global_position = target_pos
			velocity = Vector2.ZERO
			is_moving = false
		return
	
	# Check input only when not moving and not attacking
	if is_attacking:
		# Manually check if attack animation should end
		if animated_sprite.animation.begins_with("Attack_"):
			var anim_name = animated_sprite.animation
			var frame_count = animated_sprite.sprite_frames.get_frame_count(anim_name)
			var current_frame = animated_sprite.frame
			# If on last frame, end attack
			if current_frame >= frame_count - 1:
				is_attacking = false
				animated_sprite.play("Idle_" + current_direction)
		return
	
	var move_offset: Vector2 = Vector2.ZERO
	var new_direction: String = ""
	
	# Check attack input
	if Input.is_action_just_pressed("Attack") and attack_cooldown <= 0:
		attack()
		return
	
	if Input.is_physical_key_pressed(KEY_W):
		move_offset = Vector2(TILE_SIZE.x, -TILE_SIZE.y)
		new_direction = "NE"
	elif Input.is_physical_key_pressed(KEY_S):
		move_offset = Vector2(-TILE_SIZE.x, TILE_SIZE.y)
		new_direction = "SW"
	elif Input.is_physical_key_pressed(KEY_A):
		move_offset = Vector2(-TILE_SIZE.x, -TILE_SIZE.y)
		new_direction = "NW"
	elif Input.is_physical_key_pressed(KEY_D):
		move_offset = Vector2(TILE_SIZE.x, TILE_SIZE.y)
		new_direction = "SE"
	
	# Start movement
	if move_offset != Vector2.ZERO:
		previous_pos = global_position
		var next_pos = global_position + move_offset
		
		# Check if tile is occupied by an enemy
		var tile_occupied = false
		for enemy in get_tree().get_nodes_in_group("enemy"):
			if enemy.global_position.distance_to(next_pos) < 2:
				tile_occupied = true
				break
		
		if not tile_occupied:
			var direction_changed = (new_direction != current_direction)
			current_direction = new_direction
			target_pos = next_pos
			is_moving = true
			
			# Play footstep sound when starting movement
			if footstep_sound and not footstep_sound.playing:
				footstep_sound.play()
			
			if direction_changed or not animated_sprite.animation.begins_with("Walk_"):
				animated_sprite.play("Walk_" + current_direction)
	else:
		# No input - play idle if not already
		if not animated_sprite.animation.begins_with("Idle_"):
			animated_sprite.play("Idle_" + current_direction)

func attack() -> void:
	is_attacking = true
	attack_cooldown = attack_cooldown_time
	
	# Play sword swing sound always
	if sword_swing_sound:
		sword_swing_sound.play()
	
	# Play attack animation based on direction (set to not loop)
	var attack_anim = "Attack_" + current_direction
	if animated_sprite.sprite_frames.has_animation(attack_anim):
		# Force animation to not loop
		animated_sprite.sprite_frames.set_animation_loop(attack_anim, false)
		animated_sprite.play(attack_anim)
	else:
		is_attacking = false
		return
	
	if not attack_area:
		is_attacking = false
		return
	
	# Get attack offset for knockback direction
	var attack_offset: Vector2 = Vector2.ZERO
	if current_direction == "NE":
		attack_offset = Vector2(TILE_SIZE.x, -TILE_SIZE.y)
	elif current_direction == "SE":
		attack_offset = Vector2(TILE_SIZE.x, TILE_SIZE.y)
	elif current_direction == "SW":
		attack_offset = Vector2(-TILE_SIZE.x, TILE_SIZE.y)
	elif current_direction == "NW":
		attack_offset = Vector2(-TILE_SIZE.x, -TILE_SIZE.y)
	
	# Check for enemies in attack area
	var enemies_in_range = attack_area.get_overlapping_bodies()
	var hit_count = 0
	for body in enemies_in_range:
		if body.is_in_group("enemy") and body.has_method("take_damage"):
			# Check if enemy is in the direction player is facing
			var to_enemy = (body.global_position - global_position).normalized()
			var attack_direction = attack_offset.normalized()
			
			# Narrower attack cone: dot > 0.7 means ~45-50° cone
			if to_enemy.dot(attack_direction) > 0.7:
				# Play attack voice sound on hit
				if attack_voice_sound and hit_count == 0:
					attack_voice_sound.play()
				
				# Increase combo count and update crit chance
				combo_count += 1
				current_crit_chance = min(base_crit_chance + (combo_count * combo_crit_increase), max_crit_chance)
				has_hit_enemy = true
				crit_boost_timer = 0.0  # Reset timer on each hit
				
				# Calculate damage and check for critical hit
				var damage = base_damage
				var is_critical = randf() < current_crit_chance
				if is_critical:
					damage *= 2  # Critical hits deal 2x damage
					# Play critical hit sound
					if crit_sound:
						crit_sound.play()
				
				# Spawn particle effect at hit position
				var hit_pos = global_position.lerp(body.global_position, 0.5)
				spawn_hit_particle(hit_pos)
				
				# Spawn damage text at hit position
				spawn_damage_text(float(damage), is_critical, hit_pos)
				
				# Deal damage to enemy
				body.take_damage(float(damage), attack_offset.normalized(), is_critical)
				hit_count += 1
	
	if hit_count > 0:
		attacked.emit()  # Signal that we attacked
		camera_shake_strength = 1.5  # Small shake when hitting enemies
	
	# Don't set is_attacking = false here, let the animation finish handle it

func take_damage(knockback_direction: Vector2 = Vector2.ZERO, damage: float = 20.0) -> void:
	# Prevent taking damage if already dead
	if is_dead:
		return
	
	# Prevent taking damage during invincibility frames
	if is_invincible:
		return
	
	health -= int(damage)
	health = max(health, 0)  # Clamp to 0
	health_changed.emit(health, max_health)  # Signal health change
	
	# Play damage sound
	if damage_sound:
		damage_sound.play()
	
	# Blink effect when damaged
	if animated_sprite:
		animated_sprite.modulate = Color(1, 0.3, 0.3, 1)  # Red tint
		await get_tree().create_timer(0.1).timeout
		if not is_dead:
			animated_sprite.modulate = Color(1, 1, 1, 1)  # Back to normal
	
	# Always apply knockback - use provided direction or fallback to random
	var kb_dir = knockback_direction
	if kb_dir.length() < 0.1:  # If direction is too small or zero
		# Use a random direction as fallback
		kb_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
	
	is_knockback = true
	is_moving = false
	knockback_velocity = kb_dir.normalized() * 120
	velocity = Vector2.ZERO
	
	is_stunned = true
	stun_timer = 0.25
	is_moving = false
	target_pos = global_position
	
	# Grant invincibility frames
	is_invincible = true
	invincibility_timer = INVINCIBILITY_TIME
	
	# Trigger camera shake
	camera_shake_strength = 3.0
	
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
		
		# Wait before starting fade
		await get_tree().create_timer(1.0).timeout
		
		# Create fade to black (overlay layer)
		var canvas_layer = CanvasLayer.new()
		canvas_layer.layer = 50
		canvas_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		get_tree().root.add_child(canvas_layer)
		
		var fade = ColorRect.new()
		fade.color = Color(0, 0, 0, 0)
		fade.set_anchors_preset(Control.PRESET_FULL_RECT)
		fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fade.process_mode = Node.PROCESS_MODE_ALWAYS
		canvas_layer.add_child(fade)
		
		# Freeze game and start fade
		get_tree().paused = true
		
		# Manually animate fade during pause
		var fade_time = 0.0
		var fade_duration = 1.5
		while fade_time < fade_duration:
			await get_tree().process_frame
			fade_time += get_process_delta_time()
			var alpha = min(fade_time / fade_duration, 1.0) * 0.95
			fade.color.a = alpha
		
		# Transfer to gameover scene
		get_tree().paused = false
		get_tree().change_scene_to_file("res://GAMEOVER.tscn")
		
		return

func spawn_hit_particle(hit_position: Vector2) -> void:
	var particle = PARTICLE_SCENE.instantiate()
	particle.global_position = hit_position
	get_tree().root.add_child(particle)
	
	# The particle scene root IS the AnimatedSprite2D
	if particle is AnimatedSprite2D:
		if particle.sprite_frames.has_animation("Particle 1"):
			particle.sprite_frames.set_animation_loop("Particle 1", false)
		particle.play("Particle 1")
		particle.animation_finished.connect(func(): particle.queue_free())

func spawn_damage_text(_damage: float, _is_critical: bool, _hit_pos: Vector2) -> void:
	"""Spawn floating damage text at specified position"""
	var damage_text = DAMAGE_TEXT_SCENE.instantiate()
	damage_text.global_position = _hit_pos + Vector2(0, -5)  # Slightly above hit position
	get_tree().root.add_child(damage_text)
	damage_text.setup(_damage, _is_critical)

func _on_animation_finished() -> void:
	# When attack animation finishes, return to idle
	if animated_sprite.animation.begins_with("Attack_"):
		is_attacking = false
		animated_sprite.play("Idle_" + current_direction)

func _setup_torch_light() -> void:
	"""Create a warm torch light that follows the player"""
	torch_light = PointLight2D.new()
	torch_light.name = "TorchLight"
	add_child(torch_light)
	
	# Position slightly above player (torch in hand)
	torch_light.position = Vector2(0, -2)
	
	# Warm torch colors
	torch_light.color = Color(1.0, 0.8, 0.5, 1.0)  # Warm orange-yellow
	torch_light.energy = 1.5
	torch_light.blend_mode = Light2D.BLEND_MODE_ADD
	
	# Set light radius
	torch_light.texture_scale = 2.0
	
	# Add flickering effect for realism
	torch_light.set_meta("flicker_time", 0.0)

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
	
	# Wait for black background to finish fading out (0.8s fade + small buffer)
	await get_tree().create_timer(1.0).timeout
	
	spawn_reveal_active = false
	is_stunned = false  # Allow movement

func _on_hitbox_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemy"):
		# Enemy will handle the damage through their attack system
		pass
