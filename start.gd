extends AnimatedSprite2D

var is_hovered: bool = false
var has_opened: bool = false
var interaction_enabled: bool = false

func _ready() -> void:
	centered = true
	
	# Set animations to not loop
	if sprite_frames:
		sprite_frames.set_animation_loop("Start Opening", false)
		sprite_frames.set_animation_loop("Start Closing", false)
	
	# Start with last frame of closing animation visible
	if sprite_frames and sprite_frames.has_animation("Start Closing"):
		animation = "Start Closing"
		frame = sprite_frames.get_frame_count("Start Closing") - 1
		stop()
	
	animation_finished.connect(_on_animation_finished)

func _process(_delta: float) -> void:
	var mouse_pos = get_global_mouse_position()
	
	# Get sprite texture size
	var texture_size = Vector2.ZERO
	if sprite_frames and sprite_frames.has_animation(animation):
		var texture = sprite_frames.get_frame_texture(animation, frame)
		if texture:
			texture_size = texture.get_size()
	
	# Calculate sprite rect considering scale and centered
	var sprite_rect = Rect2(global_position - (texture_size * scale / 2), texture_size * scale)
	
	var was_hovered = is_hovered
	is_hovered = sprite_rect.has_point(mouse_pos)
	
	# Play animation on hover state change
	if is_hovered and not was_hovered:
		has_opened = false
		play("Start Opening")
	elif not is_hovered and was_hovered:
		play("Start Closing")

func _on_animation_finished() -> void:
	# Freeze on last frame when animation finishes
	if animation == "Start Opening":
		has_opened = true
		stop()
		frame = sprite_frames.get_frame_count("Start Opening") - 1
	elif animation == "Start Closing":
		stop()
		frame = sprite_frames.get_frame_count("Start Closing") - 1


func _input(event: InputEvent) -> void:
	if not interaction_enabled:
		return
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_hovered:
			print("Start button clicked!")
			# Call custom burnout transition on title screen
			var title_screen = get_tree().current_scene
			if title_screen and title_screen.has_method("_start_burnout_transition"):
				await title_screen._start_burnout_transition()
				get_tree().change_scene_to_file("res://Tutorial Land.tscn")
			else:
				get_tree().change_scene_to_file("res://Tutorial Land.tscn")
