extends CharacterBody3D

var speed
var WALK_SPEED = 5.0
var SPRINT_SPEED = 8.0

const JUMP_VELOCITY = {
	SIZE.MICRO: 1.2,
	SIZE.SMALL: 4.0,
	SIZE.NORMAL: 6.0,
}
const SENSITIVITY = 0.004
const BOB_FREQ = 2.4
const BASE_FOV = 75.0
const FOV_CHANGE = 1.5
const REMOTE_HOLD_POS = Vector3(1.0, -1.0, -1.0)
const REMOTE_ROTATION = Vector3(-45.0, -15.0, -90.0)

var gravity = 9.8
var can_change_size = true
var remote_held = true
var keys_held = false
var in_water = false
var BOB_AMP = 0.08
var t_bob = 0.0

@export var cooldown: float = 0.6

enum SIZE {
	MICRO,
	SMALL,
	NORMAL,
}

var current_size = SIZE.NORMAL

const HEIGHT = {
	SIZE.MICRO: 0.88,
	SIZE.SMALL: 0.78,
	SIZE.NORMAL: 3.0,
}

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var model = $Node3D/MeshInstance3D
@onready var col_normal = $CollisionShape3D_Normal
@onready var col_small = $CollisionShape3D_Small
@onready var col_micro = $CollisionShape3D_Micro
@onready var ceiling_check = $Head/RayCast3D
@onready var mote = $Head/RemoteControl
@onready var water_detection_area = $WaterDetectionArea
@onready var pickup_area = $PickupArea


func _ready():
	ceiling_check.target_position = Vector3(0, HEIGHT[SIZE.NORMAL] - HEIGHT[SIZE.SMALL], 0)
	ceiling_check.enabled = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	mote.position = REMOTE_HOLD_POS
	
	water_detection_area.area_entered.connect(_on_water_entered)
	water_detection_area.area_exited.connect(_on_water_exited)
	pickup_area.body_entered.connect(_on_pickup_detected)

func get_water_surface_height() -> float:
	var water_mesh = get_node("../Objects/Bath/Water")
	if not water_mesh:
		return 0.0
	var aabb = water_mesh.get_mesh().get_aabb()
	var global_aabb = water_mesh.global_transform * aabb
	return global_aabb.get_center().y + (global_aabb.size.y / 2.0)

func snap_player_to_water_surface():
	var surface_height = get_water_surface_height()
	var offset = HEIGHT[SIZE.NORMAL] * 0.6
	global_position.y = surface_height + offset
	
	var space_state = get_world_3d().direct_space_state
	var params = PhysicsShapeQueryParameters3D.new()
	params.shape = col_normal.shape
	params.exclude = [self.get_rid()]
	
	for _i in range(10):
		params.transform = global_transform
		if space_state.intersect_shape(params).is_empty():
			return
		offset += 0.1
		global_position.y = surface_height + offset

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-40), deg_to_rad(60))
	
	if can_change_size and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if current_size == SIZE.NORMAL:
			set_size(SIZE.SMALL)
		elif current_size == SIZE.SMALL and not ceiling_check.is_colliding():
			set_size(SIZE.NORMAL)
		elif current_size == SIZE.MICRO:
			set_size(SIZE.NORMAL)

