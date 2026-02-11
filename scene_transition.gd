extends CanvasLayer

## Handles scene transitions with fade effects
## Manages special behavior for game over vs gameplay scenes

const OVERLAY_LAYER: int = 99

var fade_overlay: ColorRect

func _ready() -> void:
	# Create black overlay
	fade_overlay = ColorRect.new()
	fade_overlay.color = Color.BLACK
	fade_overlay.modulate.a = 0.0
	fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade_overlay)
	
	# Make it fill the entire viewport
	fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_overlay.anchor_left = 0.0
	fade_overlay.anchor_top = 0.0
	fade_overlay.anchor_right = 1.0
	fade_overlay.anchor_bottom = 1.0
	fade_overlay.offset_left = 0
	fade_overlay.offset_top = 0
	fade_overlay.offset_right = 0
	fade_overlay.offset_bottom = 0
	fade_overlay.grow_horizontal = Control.GROW_DIRECTION_BOTH
	fade_overlay.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	# Set layer below where player will be during reveal
	layer = OVERLAY_LAYER

func transition_to_scene(scene_path: String) -> void:
	"""Transition to a new scene with fade effect"""
	print("Starting transition to: ", scene_path)
	
	# Ensure overlay is ready
	if not fade_overlay:
		push_error("Fade overlay not initialized!")
		return
	
	# Check if this is the game over scene
	var is_game_over: bool = scene_path.to_lower().contains("gameover")
	
	# Fade to black
	print("Fading to black...")
	var tween: Tween = create_tween()
	tween.tween_property(fade_overlay, "modulate:a", 1.0, 0.5)
	await tween.finished
	print("Fade to black complete")
	
	# Change scene
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame
	
	if is_game_over:
		# For game over, fade out immediately to show the scene
		print("Game over scene - fading out black overlay...")
		if is_inside_tree():
			var fade_tween: Tween = create_tween()
			fade_tween.tween_property(fade_overlay, "modulate:a", 0.0, 0.8)
			await fade_tween.finished
	else:
		# Stay black and wait for player fire reveal to complete (3.5 seconds + buffer)
		print("Waiting for player fire reveal...")
		await get_tree().create_timer(3.7).timeout
		
		# Fade from black to reveal the scene
		print("Fading from black...")
		if is_inside_tree():
			var fade_tween: Tween = create_tween()
			fade_tween.tween_property(fade_overlay, "modulate:a", 0.0, 0.8)
	
	print("Transition complete")
