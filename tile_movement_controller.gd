extends CharacterBody2D

## Base movement controller for tile-based entities
## Handles smooth interpolation, collision detection, and tile alignment
## Designed for isometric grid-based movement

class_name TileMovementController

const TILE_SIZE: Vector2 = Vector2(8, 4)  # Isometric tile dimensions

@export var move_speed: float = 50.0
@export var snap_threshold: float = 0.5  # Distance threshold for snapping to target

var is_moving: bool = false
var target_pos: Vector2 = Vector2.ZERO
var _previous_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	target_pos = global_position
	_previous_pos = global_position

func _physics_process(delta: float) -> void:
	if is_moving:
		_handle_movement(delta)

## Start movement to a target tile position
## Returns true if movement started, false if already moving
func move_to(next_pos: Vector2) -> bool:
	if is_moving:
		return false  # Already moving
	
	_previous_pos = global_position
	target_pos = next_pos
	is_moving = true
	return true

## Handle smooth interpolation and collision detection
func _handle_movement(_delta: float) -> void:
	var direction = (target_pos - global_position).normalized()
	velocity = direction * move_speed
	move_and_slide()

	# Always snap to tile after movement
	snap_to_tile()

	# Handle collision with sliding
	if get_slide_collision_count() > 0:
		velocity = Vector2.ZERO
		is_moving = false
		return

	# Check if reached target tile
	if global_position.distance_to(target_pos) < snap_threshold:
		global_position = target_pos
		velocity = Vector2.ZERO
		is_moving = false
		_on_movement_complete()

## Called when movement to target tile completes (override in subclasses)
func _on_movement_complete() -> void:
	pass  # Override in subclass if needed

## Check if next tile is walkable (override in subclasses for custom checks)
func is_tile_walkable(test_pos: Vector2) -> bool:
	return _check_wall_collision(test_pos)

## Check for wall/barrier collision at position
func _check_wall_collision(test_pos: Vector2) -> bool:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = test_pos
	query.collision_mask = 1  # Walls on layer 1
	query.exclude = [self]
	var wall_hit = space_state.intersect_point(query)
	
	return wall_hit.size() == 0  # True if no walls

## Snap position to nearest tile (useful after knockback or collision)
func snap_to_tile() -> void:
	global_position = (global_position / TILE_SIZE).round() * TILE_SIZE
	target_pos = global_position
	is_moving = false
	velocity = Vector2.ZERO

## Stop current movement immediately
func stop_movement() -> void:
	is_moving = false
	velocity = Vector2.ZERO
	target_pos = global_position

## Get the tile position for a world position
static func world_to_tile(world_pos: Vector2) -> Vector2:
	return (world_pos / TILE_SIZE).round() * TILE_SIZE

## Get adjacent tile positions (4 cardinal directions in isometric)
func get_adjacent_tiles() -> Array[Vector2]:
	var tiles: Array[Vector2] = []
	tiles.append(global_position + Vector2(TILE_SIZE.x, TILE_SIZE.y))    # SE
	tiles.append(global_position + Vector2(-TILE_SIZE.x, -TILE_SIZE.y))  # NW
	tiles.append(global_position + Vector2(-TILE_SIZE.x, TILE_SIZE.y))   # SW
	tiles.append(global_position + Vector2(TILE_SIZE.x, -TILE_SIZE.y))   # NE
	return tiles

## Get direction vector from current position to target
func get_direction_to(target: Vector2) -> Vector2:
	return (target - global_position).normalized()

## Check if currently on a tile boundary (not mid-movement)
func is_on_tile() -> bool:
	var tile_pos = world_to_tile(global_position)
	return global_position.distance_to(tile_pos) < 0.1
