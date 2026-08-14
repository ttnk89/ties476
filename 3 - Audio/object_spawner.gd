extends Node2D

@export var prey_scene: PackedScene
@export var black_hole_scene: PackedScene

@export var min_spawn_dist: float = 1000.0
@export var max_spawn_dist: float = 3000.0
@export var max_prey: int = 50
@export var max_black_holes: int = 5
@export var spawn_interval: float = 0.5


func _ready():
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = spawn_interval
	timer.timeout.connect(_on_spawn_timer_timeout)
	timer.start()


func _on_spawn_timer_timeout():
	if get_tree().get_nodes_in_group("prey").size() < max_prey:
		_spawn_random_object(prey_scene)
	if get_tree().get_nodes_in_group("black_hole").size() < max_black_holes:
		_spawn_random_object(black_hole_scene)


func _spawn_random_object(scene: PackedScene):
	if scene == null:
		push_error("ERROR: Attempted to spawn an object with a null scene reference!")
		return

	var obj = scene.instantiate()

	var player = get_tree().get_first_node_in_group("player")
	var center = player.global_position if player else Vector2.ZERO

	var angle = randf() * TAU
	var distance = randf_range(min_spawn_dist, max_spawn_dist) * (
		1.0 + (player.current_scale - 1.0) * 0.5
	)
	var spawn_pos = center + (Vector2(cos(angle), sin(angle)) * distance)

	obj.global_position = spawn_pos

	if obj is CanvasItem:
		obj.z_index = 1

	get_parent().add_child.call_deferred(obj)
