extends AnimatedSprite2D

const ANIM_FULL: StringName = &"Full"
const ANIM_DAMAGED: StringName = &"Damaged"
const ANIM_CRITICAL: StringName = &"Critical"
const ANIM_FATAL: StringName = &"Fatal"
const ANIM_DEAD: StringName = &"Dead"

var _player: Node = null
@onready var fire_light: PointLight2D = get_node_or_null("PointLight2D")
@export var min_light_energy: float = 0.0
var _base_light_energy: float = 1.0

func _ready() -> void:
	if fire_light:
		_base_light_energy = fire_light.energy
	call_deferred("_bind_player")
	# Safe fallback state before first health sync.
	_set_health_anim(1, 1)

func _bind_player() -> void:
	if _player and is_instance_valid(_player):
		return
	
	_player = get_tree().get_first_node_in_group("player")
	if not _player:
		await get_tree().process_frame
		_player = get_tree().get_first_node_in_group("player")
	if not _player:
		return
	
	if _player.has_signal("health_changed"):
		var callable := Callable(self, "_on_player_health_changed")
		if not _player.is_connected("health_changed", callable):
			_player.connect("health_changed", callable)
	
	if _player.has_signal("died"):
		var died_callable := Callable(self, "_on_player_died")
		if not _player.is_connected("died", died_callable):
			_player.connect("died", died_callable)
	
	var current_health_value: Variant = _player.get("health")
	var max_health_value: Variant = _player.get("max_health")
	var current_health: int = int(current_health_value) if current_health_value != null else 1
	var max_health: int = int(max_health_value) if max_health_value != null else max(current_health, 1)
	_set_health_anim(current_health, max_health)

func _on_player_health_changed(new_health: int, max_health: int) -> void:
	_set_health_anim(new_health, max_health)

func _on_player_died() -> void:
	if sprite_frames and sprite_frames.has_animation(ANIM_DEAD):
		if animation != ANIM_DEAD:
			play(ANIM_DEAD)
	_update_fire_light(0.0)

func _set_health_anim(current_health: int, max_health: int) -> void:
	var safe_max: int = maxi(max_health, 1)
	var clamped_health: int = clampi(current_health, 0, safe_max)
	var health_ratio: float = float(clamped_health) / float(safe_max)
	
	var next_anim: StringName = ANIM_FULL
	if clamped_health <= 0 and sprite_frames and sprite_frames.has_animation(ANIM_DEAD):
		next_anim = ANIM_DEAD
	elif health_ratio <= 0.25:
		next_anim = ANIM_FATAL
	elif health_ratio <= 0.50:
		next_anim = ANIM_CRITICAL
	elif health_ratio <= 0.75:
		next_anim = ANIM_DAMAGED
	
	if sprite_frames and sprite_frames.has_animation(next_anim):
		if animation != next_anim:
			play(next_anim)
	
	_update_fire_light(health_ratio)

func _update_fire_light(health_ratio: float) -> void:
	if not fire_light:
		return
	var ratio: float = clampf(health_ratio, 0.0, 1.0)
	fire_light.energy = lerpf(min_light_energy, _base_light_energy, ratio)
