extends CharacterBody2D

## Ted - Enemy AI Controller
## Handles chase behavior, pathfinding, and combat

enum STATE { IDLE, CHASE, ATTACK, STUNNED, DEAD }

signal health_changed(new_health: int, max_health: int)
signal died

const TILE_SIZE := Vector2(8, 4)
const DAMAGE_TEXT_SCENE = preload("res://DamageText.tscn")
const KNOCKBACK_FRICTION := 400.0
const KNOCKBACK_STRENGTH := 110.0
const BLINK_DURATION := 0.1
const ATTACK_RANGE := 12.0
const DIRECTION_CHANGE_DELAY := 0.15
const PATH_RECALC_INTERVAL := 1.0
const STUCK_THRESHOLD := 1.5
const VISIBILITY_CHECK_INTERVAL := 0.5

# Slope constants
const SLOPE_MAX_OFFSET := 16.0
const SLOPE_ROTATION_DEG := 2.0
const SLOPE_UPHILL_SPEED := 0.85
const SLOPE_DOWNHILL_SPEED := 1.15
const TILE_PX := 8.0
const SLOPE_DIAG := 12.0

@export var move_speed: float = 20

@export var health: int = 50
@export var max_health: int = 50
@export var attack_damage: float = 10
@export var attack_interval: float = 0.8
@export var elevation: float = 0.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D if has_node("AnimatedSprite2D") else null

var state: STATE = STATE.IDLE
var player: CharacterBody2D
var current_direction := "SE"
var attack_cooldown: float = 0.0
var is_attacking := false
var is_knockback := false
var knockback_velocity := Vector2.ZERO
var is_dead := false
var player_in_detection_zone := false
var can_see_player := false

# Terrain
var terrain_0: TileMapLayer = null
var terrain_1: TileMapLayer = null
var terrain_2: TileMapLayer = null
var current_terrain: TileMapLayer = null

# Slope visual state
var slope_offset := 0.0
var slope_target_offset := 0.0
var slope_rotation := 0.0
var slope_target_rotation := 0.0
var shadow_rect: ColorRect = null
var is_on_slope := false
var was_on_slope := false

# Pathfinding (lightweight)
var pathfinding: AStarPathfinding = null
var current_path: Array = []
var path_index := 0

# Timers (consolidated to reduce per-frame branches)
var _dir_timer := 0.0
var _path_timer := 0.0
var _vis_timer := 0.0
var _stuck_timer := 0.0
var _last_pos := Vector2.ZERO
var _last_dir := "SE"

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("ted")
	player = get_tree().get_first_node_in_group("player")

	var parent := get_parent()
	if parent:
		terrain_0 = parent.get_node_or_null("Terrain 0")
		terrain_1 = parent.get_node_or_null("Terrain 1")
		terrain_2 = parent.get_node_or_null("Terrain 2")
		current_terrain = terrain_0

	pathfinding = AStarPathfinding.new(TILE_SIZE)
	_last_pos = global_position

	# Create blob shadow under feet
	_create_blob_shadow()

	# detection_range.gd already handles signals and sets player_in_detection_zone

	if sprite:
		sprite.play("Idle_SE")
		if sprite.sprite_frames:
			for dir in ["SE", "NW", "SW", "NE"]:
				if sprite.sprite_frames.has_animation("Attack_" + dir):
					sprite.sprite_frames.set_animation_loop("Attack_" + dir, false)
				if sprite.sprite_frames.has_animation("Walking_" + dir):
					sprite.sprite_frames.set_animation_loop("Walking_" + dir, true)
		sprite.animation_finished.connect(_on_animation_finished)

	health_changed.emit(health, max_health)

func _on_animation_finished() -> void:
	if sprite and sprite.animation.begins_with("Attack_"):
		is_attacking = false
		sprite.play("Idle_" + current_direction)


func _create_blob_shadow() -> void:
	var shadow := ColorRect.new()
	shadow.name = "ShadowRect"
	shadow.size = Vector2(10, 4)
	shadow.position = Vector2(-5, 6)
	shadow.z_index = -1
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = load("res://Shaders/Double_Dither.gdshader")
	shader_mat.set_shader_parameter("center", Vector2(0.5, 0.5))
	shader_mat.set_shader_parameter("radius", 0.45)
	shader_mat.set_shader_parameter("pixel_size", 1.0)
	shader_mat.set_shader_parameter("resolution", Vector2(10, 4))
	shader_mat.set_shader_parameter("bayer_size", 0)
	shader_mat.set_shader_parameter("interpolate", true)
	shader_mat.set_shader_parameter("falloff", 2.0)
	shader_mat.set_shader_parameter("color", Color(0, 0, 0, 0.35))
	shader_mat.set_shader_parameter("invert", false)
	shadow.material = shader_mat
	
	add_child(shadow)
	shadow_rect = shadow

