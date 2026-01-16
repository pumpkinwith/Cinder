extends CharacterBody2D

## Ted - Enemy AI Controller
## Handles chase behavior, pathfinding, and combat

# State machine for cleaner logic
enum STATE { IDLE, CHASE, ATTACK, STUNNED, DEAD }

# Signals for events
signal health_changed(new_health: int, max_health: int)
signal died
signal lost_player

const TILE_SIZE: Vector2 = Vector2(8, 4)
const PARTICLE_SCENE = preload("res://Particles.tscn")
const DAMAGE_TEXT_SCENE = preload("res://DamageText.tscn")

# Y-sort for isometric depth
const USE_Y_SORT: bool = true

@export var move_speed: float = 35
@export var detection_range: float = 75
@export var health: int = 40
@export var max_health: int = 40
@export var respawn_enabled: bool = true
@export var enemy_damage: float = 10.0  # Ted deals 15 damage
@export var enemy_crit_chance: float = 0.10  # 10% chance for critical hits

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D if has_node("AnimatedSprite2D") else null
@onready var attack_area: Area2D = $Attack if has_node("Attack") else null

var state: STATE = STATE.IDLE
var player: CharacterBody2D
var current_direction: String = "SE"
var attack_cooldown: float = 0.25
var can_attack: bool = true
var is_knockback: bool = false
var knockback_velocity: Vector2 = Vector2.ZERO
var is_dead: bool = false
var respawn_timer: float = 0.0
var is_moving: bool = false
var target_pos: Vector2 = Vector2.ZERO
var previous_pos: Vector2 = Vector2.ZERO
var move_timer: float = 0.0
var player_detected: bool = false
var player_lost_timer: float = 0.0

const KNOCKBACK_FRICTION: float = 400.0
const RESPAWN_DELAY: float = 2.0
const MOVE_INTERVAL: float = 0.05  # Time between tile movements (smaller = smoother)
const PLAYER_LOST_TIME: float = 2.0  # Time to forget player after losing range

func _ready() -> void:
	add_to_group("enemy")  # Keep "enemy" group for compatibility
	add_to_group("ted")     # Add Ted-specific group
	player = get_tree().get_first_node_in_group("player")
	target_pos = global_position
	previous_pos = global_position
	
	if sprite:
		sprite.play("Idle_" + current_direction)
	
	# Emit initial health
	health_changed.emit(health, max_health)

func add_shadow() -> void:
	pass  # Shadow code removed

func _process(_delta: float) -> void:
	pass  # Shadow update code removed

