extends TileMapLayer

## Boundaries now handled automatically by checking tile existence
## No need to place collision tiles!

func _ready() -> void:
	pass  # Boundary placement disabled - tile existence check is enough
