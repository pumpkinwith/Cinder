extends TileMapLayer

## Ground level terrain - handles all tile and boundary checking
## Tile size: 8 (width) x 16 (height) in isometric view

const MAIN_SOURCE_ID: int = 1
const BOUNDARY_ATLAS_POS: Vector2i = Vector2i(1, 3)
const TILE_STEP: Vector2 = Vector2(8, 16)

func _ready() -> void:
	place_boundaries()

func has_tile_at(world_pos: Vector2) -> bool:
	"""Check if a tile exists at the given world position"""
	var tile_coords = local_to_map(to_local(world_pos))
	var source_id = get_cell_source_id(tile_coords)
	return source_id != -1

func can_move_to(world_pos: Vector2) -> bool:
	"""Check if player can move to this world position"""
	var tile_coords = get_tile_coords(world_pos)
	var source_id = get_cell_source_id(tile_coords)
	if source_id == -1:
		return false
	var tile_data = get_cell_tile_data(tile_coords)
	if tile_data:
		for layer_id in range(tile_set.get_physics_layers_count()):
			if tile_data.get_collision_polygons_count(layer_id) > 0:
				return false
	return true

func place_boundaries() -> void:
	var offsets = [
		Vector2i(0, -1),
		Vector2i(0, 1),
		Vector2i(1, 0),
		Vector2i(-1, 0)
	]
	var used = get_used_cells()
	for cell in used:
		for offset in offsets:
			var edge = cell + offset
			if get_cell_source_id(edge) == -1:
				set_cell(edge, MAIN_SOURCE_ID, BOUNDARY_ATLAS_POS)

func get_tile_coords(world_pos: Vector2) -> Vector2i:
	"""Convert world position to tile coordinates"""
	return local_to_map(to_local(world_pos))

func get_world_pos(tile_coords: Vector2i) -> Vector2:
	"""Convert tile coordinates to world position"""
	return to_global(map_to_local(tile_coords))

func get_move_step() -> Vector2:
	"""Tile step size for movement on this layer"""
	return TILE_STEP
