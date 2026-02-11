extends CharacterBody2D

## Ted - Enemy AI Controller
## Handles chase behavior, pathfinding, and combat

# State machine for cleaner logic
enum STATE { CHASE, ATTACK, STUNNED, DEAD }

# Signals for events
signal health_changed(new_health: int, max_health: int)
signal died

const TILE_SIZE: Vector2 = Vector2(8, 4)
const DAMAGE_TEXT_SCENE = preload("res://DamageText.tscn")

# Y-sort for isometric depth
const USE_Y_SORT: bool = true

@export var move_speed: float = 25
@export var health: int = 50
@export var max_health: int = 50
@export var attack_damage: float = 15.0
@export var attack_interval: float = 0.8
@export var elevation: float = 0.0  # Vertical position for 3D-like terrain (future use)
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D if has_node("AnimatedSprite2D") else null

var state: STATE = STATE.CHASE
var player: CharacterBody2D
var current_direction: String = "SE"
var attack_cooldown: float = 0.05
var can_attack: bool = true
var is_attacking: bool = false
var is_knockback: bool = false
var knockback_velocity: Vector2 = Vector2.ZERO
var is_dead: bool = false
var is_moving: bool = false
var target_pos: Vector2 = Vector2.ZERO
var previous_pos: Vector2 = Vector2.ZERO
var move_timer: float = 0.0
var player_detected: bool = false
var player_in_detection_zone: bool = false
var player_lost_timer: float = 0.0
var stuck_timer: float = 0.0
var last_valid_pos: Vector2 = Vector2.ZERO
var movement_timeout: float = 0.0

const KNOCKBACK_FRICTION: float = 400.0
const KNOCKBACK_STRENGTH: float = 110.0
const MOVE_INTERVAL: float = 0.05  # Time between tile movements (smaller = smoother)
const PLAYER_LOST_TIME: float = 2.0  # Time to forget player after losing range
const BLINK_DURATION: float = 0.1

func _ready() -> void:
	add_to_group("enemy")  # Keep "enemy" group for compatibility
	add_to_group("ted")     # Add Ted-specific group
	player = get_tree().get_first_node_in_group("player")
	target_pos = global_position
	previous_pos = global_position
	last_valid_pos = global_position
	
	# Detection range signals are now connected via detection_range.gd script
	# which sets player_in_detection_zone directly on the parent (this node)
	
	if sprite:
		sprite.play("Idle_" + current_direction)
		
		# Set attack animations to non-looping and walk animations to looping
		if sprite.sprite_frames:
			for direction in ["SE", "NW", "SW", "NE"]:
				var attack_anim: String = "Attack_" + direction
				if sprite.sprite_frames.has_animation(attack_anim):
					sprite.sprite_frames.set_animation_loop(attack_anim, false)
				var walk_anim: String = "Walking_" + direction
				if sprite.sprite_frames.has_animation(walk_anim):
					sprite.sprite_frames.set_animation_loop(walk_anim, true)
		
		# Connect animation_finished signal
		if sprite.has_signal("animation_finished"):
			sprite.animation_finished.connect(_on_animation_finished)
	
	# Emit initial health
	health_changed.emit(health, max_health)

func _on_animation_finished() -> void:
	"""Handle animation completion - return to idle after attack"""
	if sprite and sprite.animation.begins_with("Attack_"):
		is_attacking = false
		sprite.play("Idle_" + current_direction)
	health_changed.emit(health, max_health)


