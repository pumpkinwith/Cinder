extends Area2D

## Ted-specific hurt box that receives attacks from hit boxes
## Routes damage to parent Ted enemy using apply_hit method

@export var character_owner: Node = null
@export var invincible: bool = false

func _ready() -> void:
	if character_owner == null:
		character_owner = get_parent()

func apply_hit(hit_data: Dictionary) -> void:
	"""Process incoming hit from player attack"""
	if invincible:
		return

	# Forward hit payload to Ted with consistent ordering: (knockback_direction, damage, is_critical)
	var damage: float = float(hit_data.get("damage", 0))
	var knockback_amount: float = float(hit_data.get("knockback", 0))
	var knockback_dir: Vector2 = hit_data.get("knockback_dir", Vector2.ZERO)
	var source_node: Node = hit_data.get("source", null)
	var is_critical: bool = hit_data.get("is_critical", false)

	# Calculate knockback direction from source if not provided
	if knockback_dir == Vector2.ZERO and source_node != null and character_owner is Node2D and source_node is Node2D:
		knockback_dir = (character_owner.global_position - source_node.global_position).normalized()

	if character_owner and character_owner.has_method("take_damage"):
		# Use consistent signature: (knockback_direction, damage, is_critical)
		character_owner.take_damage(knockback_dir * knockback_amount, damage, is_critical)
	else:
		push_error("Ted_hurt_box: Owner does not have take_damage method")