func _physics_process(delta):
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY[current_size]
	
	speed = SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED

	var input_dir = Input.get_vector("left", "right", "up", "down")
	var direction = (head.transform.basis * transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var decel_factor = 7.0 if is_on_floor() else 3.0
	velocity.x = lerp(velocity.x, direction.x * speed, delta * decel_factor if not direction else 1.0)
	velocity.z = lerp(velocity.z, direction.z * speed, delta * decel_factor if not direction else 1.0)
	
	if current_size == SIZE.SMALL and in_water:
		set_size(SIZE.NORMAL)
	
	t_bob += delta * velocity.length() * float(is_on_floor())
	var bob_offset = _headbob(t_bob)
	camera.transform.origin = bob_offset
	
	if remote_held:
		mote.collision_layer = 2
		mote.position = REMOTE_HOLD_POS + bob_offset
		mote.rotation_degrees = REMOTE_ROTATION
	
	var velocity_clamped = clamp(velocity.length(), 0.25, SPRINT_SPEED * 2)
	camera.fov = lerp(camera.fov, BASE_FOV + FOV_CHANGE * velocity_clamped, delta * 8.0)
	
	move_and_slide()

	if current_size == SIZE.NORMAL:
		if (not keys_held):
			var items = pickup_area.get_overlapping_areas()
			# print("Overlapping items: ", items.size())
			for item in items:
				if item.is_in_group("keys") and not keys_held:
					pickup_keys(item)
					break # Only pick up the first one found

func _headbob(time: float) -> Vector3:
	return Vector3(
		cos(time * BOB_FREQ / 2.0) * BOB_AMP,
		sin(time * BOB_FREQ) * BOB_AMP,
		0.0
	)

func set_size(size: int):
	if current_size == SIZE.SMALL and size == SIZE.NORMAL and in_water:
		snap_player_to_water_surface()
	
	get_tree().create_timer(cooldown).timeout.connect(_on_size_change_cooldown_timeout)
	can_change_size = false
	
	# Disable all collision shapes first
	col_normal.disabled = true
	col_small.disabled = true
	col_micro.disabled = true
	
	# Update based on new size
	match size:
		SIZE.MICRO:
			col_micro.disabled = false
			model.scale = Vector3.ONE * 0.1
			BOB_AMP = 0.02
			WALK_SPEED = 1.0
			SPRINT_SPEED = 2.0
		SIZE.SMALL:
			col_small.disabled = false
			model.scale = Vector3.ONE * 0.1
			BOB_AMP = 0.02
			WALK_SPEED = 2.5
			SPRINT_SPEED = 4.0
		SIZE.NORMAL:
			col_normal.disabled = false
			model.scale = Vector3.ONE * HEIGHT[SIZE.NORMAL]
			BOB_AMP = 0.08
			WALK_SPEED = 5.0
			SPRINT_SPEED = 8.0
	
	head.position.y = HEIGHT[size]
	current_size = size
	if current_size == SIZE.SMALL and remote_held:
		_drop_remote()

func _drop_remote():
	print("Dropped remote")
	remote_held = false
	var drop_position = global_position + Vector3(0, 0.5, 0)
	mote.get_parent().remove_child(mote)
	get_tree().root.get_child(0).add_child(mote)
	mote.global_position = drop_position

	mote.freeze = false
	mote.set_collision_layer_value(1, true)
	mote.set_collision_layer_value(2, true)
	mote.collision_mask = 1
	mote.linear_velocity = Vector3.ZERO

func pickup_remote():
	print("Picked up remote")
	remote_held = true
	mote.get_parent().remove_child(mote)
	head.add_child(mote)
	mote.position = REMOTE_HOLD_POS

func pickup_keys(item: Node3D):
	print("Picked up keys")
	keys_held = true
	var keysparent = item.get_parent()
	keysparent.get_parent().remove_child(keysparent)

func _on_size_change_cooldown_timeout():
	can_change_size = true

func _on_water_entered(area: Area3D):
	if area.is_in_group("water"):
		print("Entered water")
		in_water = true

func _on_water_exited(area: Area3D):
	if area.is_in_group("water"):
		in_water = false

func _on_pickup_detected(body: Node3D):
	# print("Pickup detected: ", body.name)
	if body == mote and not remote_held and current_size == SIZE.NORMAL:
		print("Picked up remote")
		remote_held = true
		mote.get_parent().remove_child(mote)
		head.add_child(mote)
# 		mote.position = REMOTE_HOLD_POS
# 	if body == keys and current_size == SIZE.NORMAL:
# 		print("Picked up keys")
# 		keys_held = true
# 		keys.get_parent().remove_child(keys)


func _on_detection_area_body_entered(body):
	pass # Replace with function body.
