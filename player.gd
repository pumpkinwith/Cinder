extends CharacterBody2D

@export var highlight_path: NodePath = NodePath("")           # optional, otherwise it falls back to ../Highlight
@export var ground_map_path: NodePath = NodePath("")          # set to the ground TileMap layer
@export var move_speed: float = 125.0                        # pixels/sec
@export var sprint_multiplier: float = 1.5                   # speed multiplier when holding Shift
@export var snap_threshold: float = 2.0                      # pixels to snap to tile
@export var tile_origin_offset: Vector2 = Vector2(0, -8)     # match TileSet texture_origin

@onready var highlight: Node = null
@onready var ground_map: TileMapLayer = null

var is_moving: bool = false
var target_global_pos: Vector2 = Vector2.ZERO
var path: Array[Vector2i] = []
var astar_grid: AStarGrid2D = AStarGrid2D.new()

func _find_ground_map() -> Node:
	# 1) Explicit inspector path
	if ground_map_path != NodePath(""):
		var n = get_node_or_null(ground_map_path)
		if n:
			return n

	# 2) Sibling of highlight or sibling in parent called "Ground"
	if highlight and highlight.get_parent():
		var s = highlight.get_parent().get_node_or_null("Ground")
		if s:
			return s
	if get_parent():
		var s2 = get_parent().get_node_or_null("Ground")
		if s2:
			return s2

	# 3) find_node by name anywhere
	var by_name = get_tree().get_root().find_node("Ground", true, false)
	if by_name:
		return by_name

	# 4) Fallback: find first node that looks like a TileMap/TileMapLayer
	var root = get_tree().get_root()
	var q = [root]
	while not q.empty():
		var n = q.pop_front()
		if n == self:
			for c in n.get_children():
				q.push_back(c)
			continue
		if n.has_method("get_used_rect") and n.has_method("get_cell_source_id"):
			return n
		for c in n.get_children():
			q.push_back(c)
	return null

func _ready() -> void:
	if highlight_path != NodePath(""):
		highlight = get_node_or_null(highlight_path)
	if highlight == null and get_parent():
		highlight = get_parent().get_node_or_null("Highlight")

	# --- Robust Ground Map Finding ---
	# Use helper to locate ground_map in several ways
	ground_map = _find_ground_map()

	if ground_map == null:
		push_warning("Ground map not found; pathfinding will be disabled. Ensure 'ground_map_path' is set in inspector or a TileMapLayer is named 'Ground'.")
		return

	# Setup AStarGrid2D based on the ground map's actual dimensions
	var map_rect = ground_map.get_used_rect()
	astar_grid.region = map_rect
	astar_grid.cell_size = ground_map.tile_set.tile_size
	astar_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar_grid.update() # This initializes the grid as fully walkable.

	# Now, mark non-existent tiles as solid (unwalkable)
	for x in range(map_rect.position.x, map_rect.end.x):
		for y in range(map_rect.position.y, map_rect.end.y):
			var cell = Vector2i(x, y)
			if ground_map.get_cell_source_id(cell) == -1: # Check if tile exists at cell
				astar_grid.set_point_solid(cell)

func _physics_process(delta: float) -> void:
	if is_moving:
		var current_speed = move_speed
		if Input.is_key_pressed(Key.KEY_SHIFT):
			current_speed *= sprint_multiplier
		
		global_position = global_position.move_toward(target_global_pos, current_speed * delta)
		if global_position.distance_to(target_global_pos) <= snap_threshold:
			global_position = target_global_pos
			is_moving = false
			# If there are more points in the path, move to the next one
			if not path.is_empty():
				_move_to_next_tile()
	
func _move_to_next_tile():
	if not path.is_empty():
		var next_tile_pos = path[0]
		path.pop_front()
		if highlight == null:
			push_warning("Highlight node not available for position conversion.")
			return
		target_global_pos = highlight.to_global(highlight.map_to_local(next_tile_pos) + tile_origin_offset)
		is_moving = true

func _on_tile_clicked(tile_pos: Vector2i) -> void:
	# need highlight map to convert cells consistently
	var map_node := highlight
	if map_node == null:
		push_warning("Highlight node not available.")
		return

	# If pathfinding is not configured, do nothing.
	if ground_map == null:
		push_warning("Ground map not found, cannot pathfind.")
		return

	# Check if the target tile is within the AStar grid bounds
	if not astar_grid.region.has_point(tile_pos):
		return

	# player's current cell (in the same coordinate space as highlight)
	var player_tile: Vector2i = map_node.local_to_map(map_node.to_local(global_position - tile_origin_offset))
	# if clicked same tile, do nothing
	if tile_pos == player_tile:
		return

	# Check if the player tile is within the AStar grid bounds
	if not astar_grid.region.has_point(player_tile):
		return

	# Find a path from player's current tile to the clicked tile
	path = astar_grid.get_id_path(player_tile, tile_pos)

	if not path.is_empty():
		path.pop_front() # remove the starting point (player's current tile)
		_move_to_next_tile()


func _sign_i(v: int) -> int:
	if v > 0:
		return 1
	if v < 0:
		return -1
	return 0
