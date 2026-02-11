extends Area2D

## Hurt box that receives damage from hit boxes
## Processes hits and forwards damage to the owning character

@export_group("Character")
@export var character_owner: Node2D  # The character that owns this hurt box
@export var invincible: bool = false  # Temporary invincibility

@export_group("Resistance")
@export var resistance: Dictionary = {
	"physical": 1.0  # Damage multiplier (1.0 = normal, 0.5 = half damage)
}

func _ready() -> void:
	if character_owner == null:
		character_owner = get_parent()
		if character_owner == null:
			push_error("[hurt_box] No character owner found for %s" % name)

func apply_hit(hit_data: Dictionary) -> void:
	"""Process incoming hit and forward to character owner"""
	if invincible:
		return
	
	if not character_owner:
		push_error("[hurt_box] Cannot apply hit - no character owner")
		return
	
	if not character_owner.has_method("take_damage"):
		push_error("[hurt_box] Character owner %s does not have take_damage method" % character_owner.name)
		return

	# Extract hit data with safe defaults
	var damage: float = float(hit_data.get("damage", 0))
	var knockback_amount: float = float(hit_data.get("knockback", 0))
	var knockback_dir: Vector2 = hit_data.get("knockback_dir", Vector2.ZERO)
	var source_node: Node = hit_data.get("source", null)
	var is_critical: bool = hit_data.get("is_critical", false)

	# Apply resistance
	var damage_type: String = hit_data.get("type", "physical")
	if resistance.has(damage_type):
		damage *= resistance[damage_type]

	# Calculate knockback direction from source if not provided
	if knockback_dir == Vector2.ZERO and source_node is Node2D and character_owner is Node2D:
		knockback_dir = (character_owner.global_position - source_node.global_position).normalized()

	# Forward to character with signature: (knockback_vector, damage, is_critical)
	character_owner.take_damage(knockback_dir * knockback_amount, damage, is_critical)

