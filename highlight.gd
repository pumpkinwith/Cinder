extends TileMapLayer

signal tile_clicked(tile_pos: Vector2i)

@export var player_node_path: NodePath = NodePath("")   # set to Player node in inspector (optional)
@export var ground_map_path: NodePath = NodePath("")    # set to the ground TileMap layer
@export var available_tile_id: int = 0                  # blue highlight tile id
@export var unavailable_tile_id: int = 1                # red highlight tile id
@export var autotile_coord: Vector2i = Vector2i(0, 0)   # autotile coord used in set_cell

@export var tile_origin_offset: Vector2 = Vector2(0, -8) # match TileSet texture_origin (same as Player)
@export var debug: bool = false

@onready var player_node: Node = null
@onready var ground_map: TileMapLayer = null

func _ready():
	# try explicit path first, otherwise try to find a sibling named "Player"
	if player_node_path != NodePath(""):
		player_node = get_node_or_null(player_node_path)
	if player_node == null and get_parent():
		player_node = get_parent().get_node_or_null("Player")

	# find ground_map robustly
	ground_map = _find_ground_map()

	if ground_map == null:
		push_warning("[highlight] Ground map not found. Void detection will not work.")
		return

func _find_ground_map() -> Node:
	# 1) Explicit inspector path
	if ground_map_path != NodePath(""):
		var n = get_node_or_null(ground_map_path)
		if n:
			return n

	# 2) Sibling called "Ground"
	if get_parent():
		var s = get_parent().get_node_or_null("Ground")
		if s:
			return s

	# 3) find_node by name anywhere
	var by_name = get_tree().get_root().find_node("Ground", true, false)
	if by_name:
		return by_name

	# 4) Fallback: find first node that looks like a TileMap/TileMapLayer
	var root = get_tree().get_root()
	var q = [root]
	while not q.empty():
		var n = q.pop_front()
		# Skip self
		if n == self:
			for c in n.get_children():
				q.push_back(c)
			continue
		# Heuristic: has tilemap-like API
		if n.has_method("get_used_rect") and n.has_method("get_cell_source_id"):
			return n
		for c in n.get_children():
			q.push_back(c)
	return null

func _process(_delta):
	var mouse_global = get_global_mouse_position()
	# Mouse mapping should NOT use sprite origin offset
	var tile_pos: Vector2i = local_to_map(to_local(mouse_global))
	if debug:
		if player_node:
			var player_tile_dbg: Vector2i = local_to_map(to_local(player_node.global_position - tile_origin_offset))
			print_debug("[highlight] hover mouse=", mouse_global, " tile=", tile_pos, " player=", player_node.global_position, " player_tile=", player_tile_dbg)
		else:
			print_debug("[highlight] hover mouse=", mouse_global, " tile=", tile_pos, " player=null")

	clear() # clear previous highlight

	var is_on_ground = true
	if ground_map:
		is_on_ground = ground_map.get_cell_source_id(tile_pos) != -1

	var tile_id = available_tile_id if is_on_ground else unavailable_tile_id
	set_cell(tile_pos, tile_id, autotile_coord)

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Mouse mapping should NOT use sprite origin offset
		var tile_pos: Vector2i = local_to_map(to_local(get_global_mouse_position()))

		var can_click = true
		if ground_map:
			can_click = ground_map.get_cell_source_id(tile_pos) != -1

		if can_click:
			if debug:
				var dbg_player_tile: Vector2i = local_to_map(to_local(player_node.global_position - tile_origin_offset)) if player_node else Vector2i(0, 0)
				var dbg_dx: int = tile_pos.x - dbg_player_tile.x
				var dbg_dy: int = tile_pos.y - dbg_player_tile.y
				print_debug("[highlight] click tile=", tile_pos, " player_tile=", dbg_player_tile, " dx/dy=", Vector2i(dbg_dx, dbg_dy))
			emit_signal("tile_clicked", tile_pos)
