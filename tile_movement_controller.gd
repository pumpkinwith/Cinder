extends CharacterBody2D

## Base movement controller for tile-based entities
## Handles smooth interpolation, collision detection, and tile alignment
## Designed for isometric grid-based movement

class_name TileMovementController

const TILE_SIZE: Vector2 = Vector2(8, 4)  # Isometric tile dimensions

@export var move_speed: float = 50.0
@export var snap_threshold: float = 0.5  # Distance threshold for snapping to target
@export var occupancy_groups: Array = ["player", "enemy"]
@export var occupy_check_radius: float = 1.5
@export var use_free_movement: bool = true  # Allow free movement instead of strict tile-based
@export var elevation: float = 0.0  # Y-offset for vertical positioning (for future terrain)
@export var movement_tilemap_path: NodePath = NodePath("../Terrain 0")

var is_moving: bool = false
var target_pos: Vector2 = Vector2.ZERO
var _previous_pos: Vector2 = Vector2.ZERO
var _reserved_tile_key: String = ""
var _start_pos: Vector2 = Vector2.ZERO
var _travel_t: float = 0.0
var _travel_time: float = 0.0
var _stuck_timer: float = 0.0
var _last_valid_pos: Vector2 = Vector2.ZERO
var movement_tilemap: TileMapLayer = null
var tile_step: Vector2 = TILE_SIZE

# Shared reservation map so only one entity can reserve a tile at a time
# CRITICAL: Must be static to be shared across all instances
static var _reserved_tiles: Dictionary = {}

func _ready() -> void:
	if movement_tilemap_path != NodePath():
		movement_tilemap = get_node_or_null(movement_tilemap_path)
	if not movement_tilemap:
		var parent = get_parent()
		if parent:
			movement_tilemap = parent.get_node_or_null("Terrain 0")
	if movement_tilemap and movement_tilemap.tile_set:
		var ts = movement_tilemap.tile_set.tile_size
		tile_step = Vector2(ts.x * 0.5, ts.y * 0.5)

	# Ensure entity starts exactly on a tile center
	target_pos = world_to_tile(global_position)
	global_position = target_pos
	_previous_pos = global_position
	_last_valid_pos = global_position
	# Reserve starting tile so others cannot move into it
	_reserve_tile(target_pos)

func _physics_process(delta: float) -> void:
	if is_moving:
		# Check if stuck (not making progress)
		var dist_traveled = global_position.distance_to(_previous_pos)
		if dist_traveled < 0.1:
			_stuck_timer += delta
			if _stuck_timer > 0.3:  # Stuck for 0.3 seconds
				# Recover by snapping to last valid position
				global_position = _last_valid_pos
				snap_to_tile()
				_stuck_timer = 0.0
				return
		else:
			_stuck_timer = 0.0
			_last_valid_pos = global_position
		
		_handle_movement(delta)
		_previous_pos = global_position

## Start movement to a target tile position
## Returns true if movement started, false if already moving
func move_to(next_pos: Vector2) -> bool:
	if is_moving:
		return false  # Already moving

	# Quantize requested position to the nearest tile center so entities always move tile-to-tile
	_previous_pos = global_position
	var quantized = world_to_tile(next_pos)
	# If already at that tile, don't start movement
	if quantized.distance_to(global_position) < 0.01:
		return false

	# Check world collisions and occupancy
	if not is_tile_walkable(quantized):
		return false
	# Check if another object occupies the tile (by group membership)
	if is_tile_occupied(quantized):
		return false

	# Attempt to reserve the destination tile. If someone else holds it, abort.
	var k = _tile_key(quantized)
	if _reserved_tiles.has(k) and _reserved_tiles[k] != self:
		return false

	# Reserve destination and release old reservation explicitly (avoid overwriting bug)
	var old_key = _reserved_tile_key
	_reserved_tiles[k] = self
	_reserved_tile_key = k
	if old_key != "" and old_key != _reserved_tile_key:
		if _reserved_tiles.has(old_key) and _reserved_tiles[old_key] == self:
			_reserved_tiles.erase(old_key)

	# Initialize precise interpolation between tiles
	_previous_pos = global_position
	_start_pos = global_position
	target_pos = quantized
	var dist = _start_pos.distance_to(target_pos)
	_travel_time = dist / max(move_speed, 0.0001)
	_travel_t = 0.0
	is_moving = true
	return true

## Handle smooth interpolation and collision detection

