extends Node
## Script to set up realistic moonlight lighting system
## Attach this to your main scene node and it will configure lighting automatically

@export var ambient_darkness: Color = Color(0.15, 0.18, 0.28, 1.0)  # Dark blue-purple night
@export var enable_shadows: bool = true  # Moonlight casts soft shadows
@export var shadow_color: Color = Color(0.05, 0.08, 0.15, 0.6)  # Blue-tinted shadows
@export var moonlight_energy: float = 0.4  # Subtle moonlight
@export var moonlight_color: Color = Color(0.7, 0.8, 1.0)  # Cool silvery-blue
@export var use_directional_light: bool = true  # Use DirectionalLight2D for realistic moon

func _ready() -> void:
	setup_ambient_lighting()
	setup_moonlight()
	print("Moonlight system initialized")

func setup_ambient_lighting() -> void:
	"""Create CanvasModulate for ambient darkness if it doesn't exist"""
	var canvas_modulate = get_node_or_null("CanvasModulate")
	
	if not canvas_modulate:
		canvas_modulate = CanvasModulate.new()
		canvas_modulate.name = "CanvasModulate"
		add_child(canvas_modulate)
		print("Created CanvasModulate node")
	
	canvas_modulate.color = ambient_darkness
	print("Set ambient darkness to: ", ambient_darkness)

func setup_moonlight() -> void:
	"""Create realistic moonlight using DirectionalLight2D"""
	# Remove old point light if it exists
	var old_light = get_node_or_null("MainLight")
	if old_light:
		old_light.queue_free()
	
	if use_directional_light:
		# Create directional light for parallel moonlight rays
		var moon_light = DirectionalLight2D.new()
		moon_light.name = "MoonLight"
		add_child(moon_light)
		
		# Configure moonlight properties
		moon_light.energy = moonlight_energy
		moon_light.color = moonlight_color
		moon_light.blend_mode = Light2D.BLEND_MODE_ADD
		
		# Set angle - moon from upper-left (NW direction in isometric)
		# -45 degrees = light coming from top-left
		moon_light.rotation_degrees = -45
		
		# Configure soft shadows
		if enable_shadows:
			moon_light.shadow_enabled = true
			moon_light.shadow_color = shadow_color
			moon_light.shadow_filter = DirectionalLight2D.SHADOW_FILTER_PCF5
			moon_light.shadow_filter_smooth = 2.0
		
		print("Created DirectionalLight2D moonlight")
	else:
		# Fallback to point light
		var moon_light = PointLight2D.new()
		moon_light.name = "MoonLight"
		moon_light.position = Vector2(0, -100)  # High above
		add_child(moon_light)
		
		moon_light.energy = moonlight_energy * 1.5
		moon_light.color = moonlight_color
		moon_light.texture_scale = 10.0
		moon_light.blend_mode = Light2D.BLEND_MODE_ADD
		
		# Create gradient texture
		var gradient = Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		
		var gradient_texture = GradientTexture2D.new()
		gradient_texture.gradient = gradient
		gradient_texture.fill = GradientTexture2D.FILL_RADIAL
		gradient_texture.fill_from = Vector2(0.5, 0.5)
		gradient_texture.fill_to = Vector2(0.5, 0)
		
		moon_light.texture = gradient_texture
		
		if enable_shadows:
			moon_light.shadow_enabled = true
			moon_light.shadow_color = shadow_color
		
		print("Created PointLight2D moonlight (fallback)")


func create_point_light() -> PointLight2D:
	"""Create a PointLight2D with proper gradient texture"""
	var light = PointLight2D.new()
	
	# Create gradient texture for the light
	var gradient = Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))  # White center
	gradient.set_color(1, Color(1, 1, 1, 0))  # Transparent edges
	
	var gradient_texture = GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill = GradientTexture2D.FILL_RADIAL
	gradient_texture.fill_from = Vector2(0.5, 0.5)  # Center
	gradient_texture.fill_to = Vector2(0.5, 0)  # Radial to edge
	gradient_texture.width = 128
	gradient_texture.height = 128
	
	light.texture = gradient_texture
	light.texture_scale = 1.0
	light.blend_mode = Light2D.BLEND_MODE_ADD
	
	return light

func _input(event: InputEvent) -> void:
	"""Toggle between DirectionalLight2D and PointLight2D with F key"""
	if event.is_action_pressed("ui_focus_next"):  # F key
		use_directional_light = !use_directional_light
		setup_moonlight()
		print("Switched to ", "DirectionalLight2D" if use_directional_light else "PointLight2D")
