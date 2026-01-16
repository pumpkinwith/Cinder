extends Node

@export var color_rect_path: NodePath
@export var player_path: NodePath
@export var camera_path: NodePath

var color_rect: ColorRect
var player: Node2D
var camera: Camera2D

func _ready():
    # Resolve nodes with fallbacks
    if color_rect_path and has_node(color_rect_path):
        color_rect = get_node(color_rect_path)
    else:
        # find first ColorRect in tree
        color_rect = get_tree().get_root().find_node("ColorRect", true, false)

    if player_path and has_node(player_path):
        player = get_node(player_path)
    else:
        # try group 'player' first
        var players = get_tree().get_nodes_in_group("player")
        if players.size() > 0:
            player = players[0]
        else:
            player = get_tree().get_root().find_node("Player", true, false)

    if camera_path and has_node(camera_path):
        camera = get_node(camera_path)
    else:
        camera = player.get_node_or_null("Camera2D") if player else null
        if not camera:
            camera = get_tree().get_root().find_node("Camera2D", true, false)

func _process(_delta):
    if not color_rect or not color_rect.material:
        return
    var mat = color_rect.material
    if not (mat is ShaderMaterial):
        return

    if player:
        mat.set_shader_parameter("player_world_pos", player.global_position)
    if camera:
        mat.set_shader_parameter("camera_world_pos", camera.global_position)
        mat.set_shader_parameter("camera_zoom", camera.zoom)

    var vs = get_viewport().get_visible_rect().size
    mat.set_shader_parameter("viewport_size", vs)

    # Optional: tweak default fog radius/falloff if desired
    # mat.set_shader_parameter("fog_player_radius", 0.15)
    # mat.set_shader_parameter("fog_player_falloff", 0.2)