func _handle_movement(delta: float) -> void:
	if use_free_movement:
		# Free movement mode - move directly toward target without strict tile locking
		var direction = (target_pos - global_position).normalized()
		var distance = global_position.distance_to(target_pos)
		
		if distance < snap_threshold:
			# Arrived at target
			global_position = target_pos
			is_moving = false
			_on_movement_complete()
			_reserve_tile(target_pos)
			return
		
		# Move toward target
		var move_delta = direction * move_speed * delta
		var next_pos = global_position + move_delta
		
		# Check collision at next position
		if _check_wall_collision(next_pos):
			global_position = next_pos
		else:
			# Hit wall - try sliding along it
			var slide_x = global_position + Vector2(move_delta.x, 0)
			var slide_y = global_position + Vector2(0, move_delta.y)
			
			if _check_wall_collision(slide_x):
				global_position = slide_x
			elif _check_wall_collision(slide_y):
				global_position = slide_y
			else:
				# Can't move - snap to tile and stop
				snap_to_tile()
				_reserve_tile(global_position)
				is_moving = false
				return
	else:
		# Precise time-based interpolation between tile centers (original strict mode)
		_travel_t += delta
		var t := 1.0
		if _travel_time > 0.0:
			t = min(_travel_t / _travel_time, 1.0)

		var next_pos = _start_pos.lerp(target_pos, t)

		# Check wall collision at next position (if there's a wall, abort and snap)
		if not _check_wall_collision(next_pos):
			# Snap back to nearest tile and re-reserve it
			snap_to_tile()
			_reserve_tile(global_position)
			is_moving = false
			return

		# Move to the interpolated position
		global_position = next_pos

		# Arrived
		if t >= 1.0:
			global_position = target_pos
			is_moving = false
			_travel_t = 0.0
			_travel_time = 0.0
			_on_movement_complete()
			# Ensure reservation corresponds to this tile
			_reserve_tile(target_pos)

## Called when movement to target tile completes (override in subclasses)
func _on_movement_complete() -> void:
	pass  # Override in subclass if needed

## Check if next tile is walkable (override in subclasses for custom checks)
func is_tile_walkable(test_pos: Vector2) -> bool:
	# Return true if position has no wall collision and is within world bounds (caller may add more checks)
	return _check_wall_collision(test_pos)

## Check for wall/barrier collision at position
func _check_wall_collision(test_pos: Vector2) -> bool:
	var space_state = get_world_2d().direct_space_state
	
	# Use shape query instead of point query for better detection
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 2.0  # Small collision radius
	query.shape = shape
	query.transform = Transform2D(0, test_pos)
	query.collision_mask = 1  # Walls on layer 1
	query.exclude = [self]
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var wall_hit = space_state.intersect_shape(query, 1)
	
	return wall_hit.size() == 0  # True if no walls

## Snap position to nearest tile (useful after knockback or collision)
func snap_to_tile() -> void:
	# Forcefully snap to the nearest tile center and stop movement
	var tile = world_to_tile(global_position)
	global_position = tile
	target_pos = global_position
	is_moving = false
	_start_pos = global_position
	_travel_t = 0.0
	_travel_time = 0.0
	velocity = Vector2.ZERO

## Stop current movement immediately
func stop_movement() -> void:
	is_moving = false
	velocity = Vector2.ZERO
	target_pos = global_position


## Move by a cardinal isometric direction ("NE","SE","SW","NW")
func move_by_direction(dir: String) -> bool:
	var offset := Vector2.ZERO
	match dir:
		"SE": offset = Vector2(tile_step.x, tile_step.y)
		"NW": offset = Vector2(-tile_step.x, -tile_step.y)
		"SW": offset = Vector2(-tile_step.x, tile_step.y)
		"NE": offset = Vector2(tile_step.x, -tile_step.y)
		_:
			return false
	return move_to(global_position + offset)


