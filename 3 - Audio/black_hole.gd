extends RigidBody2D

@export var pull_strength: float = 600.0
@export var growth_factor: float = 0.05

var current_scale: float = 1.0


func _ready():
	freeze = true
	add_to_group("black_hole")

	if has_node("KillZone"):
		$KillZone.body_entered.connect(_on_kill_zone_body_entered)


func _physics_process(_delta):
	if not has_node("GravityWell"):
		return

	for body in $GravityWell.get_overlapping_bodies():
		if body == self:
			continue

		if "being_slurped" in body and body.being_slurped:
			continue
		#Pull stuff towards black hole
		if body is RigidBody2D or body is CharacterBody2D:
			var offset = global_position - body.global_position
			var dist = offset.length()
			var pull_dir = offset.normalized()

			var distance_dropoff = max(dist * 0.01, 0.5)
			var dynamic_force = (pull_strength / distance_dropoff)

			body.apply_central_force(pull_dir * dynamic_force)


func grow_black_hole(amount: float):
	current_scale += amount * growth_factor
	var tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE * current_scale, 0.4)


func _on_kill_zone_body_entered(body: Node2D):
	if body == self:
		return

	if body.is_in_group("prey"):
		var points = body.point_value if "point_value" in body else 1
		grow_black_hole(points)
		body.queue_free()
	elif body.is_in_group("player") or body.is_in_group("enemies"):
		var victim_scale = body.get("current_scale") if "current_scale" in body else 1.0

		if current_scale > victim_scale:
			if body.is_in_group("player"):
				body.trigger_game_over()
			else:
				grow_black_hole(victim_scale * 5.0)
				body.queue_free()