func _physics_process(delta: float) -> void:
	# Update z-index for proper depth sorting in isometric view
	# Use Y position of sprite bottom (feet) for sorting
	# Add base offset to ensure Ted renders above ground tiles (which have z_index = 1)
	z_index = 1000 + int(global_position.y + 4)
	
	if not player:
		return
	
	# Ensure visibility and sprite visibility when alive
	if not is_dead:
		if not visible:
			visible = true
		if sprite and not sprite.visible:
			sprite.visible = true
	
	# Handle respawn timer
	if is_dead:
		state = STATE.DEAD
		respawn_timer -= delta
		if respawn_timer <= 0 and respawn_enabled:
			_respawn()
		return
	
	# Handle knockback
	if is_knockback:
		state = STATE.STUNNED
		velocity = knockback_velocity
		move_and_slide()
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_FRICTION * delta)
		
		if knockback_velocity.length() < 1.0:
			is_knockback = false
			knockback_velocity = Vector2.ZERO
			velocity = Vector2.ZERO
			state = STATE.IDLE
			# Snap to nearest tile after knockback
			global_position = (global_position / TILE_SIZE).round() * TILE_SIZE
		return
	
	# Update attack cooldown
	if not can_attack:
		attack_cooldown -= delta
		if attack_cooldown <= 0:
			can_attack = true
	
	# Attack player if in range
	if can_attack and attack_area:
		var bodies_in_range = attack_area.get_overlapping_bodies()
		for body in bodies_in_range:
			if body.is_in_group("player") and body.has_method("take_damage") and not body.is_invincible:
				var knockback_dir = (body.global_position - global_position).normalized()
				
				# Check for critical hit
				var damage = enemy_damage
				var is_critical = randf() < enemy_crit_chance
				if is_critical:
					damage *= 2  # Critical hits deal 2x damage
				
				# Spawn particle effect at hit position
				var hit_pos = global_position.lerp(body.global_position, 0.5)
				spawn_hit_particle(hit_pos)
				
				# Spawn damage text at hit position (where player is hit)
				body.spawn_damage_text(damage, is_critical, body.global_position)
				
				# Deal damage to player
				body.take_damage(knockback_dir, damage)
				can_attack = false
				attack_cooldown = 0.5
				break
	
	# Check detection range and line-of-sight (walls on layer 1 block sight)
	var distance_to_player = global_position.distance_to(player.global_position)
	var has_line_of_sight = true
	if distance_to_player <= detection_range:
		var space_state = get_world_2d().direct_space_state
		var ray = PhysicsRayQueryParameters2D.create(global_position, player.global_position)
		ray.collision_mask = 1 | 2  # walls on layer 1, player on layer 2
		ray.collide_with_areas = false
		ray.collide_with_bodies = true
		ray.exclude = [self]
		var hit = space_state.intersect_ray(ray)
		if hit:
			if hit.collider.is_in_group("player"):
				has_line_of_sight = true
			else:
				has_line_of_sight = false

	if distance_to_player > detection_range or not has_line_of_sight:
		# Out of range or LOS blocked: immediately forget player
		player_detected = false
		lost_player.emit()  # Signal that player was lost
		state = STATE.IDLE
		if not is_moving:
			velocity = Vector2.ZERO
			if sprite:
				sprite.play("Idle_" + current_direction)
		return
	else:
		# In range and visible: chase
		player_detected = true
		player_lost_timer = PLAYER_LOST_TIME
		state = STATE.CHASE
	
	# Handle tile-based movement
	if is_moving:
		# Keep playing walking animation while moving
		if sprite and not sprite.animation.begins_with("Walking_"):
			sprite.play("Walking_" + current_direction)
		
		var direction = (target_pos - global_position).normalized()
		velocity = direction * move_speed
		move_and_slide()
		
		# If blocked by barrier, stop immediately and snap to tile
		if get_slide_collision_count() > 0:
			velocity = Vector2.ZERO
			is_moving = false
			global_position = (global_position / TILE_SIZE).round() * TILE_SIZE
			if sprite:
				sprite.play("Idle_" + current_direction)
			return
		
		# Always reach target exactly
		if global_position.distance_to(target_pos) < 0.5:
			# Ensure we land exactly on the target tile
			global_position = target_pos
			velocity = Vector2.ZERO
			is_moving = false
			# Play idle animation when movement ends
			if sprite:
				sprite.play("Idle_" + current_direction)
		return  # Don't pick new tile while still moving
	
	# Only pick new tile when not moving
	if not is_moving:
		# Pick next tile immediately (no timer delay)
		# But stop moving if already adjacent to player (let attack handle it)
		distance_to_player = global_position.distance_to(player.global_position)
		if distance_to_player < TILE_SIZE.length() + 2:
			# Adjacent to player - stop moving and let attack happen
			is_moving = false
		else:
			# Calculate direction to player
			var best_move: Vector2 = Vector2.ZERO
			var best_distance = INF  # pick the closest available, even if not strictly closer than current
			
			# Try all 4 directions
			var possible_moves = [
				Vector2(TILE_SIZE.x, TILE_SIZE.y),    # SE
				Vector2(-TILE_SIZE.x, -TILE_SIZE.y),  # NW
				Vector2(-TILE_SIZE.x, TILE_SIZE.y),   # SW
				Vector2(TILE_SIZE.x, -TILE_SIZE.y)    # NE
			]
			
			for move in possible_moves:
				var test_pos = global_position + move
				var test_distance = test_pos.distance_to(player.global_position)
				
				# Check if tile is occupied
				var occupied = false
				if player.global_position.distance_to(test_pos) < 2:
					occupied = true
				
				# Check if tile is blocked by walls/barriers (collision layer 1)
				if not occupied:
					var space_state = get_world_2d().direct_space_state
					var query = PhysicsPointQueryParameters2D.new()
					query.position = test_pos
					query.collision_mask = 1
					query.exclude = [self]
					var wall_hit = space_state.intersect_point(query)
					if wall_hit.size() > 0:
						occupied = true
				
				if not occupied:
					for other_enemy in get_tree().get_nodes_in_group("enemy"):
						if other_enemy != self and other_enemy.global_position.distance_to(test_pos) < 2:
							occupied = true
							break
				
				# Pick move that is closest to player among valid tiles
				if not occupied and test_distance < best_distance:
					best_move = move
					best_distance = test_distance
			
			if best_move != Vector2.ZERO:
				var next_pos = global_position + best_move
				
				# Pre-check: verify destination is walkable before moving
				var space_state = get_world_2d().direct_space_state
				var query = PhysicsPointQueryParameters2D.new()
				query.position = next_pos
				query.collision_mask = 1
				query.exclude = [self]
				var wall_hit = space_state.intersect_point(query)
				
				# Also verify no entities moved there since last check
				var occupied_by_entity = false
				if player and player.global_position.distance_to(next_pos) < 2:
					occupied_by_entity = true
				if not occupied_by_entity:
					for other_enemy in get_tree().get_nodes_in_group("enemy"):
						if other_enemy != self and other_enemy.global_position.distance_to(next_pos) < 2:
							occupied_by_entity = true
							break
				
				# Only move if destination is clear
				if wall_hit.size() == 0 and not occupied_by_entity:
					# Update facing direction first
					var new_direction = ""
					if best_move.x > 0 and best_move.y > 0:
						new_direction = "SE"
					elif best_move.x < 0 and best_move.y < 0:
						new_direction = "NW"
					elif best_move.x < 0 and best_move.y > 0:
						new_direction = "SW"
					else:
						new_direction = "NE"
					
					current_direction = new_direction
					
					# Set movement
					target_pos = next_pos
					previous_pos = global_position
					is_moving = true
					
					# Start walking animation
					if sprite:
						sprite.play("Walking_" + current_direction)
			else:
				# Stuck, play idle
				if sprite and not sprite.animation.begins_with("Idle_"):
					sprite.play("Idle_" + current_direction)

