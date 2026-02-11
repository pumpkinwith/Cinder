extends Area2D

## Hit box for player attacks - handles damage calculation, criticals, and knockback
## Connects to hurt boxes on enemies to apply damage

# Attack properties
@export_group("Damage")
@export var base_damage: float = 15.0
@export var base_crit_chance: float = 0.05
@export var combo_crit_increase: float = 0.01
@export var max_crit_chance: float = 0.65

@export_group("Knockback")
@export var knockback_strength: float = 200.0
@export var facing_threshold: float = 0.5  # Minimum dot product for valid hits (0=any, 1=exact)

@export_group("References")
@export var crit_sound: AudioStreamPlayer2D
@export var source: Node2D  # The attacking character (usually player)

# Constants
const CRIT_DAMAGE_MULTIPLIER: float = 2.0
const HIT_SOUND_DELAY: float = 0.04
const CRIT_SOUND_DELAY: float = 0.02

# State
var combo_count: int = 0
var current_crit_chance: float = 0.15
var current_direction: String = "SE"

func _ready() -> void:
	# Auto-assign source to parent if not set
	if source == null:
		source = get_parent()
		if source == null:
			push_error("[hit_box] No source found for %s" % name)
	
	# Connect area entered signal
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	
	# Start disabled
	monitoring = false

func start_attack(direction: String) -> void:
	"""Begin attack in specified direction, incrementing combo"""
	current_direction = direction
	combo_count += 1
	current_crit_chance = min(base_crit_chance + combo_count * combo_crit_increase, max_crit_chance)
	monitoring = true

func stop_attack() -> void:
	"""End attack and disable monitoring"""
	monitoring = false
	# Don't reset combo on stop - let it persist for chain attacks

func reset_combo() -> void:
	"""Reset combo counter (call when combo breaks)"""
	combo_count = 0
	current_crit_chance = base_crit_chance

func _on_area_entered(area: Area2D) -> void:
	"""Handle area entered during active attack"""
	if not monitoring:
		return
	if not area.has_method("apply_hit"):
		return
	_handle_hit_for_area(area)


func _handle_hit_for_area(area: Area2D) -> void:
	if not area.has_method("apply_hit"):
		return

	# Don't hit the source (self) or non-enemy targets.
	var target_owner := area.get_parent()
	if target_owner == null:
		return
	if source and target_owner == source:
		return
	if not target_owner.is_in_group("enemy"):
		return

	var is_critical: bool = randf() < current_crit_chance
	var damage: float = float(base_damage)
	if is_critical:
		damage *= 2.0

	var knockback_dir: Vector2 = _dir_from_string(current_direction)

	# Ensure the target is in the direction the attacker is facing
	var src_node := source if source != null else get_parent()
	if src_node and src_node is Node2D:
		var to_target: Vector2 = (target_owner.global_position - src_node.global_position).normalized()
		var face_dir := _dir_from_string(current_direction)
		# Use stricter threshold - only hit targets clearly in front (60 degree cone)
		if face_dir.dot(to_target) < 0.5:  # cos(60°) = 0.5
			return

	area.apply_hit({
		"damage": damage,
		"is_critical": is_critical,
		"knockback_dir": knockback_dir,
		"knockback": knockback_strength,
		"source": source
	})

	# Play sounds immediately without await to avoid combat lag
	# Sound effects are fired asynchronously for instant feedback
	if source:
		if source.has_node("AttackVoiceSound"):
			var hit_sfx = source.get_node("AttackVoiceSound")
			if hit_sfx and hit_sfx.has_method("play"):
				hit_sfx.play()
		elif source.has_node("HitSound"):
			var hit_sfx = source.get_node("HitSound")
			if hit_sfx and hit_sfx.has_method("play"):
				hit_sfx.play()

	# On critical hits: play crit sound immediately
	if is_critical:
		var played: bool = false
		if source:
			var cs1 = source.get_node_or_null("Crit")
			if cs1 and cs1.has_method("play"):
				cs1.play()
				played = true
			else:
				var cs2 = source.get_node_or_null("CritSound")
				if cs2 and cs2.has_method("play"):
					cs2.play()
					played = true

		# Fallback to this hitbox's exported crit_sound
		if not played and crit_sound and crit_sound.has_method("play"):
			crit_sound.play()

	# Show damage text
	if source and source.has_method("spawn_damage_text"):
		var hit_pos: Vector2 = target_owner.global_position
		source.spawn_damage_text(damage, is_critical, hit_pos)

	# Trigger camera shake
	if source and source.has_method("trigger_camera_shake"):
		source.trigger_camera_shake(2.0)




func _dir_from_string(dir: String) -> Vector2:
	match dir:
		"NE": return Vector2(1, -1).normalized()
		"SE": return Vector2(1, 1).normalized()
		"SW": return Vector2(-1, 1).normalized()
		"NW": return Vector2(-1, -1).normalized()
	return Vector2.ZERO
