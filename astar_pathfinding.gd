extends Node

## A* pathfinding for isometric tile-based grid
## Handles 4-directional movement with wall collision detection

class_name AStarPathfinding

var tile_size: Vector2
var open_set: Array[Vector2] = []
var closed_set: Array[Vector2] = []
var came_from: Dictionary = {}  # String -> Vector2
var g_score: Dictionary = {}    # String -> float
var f_score: Dictionary = {}    # String -> float

func _init(tile_sz: Vector2) -> void:
	tile_size = tile_sz

# Get walkable neighbors (4 directions)
func get_neighbors(pos: Vector2) -> Array[Vector2]:
	var neighbors: Array[Vector2] = []
	var directions = [
		Vector2(tile_size.x, tile_size.y),     # SE
		Vector2(-tile_size.x, -tile_size.y),   # NW
		Vector2(-tile_size.x, tile_size.y),    # SW
		Vector2(tile_size.x, -tile_size.y)     # NE
	]
	for dir in directions:
		neighbors.append(pos + dir)
	return neighbors

# Heuristic: Manhattan distance on isometric grid
func heuristic(pos_a: Vector2, pos_b: Vector2) -> float:
	var diff = (pos_b - pos_a).abs()
	return diff.x + diff.y

# Check if a tile is blocked (walls layer 1 or occupied by enemy/player)
func is_blocked(pos: Vector2, space_state, _excluded_bodies: Array) -> bool:
	# Check collision layer 1 (walls/barriers)
	var query = PhysicsPointQueryParameters2D.new()
	query.position = pos
	query.collision_mask = 1
	var wall_hit = space_state.intersect_point(query)
	if wall_hit.size() > 0:
		return true
	return false

# Find path from start to goal using A*
func find_path(start: Vector2, goal: Vector2, space_state, excluded_bodies: Array = []) -> Array:
	open_set.clear()
	closed_set.clear()
	came_from.clear()
	g_score.clear()
	f_score.clear()
	
	var start_key = _vec_to_key(start)
	var goal_key = _vec_to_key(goal)
	
	open_set.append(start)
	g_score[start_key] = 0.0
	f_score[start_key] = heuristic(start, goal)
	
	while open_set.size() > 0:
		# Find node with lowest f_score
		var current = open_set[0]
		var current_idx = 0
		var current_key = _vec_to_key(current)
		
		for i in range(open_set.size()):
			var key = _vec_to_key(open_set[i])
			if f_score.get(key, INF) < f_score.get(current_key, INF):
				current = open_set[i]
				current_idx = i
				current_key = key
		
		# Goal reached
		if current_key == goal_key:
			return _reconstruct_path(came_from, current)
		
		open_set.remove_at(current_idx)
		closed_set.append(current)
		
		for neighbor in get_neighbors(current):
			var neighbor_key = _vec_to_key(neighbor)
			
			# Skip if already evaluated or blocked
			if closed_set.has(neighbor) or is_blocked(neighbor, space_state, excluded_bodies):
				continue
			
			var tentative_g = g_score.get(_vec_to_key(current), INF) + tile_size.length()
			
			if not open_set.has(neighbor):
				open_set.append(neighbor)
			elif tentative_g >= g_score.get(neighbor_key, INF):
				continue
			
			# Better path found
			came_from[neighbor_key] = current
			g_score[neighbor_key] = tentative_g
			f_score[neighbor_key] = tentative_g + heuristic(neighbor, goal)
	
	return []  # No path found

func _reconstruct_path(parent_map: Dictionary, current: Vector2) -> Array:
	var path = [current]
	var current_key = _vec_to_key(current)
	
	while parent_map.has(current_key):
		current = parent_map[current_key]
		current_key = _vec_to_key(current)
		path.insert(0, current)
	
	return path

func _vec_to_key(vec: Vector2) -> String:
	return "%.0f,%.0f" % [vec.x, vec.y]
