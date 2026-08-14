extends CanvasLayer

@onready var rect = $ColorRect


func _ready():
	rect.material.set_shader_parameter("progress", 0.0)


func set_progress(value: float):
	rect.material.set_shader_parameter("progress", value)


func play_implosion(world_target_position: Vector2, duration: float = 1.4):
	var screen_uv = _get_screen_uv(world_target_position)
	rect.material.set_shader_parameter("center", screen_uv)
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	await tween.tween_property(rect.material, "shader_parameter/progress", 1.0, duration).finished


func play_expansion(world_target_position: Vector2, duration: float = 0.8):
	var screen_uv = _get_screen_uv(world_target_position)
	rect.material.set_shader_parameter("center", screen_uv)
	var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await tween.tween_property(rect.material, "shader_parameter/progress", 0.0, duration).finished


func _get_screen_uv(world_pos: Vector2) -> Vector2:
	var canvas_transform = get_viewport().get_canvas_transform()
	var screen_pixel_pos = canvas_transform * world_pos
	var screen_size = get_viewport().get_visible_rect().size
	return Vector2(
		clamp(screen_pixel_pos.x / screen_size.x, 0.0, 1.0),
		clamp(screen_pixel_pos.y / screen_size.y, 0.0, 1.0),
	)