func _physics_process(delta: float) -> void:
	# Update z-index for proper depth sorting in isometric view
	# Use Y position of sprite bottom (feet) for sorting, minus elevation for 3D effect
	# Add base offset to ensure Ted renders above ground tiles (which have z_index = 1)
	z_index = 1000 + int(global_position.y + 4 - elevation)
	
	if not player:
		return
	
	# Ensure visibility and sprite visibility when alive
	if not is_dead:
		if not visible:
			visible = true
		if sprite and not sprite.visible:
			sprite.visible = true
	
	# Ted is dead - do nothing
	if is_dead:
		state = STATE.DEAD
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
			# Snap to nearest tile to maintain grid alignment
			var nearest_tile = _snap_to_nearest_tile(global_position)
			global_position = nearest_tile
			state = STATE.CHASE
		return
	
	# Update attack cooldown
	if not can_attack:
		attack_cooldown -= delta
		if attack_cooldown <= 0:
			can_attack = true
	
	# State will be controlled by external detection script
	# Default to CHASE state
	
	# Handle tile-based movement
	if is_moving:
		var direction = (target_pos - global_position).normalized()
		velocity = direction * move_speed
		
		# Update facing direction based on actual movement
		if velocity.length() > 0.1:
			_update_direction_from_velocity(velocity)
		
		# Keep playing walking animation while moving
		if sprite and not sprite.animation.begins_with("Walking_") and not is_attacking:
			sprite.play("Walking_" + current_direction)
		
		move_and_slide()
		
		# Reached target
		if global_position.distance_to(target_pos) < 2.0:
			is_moving = false
			velocity = Vector2.ZERO
			movement_timeout = 0.0
			# Don't return - let it pick next tile immediately if still chasing
		
		# Movement timeout (prevent infinite chasing)
		movement_timeout += delta
		if movement_timeout > 3.0:
			is_moving = false
			velocity = Vector2.ZERO
			movement_timeout = 0.0
			if sprite:
				sprite.play("Idle_" + current_direction)
		
		# Return only if still moving (haven't reached target yet)
		if is_moving:
			return
	
	# Only pick new tile when not moving
	if not is_moving and not is_attacking and state == STATE.CHASE:
		# Only chase if player is in detection zone
		if not player_in_detection_zone:
			# Player left detection zone - play idle and wait
			if sprite and not sprite.animation.begins_with("Idle_"):
				sprite.play("Idle_" + current_direction)
			return
		
		# DEBUG: Player is in detection zone, attempting to chase
		# print("[Ted] Chasing player at distance: ", global_position.distance_to(player.global_position))
		
		# Pick next tile immediately (no timer delay)
		# But stop moving if already adjacent to player (let attack handle it)
		var distance_to_player = global_position.distance_to(player.global_position)
		if distance_to_player < TILE_SIZE.length() + 2:
			# Adjacent to player - stop moving and face the player so attacks aim correctly
			is_moving = false
			# Compute facing based on relative position to player
			var to_player = player.global_position - global_position
			if to_player.x > 0 and to_player.y > 0:
				current_direction = "SE"
			elif to_player.x < 0 and to_player.y < 0:
				current_direction = "NW"
			elif to_player.x < 0 and to_player.y > 0:
				current_direction = "SW"
			else:
				current_direction = "NE"
			if sprite:
				sprite.play("Idle_" + current_direction)
			# Enter ATTACK state so other systems know Ted is ready to attack
			state = STATE.ATTACK
			# Attack logic now handled by Ted's hit box on attack animation
			if can_attack and not is_dead:
				can_attack = false
				attack_cooldown = attack_interval
				# Play attack animation which will trigger hit box
				var attack_anim := "Attack_" + current_direction
				if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(attack_anim):
					is_attacking = true
					sprite.play(attack_anim)
					# TODO: Activate Ted's hit box during attack animation
					# For now, apply damage directly as fallback
					if player and player.has_method("take_damage"):
						var atk_to_player = (player.global_position - global_position).normalized()
						player.take_damage(atk_to_player * KNOCKBACK_STRENGTH, attack_damage, false)
				else:
					is_attacking = false
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

func _snap_to_nearest_tile(pos: Vector2) -> Vector2:
	"""Snap a world position to the nearest tile center"""
	var tile_x = round(pos.x / TILE_SIZE.x) * TILE_SIZE.x
	var tile_y = round(pos.y / TILE_SIZE.y) * TILE_SIZE.y
	return Vector2(tile_x, tile_y)

func _update_direction_from_velocity(vel: Vector2) -> void:
	"""Update current_direction based on velocity vector"""
	if vel.length() < 0.1:
		return
	
	# Determine direction from velocity
	if vel.x > 0 and vel.y > 0:
		current_direction = "SE"
	elif vel.x < 0 and vel.y < 0:
		current_direction = "NW"
	elif vel.x < 0 and vel.y > 0:
		current_direction = "SW"
	else:
		current_direction = "NE"

func take_damage(knockback_direction: Vector2, damage: float, _is_critical: bool = false) -> void:
	"""Handle damage from player attacks with consistent signature"""
	if is_dead:
		return

	# Apply damage
	health -= int(damage)
	health = max(health, 0)
	health_changed.emit(health, max_health)

	# Blink effect when damaged
	if sprite and not is_dead:
		sprite.modulate = Color(1, 0.3, 0.3, 1)
		await get_tree().create_timer(BLINK_DURATION).timeout
		if sprite and not is_dead:
			sprite.modulate = Color(1, 1, 1, 1)

	# Apply knockback if provided
	if knockback_direction != Vector2.ZERO:
		is_knockback = true
		knockback_velocity = knockback_direction.normalized() * KNOCKBACK_STRENGTH
		velocity = Vector2.ZERO

	if health <= 0:
		died.emit()
		is_dead = true
		state = STATE.DEAD
		visible = false
		queue_free()
