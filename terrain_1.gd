extends TileMapLayer

## Terrain level 1 - elevated platform layer
## Tile size: 8 (width) x 16 (height) in isometric view

const BOUNDARY_ATLAS_POS: Vector2i = Vector2i(1, 3)  # Tile with collision polygon
const MAIN_SOURCE: int = 1
const ELEVATION_LEVEL: float = 1.0

var terrain_0: TileMapLayer = null
var terrain_2: TileMapLayer = null

func _ready() -> void:
	# Get references to other terrain layers
	var parent = get_parent()
	if parent:
		terrain_0 = parent.get_node_or_null("Terrain 0")
		terrain_2 = parent.get_node_or_null("Terrain 2")
	place_boundaries()

func place_boundaries() -> void:
	var offsets = [
		Vector2i(0, -1),
		Vector2i(0, 1),
		Vector2i(1, 0),
		Vector2i(-1, 0),
	]
	
	# First, collect only the non-boundary tiles (actual ground tiles)
	var ground_tiles: Array[Vector2i] = []
	var used = get_used_cells()
	for cell in used:
		var atlas_coords = get_cell_atlas_coords(cell)
		# Skip if this is already a boundary tile
		if atlas_coords != BOUNDARY_ATLAS_POS:
			ground_tiles.append(cell)
	
	# Then place boundaries only around ground tiles
	for spot in ground_tiles:
		# Skip boundary placement if this tile is an elevation transition on ANY layer
		if _is_elevation_tile_on_any_layer(spot):
			continue
		
		for offset in offsets:
			var current_spot = spot + offset
			# This spot is empty - place boundary
			if get_cell_source_id(current_spot) == -1:
				# Don't place boundary if it would block an elevation tile on any layer
				var blocks_elevation = false
				for check_offset in offsets:
					var check_spot = current_spot + check_offset
					if _is_elevation_tile_on_any_layer(check_spot):
						blocks_elevation = true
						break
				
				if not blocks_elevation:
					set_cell(current_spot, MAIN_SOURCE, BOUNDARY_ATLAS_POS)

func get_elevation() -> float:
	return ELEVATION_LEVEL

func has_tile_at(world_pos: Vector2) -> bool:
	var tile_coords = local_to_map(to_local(world_pos))
	var source_id = get_cell_source_id(tile_coords)
	return source_id != -1

func get_tile_coords(world_pos: Vector2) -> Vector2i:
	"""Convert world position to tile coordinates"""
	return local_to_map(to_local(world_pos))

func get_world_pos(tile_coords: Vector2i) -> Vector2:
	"""Convert tile coordinates to world position"""
	return to_global(map_to_local(tile_coords))

func get_move_step() -> Vector2:
	"""Tile step size in world units for one isometric-grid move."""
	if tile_set:
		return Vector2(tile_set.tile_size.x * 0.5, tile_set.tile_size.y * 0.5)
	return Vector2(8, 4)

func _is_elevation_tile(tile_coords: Vector2i) -> bool:
	"""Check if a tile is marked as an elevation transition on THIS layer"""
	var tile_data = get_cell_tile_data(tile_coords)
	if not tile_data:
		return false
	var elevation_value = tile_data.get_custom_data("Elevation Tile")
	if elevation_value is bool:
		return elevation_value
	return false

func _is_elevation_tile_on_any_layer(tile_coords: Vector2i) -> bool:
	"""Check if a tile is marked as elevation transition on ANY terrain layer"""
	# Check terrain_1 (this layer)
	if _is_elevation_tile(tile_coords):
		return true
	
	# Check terrain_2
	if terrain_2:
		var tile_data_2 = terrain_2.get_cell_tile_data(tile_coords)
		if tile_data_2:
			var elevation_value = tile_data_2.get_custom_data("Elevation Tile")
			if elevation_value is bool and elevation_value:
				return true
	
	# Check terrain_0
	if terrain_0:
		var tile_data_0 = terrain_0.get_cell_tile_data(tile_coords)
		if tile_data_0:
			var elevation_value = tile_data_0.get_custom_data("Elevation Tile")
			if elevation_value is bool and elevation_value:
				return true
	
	return false