## Apply a knockback vector expressed in world-space; this will pick the nearest tile
## in the knockback direction and move the entity there. `strength_tiles` indicates
## how many tiles to attempt to push (1.0 = one tile).
func apply_knockback_vector(kb_vector: Vector2, strength_tiles: float = 1.0) -> void:
	if kb_vector == Vector2.ZERO:
		return
	
	# Stop current movement
	stop_movement()
	
	# Compute desired world position
	var kb_distance = tile_step.length() * strength_tiles
	var desired = global_position + kb_vector.normalized() * kb_distance
	
	if use_free_movement:
		# In free movement, just push directly and let collision handle it
		var test_pos = desired
		if not _check_wall_collision(test_pos):
			# Hit wall immediately - try half distance
			test_pos = global_position + kb_vector.normalized() * kb_distance * 0.5
			if not _check_wall_collision(test_pos):
				# Still blocked - just snap to current tile
				snap_to_tile()
				_reserve_tile(global_position)
				return
		
		# Move to valid position
		global_position = test_pos
		snap_to_tile()  # Snap after knockback
		_reserve_tile(global_position)
		return
	
	# Original tile-based knockback
	var dest_tile = world_to_tile(desired)
	# If destination is same as current, do nothing
	if dest_tile.distance_to(global_position) < 0.1:
		return
	# If tile is not walkable or occupied, snap to current tile to avoid drifting off-grid
	if not is_tile_walkable(dest_tile) or is_tile_occupied(dest_tile):
		snap_to_tile()
		# ensure we hold a reservation for our current tile
		_reserve_tile(global_position)
		return

	# Attempt to reserve destination tile (avoid overwriting previous reservation)
	var k = _tile_key(dest_tile)
	if _reserved_tiles.has(k) and _reserved_tiles[k] != self:
		# Someone else reserved it; snap back to current tile
		snap_to_tile()
		_reserve_tile(global_position)
		return

	# Reserve destination and release old reservation explicitly
	var old_key = _reserved_tile_key
	_reserved_tiles[k] = self
	_reserved_tile_key = k
	if old_key != "" and old_key != _reserved_tile_key:
		if _reserved_tiles.has(old_key) and _reserved_tiles[old_key] == self:
			_reserved_tiles.erase(old_key)

	# Start precise interpolation toward knockback destination
	_previous_pos = global_position
	_start_pos = global_position
	target_pos = dest_tile
	var dist = _start_pos.distance_to(target_pos)
	_travel_time = dist / max(move_speed, 0.0001)
	_travel_t = 0.0
	is_moving = true

## Get the tile position for a world position
func world_to_tile(world_pos: Vector2) -> Vector2:
	if movement_tilemap:
		var coords: Vector2i = movement_tilemap.local_to_map(movement_tilemap.to_local(world_pos))
		return movement_tilemap.to_global(movement_tilemap.map_to_local(coords))
	return (world_pos / tile_step).round() * tile_step

## Get adjacent tile positions (4 cardinal directions in isometric)
func get_adjacent_tiles() -> Array[Vector2]:
	var tiles: Array[Vector2] = []
	tiles.append(global_position + Vector2(tile_step.x, tile_step.y))    # SE
	tiles.append(global_position + Vector2(-tile_step.x, -tile_step.y))  # NW
	tiles.append(global_position + Vector2(-tile_step.x, tile_step.y))   # SW
	tiles.append(global_position + Vector2(tile_step.x, -tile_step.y))   # NE
	return tiles

## Get direction vector from current position to target
func get_direction_to(target: Vector2) -> Vector2:
	return (target - global_position).normalized()

## Check if currently on a tile boundary (not mid-movement)
func is_on_tile() -> bool:
	var tile_pos = world_to_tile(global_position)
	return global_position.distance_to(tile_pos) < 0.1


## Helpers for tile reservation/occupancy
func _tile_key(tile_pos: Vector2) -> String:
	return str(tile_pos.x) + "," + str(tile_pos.y)

func _reserve_tile(tile_pos: Vector2) -> bool:
	var k = _tile_key(tile_pos)
	if _reserved_tiles.has(k) and _reserved_tiles[k] != self:
		return false
	_reserved_tiles[k] = self
	_reserved_tile_key = k
	return true

func release_reserved_tile() -> void:
	if _reserved_tile_key == "":
		return
	if _reserved_tiles.has(_reserved_tile_key) and _reserved_tiles[_reserved_tile_key] == self:
		_reserved_tiles.erase(_reserved_tile_key)
	_reserved_tile_key = ""

func is_tile_occupied(tile_pos: Vector2) -> bool:
	# Check for nodes in configured groups that are currently on or heading to the tile
	for g in occupancy_groups:
		for n in get_tree().get_nodes_in_group(g):
			if n == self:
				continue
			# If the node has a global_position, compare; otherwise skip
			if n is Node2D:
				var npos: Vector2 = n.global_position
				if npos.distance_to(tile_pos) < occupy_check_radius:
					return true
	# Also check reservations
	var k = _tile_key(tile_pos)
	if _reserved_tiles.has(k) and _reserved_tiles[k] != self:
		return true
	return false

func _exit_tree() -> void:
	# Ensure we release any reservation if freed
	release_reserved_tile()
