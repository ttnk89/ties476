extends Node2D

@export var star_count: int = 1600
@export var loop_boundary: Vector2 = Vector2(10000, 10000)

var stars = []
var ball: RigidBody2D
var camera: Camera2D


func _ready():
	await get_tree().process_frame

	ball = get_node("../Player")
	if not ball:
		printerr("ERROR: Could not find Player")
		return

	camera = ball.get_node("Camera2D")
	if not camera:
		printerr("ERROR: Could not find Camera2D")
		return

	for i in range(star_count):
		stars.append(
			{
				"rel_pos": Vector2(randf(), randf()),
				"speed_mult": randf_range(0.1, 0.9),
				"color": Color(
					randf_range(0.8, 1.0),
					randf_range(0.8, 1.0),
					1.0,
					randf_range(0.3, 0.7),
				),
			},
		)

	z_index = -100


func _process(_delta):
	if camera and ball:
		queue_redraw()


func _physics_process(_delta):
	if not ball:
		return
	_handle_seamless_wrap()


func _draw():
	var view_size = get_viewport_rect().size
	var cam_pos = camera.get_screen_center_position() if camera else Vector2.ZERO

	var cam_zoom = camera.zoom.x if camera else 1.0
	var zoom_comp = 1.0 / cam_zoom

	var screen_buffer = view_size * zoom_comp * 1.5
	var top_left = cam_pos - (screen_buffer / 2.0)

	for star in stars:
		var raw_x = (star.rel_pos.x * 100000.0) - (cam_pos.x * star.speed_mult)
		var raw_y = (star.rel_pos.y * 100000.0) - (cam_pos.y * star.speed_mult)

		var x = top_left.x + fposmod(raw_x, screen_buffer.x)
		var y = top_left.y + fposmod(raw_y, screen_buffer.y)

		var final_size = (1.0 if star.speed_mult < 0.6 else 2.0) * zoom_comp
		draw_rect(Rect2(Vector2(x, y), Vector2(final_size, final_size)), star.color)


func _handle_seamless_wrap():
	var pos = ball.global_position
	var offset = Vector2.ZERO

	if pos.x < 0:
		offset.x = loop_boundary.x
	elif pos.x > loop_boundary.x:
		offset.x = -loop_boundary.x
	if pos.y < 0:
		offset.y = loop_boundary.y
	elif pos.y > loop_boundary.y:
		offset.y = -loop_boundary.y

	if offset != Vector2.ZERO:
		var state = PhysicsServer2D.body_get_direct_state(ball.get_rid())
		if state:
			state.transform.origin += offset
			if camera:
				camera.reset_smoothing()

		var prey_nodes = get_tree().get_nodes_in_group("prey")
		for prey in prey_nodes:
			if prey is RigidBody2D:
				var prey_state = PhysicsServer2D.body_get_direct_state(prey.get_rid())
				if prey_state:
					prey_state.transform.origin += offset
			else:
				prey.global_position += offset
