extends RefCounted

## A* pathfinding for isometric tile-based grid
## Uses Dictionary lookups for O(1) membership tests instead of Array.has()

class_name AStarPathfinding

var tile_size: Vector2

# Pre-computed direction offsets (set once in _init)
var _directions: Array[Vector2] = []

func _init(tile_sz: Vector2) -> void:
	tile_size = tile_sz
	_directions = [
		Vector2(tile_sz.x, tile_sz.y),     # SE
		Vector2(-tile_sz.x, -tile_sz.y),   # NW
		Vector2(-tile_sz.x, tile_sz.y),    # SW
		Vector2(tile_sz.x, -tile_sz.y)     # NE
	]

## Find path from start to goal. Returns Array of Vector2 waypoints.
## max_distance limits search radius (in pixels) to prevent lag.
func find_path(start: Vector2, goal: Vector2, space_state, max_distance: float = 200.0) -> Array:
	# Early exit if goal is too far (prevents massive searches on tiny tiles)
	if start.distance_to(goal) > max_distance:
		return []

	# Use Dictionaries for O(1) lookups instead of Array.has() which is O(n)
	var open_dict: Dictionary = {}   # key -> Vector2
	var closed_dict: Dictionary = {} # key -> true
	var came_from: Dictionary = {}   # key -> Vector2
	var g_score: Dictionary = {}     # key -> float
	var f_score: Dictionary = {}     # key -> float

	var start_key := _key(start)
	var goal_key := _key(goal)

	open_dict[start_key] = start
	g_score[start_key] = 0.0
	f_score[start_key] = _heuristic(start, goal)

	var step_cost := tile_size.length()
	var iterations := 0

	while open_dict.size() > 0 and iterations < 500:
		iterations += 1

		# Find node with lowest f_score in open set
		var best_key: String = ""
		var best_f: float = INF
		for key in open_dict:
			var f: float = f_score.get(key, INF)
			if f < best_f:
				best_f = f
				best_key = key

		if best_key == goal_key:
			return _reconstruct(came_from, open_dict[best_key])

		var current: Vector2 = open_dict[best_key]
		open_dict.erase(best_key)
		closed_dict[best_key] = true

		# Check 4 neighbors
		for dir in _directions:
			var neighbor := current + dir
			var nkey := _key(neighbor)

			if closed_dict.has(nkey):
				continue

			# Skip tiles too far from goal (prune search space)
			if neighbor.distance_to(goal) > max_distance:
				continue

			# Check wall collision
			if _is_wall(neighbor, space_state):
				closed_dict[nkey] = true  # Mark as blocked so we don't re-check
				continue

			var tentative_g: float = g_score.get(best_key, INF) + step_cost

			if tentative_g < g_score.get(nkey, INF):
				came_from[nkey] = current
				g_score[nkey] = tentative_g
				f_score[nkey] = tentative_g + _heuristic(neighbor, goal)
				if not open_dict.has(nkey):
					open_dict[nkey] = neighbor

	return []  # No path found

func _heuristic(a: Vector2, b: Vector2) -> float:
	# Chebyshev distance in tile coordinates (better for 4-dir movement)
	var dx: float = abs((b.x - a.x) / tile_size.x)
	var dy: float = abs((b.y - a.y) / tile_size.y)
	return max(dx, dy)

func _is_wall(pos: Vector2, space_state) -> bool:
	if not space_state:
		return false
	var query := PhysicsPointQueryParameters2D.new()
	query.position = pos
	query.collision_mask = 1
	return space_state.intersect_point(query).size() > 0

func _reconstruct(came_from: Dictionary, current: Vector2) -> Array:
	var path: Array = [current]
	var key := _key(current)
	while came_from.has(key):
		current = came_from[key]
		key = _key(current)
		path.push_front(current)
	return path

func _key(v: Vector2) -> String:
	return "%d,%d" % [int(v.x), int(v.y)]