func take_damage(damage: float, knockback_direction: Vector2 = Vector2.ZERO, _is_critical: bool = false) -> void:
	health -= int(damage)
	health = max(health, 0)  # Clamp to 0
	health_changed.emit(health, max_health)  # Signal health change
	
	# Blink effect when damaged
	if sprite and not is_dead:
		sprite.modulate = Color(1, 0.3, 0.3, 1)  # Red tint
		await get_tree().create_timer(0.1).timeout
		if sprite and not is_dead:
			sprite.modulate = Color(1, 1, 1, 1)  # Back to normal
	
	if knockback_direction != Vector2.ZERO:
		is_knockback = true
		knockback_velocity = knockback_direction.normalized() * 110.0
		velocity = Vector2.ZERO
	
	if health <= 0:
		died.emit()  # Signal that enemy died
		if respawn_enabled:
			is_dead = true
			respawn_timer = RESPAWN_DELAY
			visible = false
			collision_layer = 0
			collision_mask = 0
			velocity = Vector2.ZERO
			can_attack = false
			set_physics_process(true)
		else:
			queue_free()

func _respawn() -> void:
	health = max_health
	health_changed.emit(health, max_health)
	velocity = Vector2.ZERO
	can_attack = true
	attack_cooldown = 0.0
	is_knockback = false
	knockback_velocity = Vector2.ZERO
	is_dead = false
	is_moving = false
	player_detected = false
	player_lost_timer = 0.0
	visible = true
	collision_layer = 1
	collision_mask = 1
	state = STATE.IDLE
	
	if not player:
		return
	
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	
	var candidate_offsets = [
		Vector2(TILE_SIZE.x * 3, TILE_SIZE.y * 3),
		Vector2(-TILE_SIZE.x * 3, -TILE_SIZE.y * 3),
		Vector2(-TILE_SIZE.x * 3, TILE_SIZE.y * 3),
		Vector2(TILE_SIZE.x * 3, -TILE_SIZE.y * 3),
		Vector2(TILE_SIZE.x * 2, TILE_SIZE.y * 2),
		Vector2(-TILE_SIZE.x * 2, -TILE_SIZE.y * 2),
		Vector2(-TILE_SIZE.x * 2, TILE_SIZE.y * 2),
		Vector2(TILE_SIZE.x * 2, -TILE_SIZE.y * 2),
		Vector2(TILE_SIZE.x * 4, 0),
		Vector2(-TILE_SIZE.x * 4, 0),
		Vector2(0, TILE_SIZE.y * 4),
		Vector2(0, -TILE_SIZE.y * 4)
	]
	
	for offset in candidate_offsets:
		var test_pos = player.global_position + offset
		query.position = test_pos
		var result = space_state.intersect_point(query, 1)
		
		if result.is_empty():
			var occupied = false
			
			if player.global_position.distance_to(test_pos) < TILE_SIZE.x:
				occupied = true
			
			if not occupied:
				for other_enemy in get_tree().get_nodes_in_group("enemy"):
					if other_enemy != self and other_enemy.global_position.distance_to(test_pos) < 2:
						occupied = true
						break
			
			if not occupied:
				global_position = test_pos
				return
	
	var fallback_pos = player.global_position + Vector2(TILE_SIZE.x * 3, TILE_SIZE.y * 3)
	global_position = fallback_pos

func spawn_hit_particle(hit_position: Vector2):
	"""Spawn and manage particle effect at hit location"""
	var particle = PARTICLE_SCENE.instantiate()
	particle.global_position = hit_position
	get_tree().root.add_child(particle)
	
	# The particle scene root IS the AnimatedSprite2D
	if particle is AnimatedSprite2D:
		if particle.sprite_frames.has_animation("Ted Attack Particle"):
			particle.sprite_frames.set_animation_loop("Ted Attack Particle", false)
			particle.play("Ted Attack Particle")
		elif particle.sprite_frames.has_animation("Particle 1"):
			particle.sprite_frames.set_animation_loop("Particle 1", false)
			particle.play("Particle 1")
		particle.animation_finished.connect(func(): particle.queue_free())

func spawn_damage_text(damage: float, is_critical: bool, hit_pos: Vector2) -> void:
	"""Spawn floating damage text at specified position"""
	var damage_text = DAMAGE_TEXT_SCENE.instantiate()
	damage_text.global_position = hit_pos + Vector2(0, -5)  # Slightly above hit position
	get_tree().root.add_child(damage_text)
	damage_text.setup(damage, is_critical)