func _physics_process(delta: float) -> void:
	# Z-sorting
	z_index = 1000 + int(global_position.y + 4 - elevation)

	# Slope interpolation (only when moving)
	if velocity.length_squared() > 0.01:
		slope_offset = lerp(slope_offset, slope_target_offset, delta * 2.5)
		slope_rotation = lerp(slope_rotation, slope_target_rotation, delta * 4.0)

	if sprite:
		sprite.position.y = slope_offset
		sprite.rotation_degrees = slope_rotation
	
	# Keep shadow on the slope surface (follows sprite feet)
	if shadow_rect:
		shadow_rect.position.y = 6 + slope_offset

	if is_dead or not player:
		return

	# Handle knockback (early return)
	if is_knockback:
		_process_knockback(delta)
		return

	# Tick cooldown
	if attack_cooldown > 0.0:
		attack_cooldown -= delta

	# Not in detection range -> idle
	if not player_in_detection_zone:
		_set_idle()
		return

	# Periodic visibility check (raycast)
	_vis_timer += delta
	if _vis_timer >= VISIBILITY_CHECK_INTERVAL:
		_vis_timer = 0.0
		can_see_player = _check_line_of_sight()

	if not can_see_player:
		_set_idle()
		return

	# Distance check
	var to_player := player.global_position - global_position
	var dist := to_player.length()

	# Attack range
	if dist < ATTACK_RANGE:
		_process_attack(to_player)
		return

	# Chase
	_process_chase(delta)

# ── State processors ──────────────────────────────────────────

func _set_idle() -> void:
	if state == STATE.IDLE:
		return
	state = STATE.IDLE
	velocity = Vector2.ZERO
	current_path.clear()
	_play_anim("Idle_" + current_direction)

func _process_knockback(delta: float) -> void:
	state = STATE.STUNNED
	velocity = knockback_velocity
	move_and_slide()
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_FRICTION * delta)
	if knockback_velocity.length_squared() < 1.0:
		is_knockback = false
		knockback_velocity = Vector2.ZERO
		velocity = Vector2.ZERO
		_update_elevation()

func _process_attack(to_player: Vector2) -> void:
	state = STATE.ATTACK
	velocity = Vector2.ZERO
	_set_direction_stable(to_player)

	if attack_cooldown <= 0.0 and not is_attacking:
		attack_cooldown = attack_interval
		is_attacking = true
		var anim := "Attack_" + current_direction
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
			sprite.play(anim)
			if player and player.has_method("take_damage"):
				var kb := (player.global_position - global_position).normalized()
				player.take_damage(kb * KNOCKBACK_STRENGTH, attack_damage, false)
		else:
			is_attacking = false
	elif not is_attacking:
		_play_anim("Idle_" + current_direction)

func _process_chase(delta: float) -> void:
	state = STATE.CHASE
	is_attacking = false

	# Stuck detection
	_stuck_timer += delta
	if global_position.distance_squared_to(_last_pos) > 4.0:
		_stuck_timer = 0.0
		_last_pos = global_position

	# Recalculate path periodically or when stuck
	_path_timer += delta
	if current_path.is_empty() or _path_timer >= PATH_RECALC_INTERVAL or _stuck_timer >= STUCK_THRESHOLD:
		_recalculate_path()
		_path_timer = 0.0
		_stuck_timer = 0.0

	# Follow path or direct movement
	var move_dir := _follow_path()
	if move_dir == Vector2.ZERO:
		move_dir = _direct_move_dir()

	_set_direction_stable(move_dir)

	# Blocked check
	var intended := global_position + move_dir * move_speed * delta
	if terrain_0 and terrain_0.has_method("can_move_to") and not terrain_0.can_move_to(intended):
		current_path.clear()
		_stuck_timer = STUCK_THRESHOLD
		velocity = Vector2.ZERO
		_play_anim("Idle_" + current_direction)
		return

	# Move
	var old_elev := elevation
	velocity = move_dir * move_speed
	_update_elevation()
	_update_slope_visual(move_dir, old_elev)
	move_and_slide()
	_play_anim("Walking_" + current_direction)

# ── Direction helpers ─────────────────────────────────────────

func _set_direction_stable(dir: Vector2) -> void:
	if dir.length_squared() < 0.01:
		return
	_dir_timer += get_physics_process_delta_time()
	var new_dir := _dir_from_vec(dir)
	if new_dir != _last_dir and _dir_timer >= DIRECTION_CHANGE_DELAY:
		current_direction = new_dir
		_last_dir = new_dir
		_dir_timer = 0.0
	elif new_dir == _last_dir:
		current_direction = new_dir

func _dir_from_vec(v: Vector2) -> String:
	if v.x >= 0.0:
		return "SE" if v.y >= 0.0 else "NE"
	else:
		return "SW" if v.y >= 0.0 else "NW"

# ── Pathfinding ───────────────────────────────────────────────

