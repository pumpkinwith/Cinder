extends AnimatedSprite2D

## Start button with hover animations and fire reveal effect
## Controlled by title_screen.gd for reveal sequence

const DEFAULT_HIT_SIZE: Vector2 = Vector2(64, 64)

@export var hit_padding: Vector2 = Vector2(6, 4)
@export var hit_size: Vector2 = Vector2.ZERO
@export var open_anim: String = "Start_Open"
@export var close_anim: String = "Start_Closed"
@export var idle_anim: String = "Start"

var interaction_enabled: bool = false
var is_hovered: bool = false
var _closing: bool = false

func _ready() -> void:
    # Start hidden - title_screen will reveal us
    modulate.a = 0.0
    
    # Play idle animation initially
    if sprite_frames and sprite_frames.has_animation(idle_anim):
        play(idle_anim)
    
    # Ensure open and close animations don't loop
    if sprite_frames:
        if sprite_frames.has_animation(open_anim):
            sprite_frames.set_animation_loop(open_anim, false)
        if sprite_frames.has_animation(close_anim):
            sprite_frames.set_animation_loop(close_anim, false)
    
    # Connect animation signals
    if has_signal("animation_finished"):
        animation_finished.connect(_on_animation_finished)

func _process(_delta: float) -> void:
    if not interaction_enabled:
        return
    
    var mouse_pos: Vector2 = get_global_mouse_position()
    
    # Calculate clickable area
    var size := hit_size
    if size == Vector2.ZERO and sprite_frames:
        var anim_name: String = str(animation) if animation != "" else idle_anim
        if sprite_frames.has_animation(anim_name) and sprite_frames.get_frame_count(anim_name) > 0:
            var tex := sprite_frames.get_frame_texture(anim_name, 0)
            if tex:
                size = tex.get_size() * scale
    # Handle hover state
    var was_hovered: bool = is_hovered
    var visible_enough: bool = modulate.a > 0.1
    var rect := Rect2(global_position - size / 2, size)
    is_hovered = visible_enough and rect.has_point(mouse_pos)
    
    if is_hovered and not was_hovered:
        # Enter hover - play open animation once
        if sprite_frames and sprite_frames.has_animation(open_anim):
            play(open_anim)
        _closing = false
    elif not is_hovered and was_hovered:
        # Exit hover - play close animation once, then return to idle
        if sprite_frames and sprite_frames.has_animation(close_anim):
            play(close_anim)
            _closing = true
        else:
            # No close animation - go straight to idle
            if sprite_frames and sprite_frames.has_animation(idle_anim):
                play(idle_anim)
            _closing = false

func _on_animation_finished() -> void:
    # When close animation finishes, return to idle
    if _closing and animation == close_anim:
        if sprite_frames and sprite_frames.has_animation(idle_anim):
            play(idle_anim)
        _closing = false

func _input(event: InputEvent) -> void:
    if not interaction_enabled:
        return
    
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if is_hovered:
            # Notify parent to start transition
            var parent := get_parent()
            if parent and parent.has_method("_on_start_pressed"):
                parent._on_start_pressed()