func _recalculate_path() -> void:
	if not player or not pathfinding:
		return
	var start := _snap(global_position)
	var goal := _snap(player.global_position)
	var space := get_world_2d().direct_space_state
	current_path = pathfinding.find_path(start, goal, space)
	path_index = 0

func _follow_path() -> Vector2:
	if current_path.is_empty() or path_index >= current_path.size():
		return Vector2.ZERO
	var target: Vector2 = current_path[path_index]
	if global_position.distance_squared_to(target) < 36.0:
		path_index += 1
		if path_index >= current_path.size():
			current_path.clear()
			return Vector2.ZERO
		target = current_path[path_index]
	return (target - global_position).normalized()

func _direct_move_dir() -> Vector2:
	if not player:
		return Vector2.ZERO
	var to := player.global_position - global_position
	var step := _get_step()
	if abs(to.x) > abs(to.y):
		return Vector2(step.x, step.y).normalized() if to.x > 0 else Vector2(-step.x, -step.y).normalized()
	else:
		return Vector2(-step.x, step.y).normalized() if to.y > 0 else Vector2(step.x, -step.y).normalized()

func _snap(pos: Vector2) -> Vector2:
	var s := _get_step()
	return Vector2(round(pos.x / s.x) * s.x, round(pos.y / s.y) * s.y)

func _get_step() -> Vector2:
	if terrain_0 and terrain_0.has_method("get_move_step"):
		return terrain_0.get_move_step()
	return TILE_SIZE

# ── Line of sight ─────────────────────────────────────────────

func _check_line_of_sight() -> bool:
	if not player:
		return false
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, player.global_position)
	query.collision_mask = 1
	query.exclude = [self]
	return space.intersect_ray(query).is_empty()

# ── Combat ────────────────────────────────────────────────────

func take_damage(knockback_direction: Vector2, damage: float, _is_critical: bool = false) -> void:
	if is_dead:
		return
	health -= int(damage)
	health = max(health, 0)
	health_changed.emit(health, max_health)

	if sprite and not is_dead:
		sprite.modulate = Color(1, 0.3, 0.3, 1)
		await get_tree().create_timer(BLINK_DURATION).timeout
		if sprite and not is_dead:
			sprite.modulate = Color.WHITE

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

# ── Elevation & Slopes ───────────────────────────────────────

func _update_elevation() -> void:
	var pos := global_position
	if terrain_2 and terrain_2.has_tile_at(pos):
		if current_terrain != terrain_2:
			current_terrain = terrain_2
			elevation = 2.0
	elif terrain_1 and terrain_1.has_tile_at(pos):
		if current_terrain != terrain_1:
			current_terrain = terrain_1
			elevation = 1.0
	elif terrain_0 and terrain_0.has_tile_at(pos):
		if current_terrain != terrain_0:
			current_terrain = terrain_0
			elevation = 0.0

func _update_slope_visual(move_dir: Vector2, old_elev: float) -> void:
	if not terrain_0:
		return

	var tile_coords: Vector2i = terrain_0.get_tile_coords(global_position)
	var on_slope := _is_slope_tile(tile_coords)

	if not on_slope:
		if was_on_slope:
			slope_target_offset = 0.0
			slope_target_rotation = 0.0
			was_on_slope = false
			is_on_slope = false
		else:
			slope_target_offset = 0.0
			slope_target_rotation = 0.0
			is_on_slope = false
		if sprite:
			sprite.speed_scale = 1.0
		return

	is_on_slope = true
	was_on_slope = true

	var elev_diff := absf(elevation - old_elev)
	if elev_diff == 0.0:
		elev_diff = 1.0

	var going_up := (elevation > old_elev) or (move_dir.y < 0.0 and is_on_slope)
	var going_down := (elevation < old_elev) or (move_dir.y > 0.0 and is_on_slope)

	var vert_climb := -SLOPE_DIAG * elev_diff + move_dir.normalized().y * TILE_PX * elev_diff

	if going_up:
		slope_target_offset = vert_climb
		slope_target_rotation = -SLOPE_ROTATION_DEG * elev_diff
		if sprite:
			sprite.speed_scale = SLOPE_UPHILL_SPEED
	elif going_down:
		slope_target_offset = -vert_climb
		slope_target_rotation = SLOPE_ROTATION_DEG * elev_diff
		if sprite:
			sprite.speed_scale = SLOPE_DOWNHILL_SPEED
	else:
		slope_target_offset = 0.0
		slope_target_rotation = 0.0
		if sprite:
			sprite.speed_scale = 1.0

func _is_slope_tile(tile_coords: Vector2i) -> bool:
	for terrain in [terrain_0, terrain_1, terrain_2]:
		if terrain:
			var td = terrain.get_cell_tile_data(tile_coords)
			if td and td.get_custom_data("Elevation Tile"):
				return true
	return false

# ── Utility ───────────────────────────────────────────────────

func _play_anim(anim_name: String) -> void:
	if sprite and sprite.animation != anim_name:
		if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim_name):
			sprite.play(anim_name)
