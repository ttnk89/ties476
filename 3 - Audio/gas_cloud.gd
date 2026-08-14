extends RigidBody2D

const TIERS = {
	"SMALL": { "scale": 1.0, "points": 1, "weight": 25 },
	"MEDIUM": { "scale": 2.0, "points": 2, "weight": 40 },
	"LARGE": { "scale": 3.0, "points": 3, "weight": 25 },
	"SUPER": { "scale": 5.0, "points": 5, "weight": 10 },
}

@export var point_value: int = 1

@export var slurp_decay_speed: float = 3.0
@export var min_spiral_speed: float = 1.0
@export var max_spiral_speed: float = 4.0
@export var pull_speed: float = 60.0

var being_slurped: bool = false
var fading_out: bool = false
var spiral_angle: float = 0.0
var current_radius: float = 0.0
var initial_radius: float = 1.0

var should_spiral: bool = false
var incoming_velocity: Vector2 = Vector2.ZERO
var calculated_spiral_speed: float = 0.0


func _ready():
	gravity_scale = 0.0
	var cloud_color = Color(randf(), randf(), randf(), 0.7)
	modulate = cloud_color
	add_to_group("prey")

	var chosen_tier = _get_random_tier()

	point_value = chosen_tier["points"]

	var base_hue = randf()
	if point_value >= 5:
		cloud_color = Color.from_hsv(base_hue, 0.9, 0.5, 0.8)
	modulate = cloud_color

	$GPUParticles2D.emitting = false
	$GPUParticles2D.local_coords = false
	$GPUParticles2D.explosiveness = 0.1
	$GPUParticles2D.amount = 30
	$GPUParticles2D.lifetime = 1.0

	$GPUParticles2D.process_material = $GPUParticles2D.process_material.duplicate()
	var p_material = $GPUParticles2D.process_material as ParticleProcessMaterial

	p_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	p_material.damping_min = 0.0
	p_material.damping_max = 0.0

	p_material.scale_min = 1.0
	p_material.scale_max = 1.0
	p_material.scale = Vector2.ONE * chosen_tier["scale"]

	p_material.initial_velocity_min = 0.0
	p_material.initial_velocity_max = 0.0
	p_material.gravity = Vector3.ZERO
	p_material.spread = 0.0
	p_material.turbulence_enabled = false


func _physics_process(delta):
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	if fading_out and modulate.a <= 0.0:
		return

	if not being_slurped:
		incoming_velocity = linear_velocity

	var offset = global_position - player.global_position
	var dist = offset.length()

	if dist < player.pull_radius * player.current_scale:
		if not being_slurped:
			being_slurped = true

			var to_player_dir = -offset.normalized()

			var cross_product = incoming_velocity.cross(to_player_dir)

			if abs(cross_product) > 15.0:
				should_spiral = true

				calculated_spiral_speed = clamp(
					abs(cross_product) * 0.02,
					min_spiral_speed,
					max_spiral_speed,
				)

				if cross_product < 0:
					calculated_spiral_speed = -calculated_spiral_speed
			else:
				should_spiral = false

			freeze = true
			$CollisionShape2D.set_deferred("disabled", true)
			$GPUParticles2D.emitting = true

			spiral_angle = offset.angle()
			current_radius = dist
			initial_radius = dist

	if being_slurped:
		if not fading_out:
			var dist_ratio = clamp(current_radius / initial_radius, 0.0, 1.0)
			var speed_modifier = pow(1.0 - dist_ratio, 2.0)
			var dynamic_pull = pull_speed * lerp(0.1, 10.0, speed_modifier)

			if should_spiral:
				current_radius -= dynamic_pull * delta
				var dynamic_spin = calculated_spiral_speed * lerp(1.0, 3.5, speed_modifier)
				spiral_angle += dynamic_spin * delta
				var spiral_offset = Vector2(cos(spiral_angle), sin(spiral_angle)) * max(
					current_radius,
					0.0,
				)
				global_position = player.global_position + spiral_offset
			else:
				var to_player = player.global_position - global_position
				global_position += to_player.normalized() * dynamic_pull * delta

				current_radius = to_player.length()
				spiral_angle = to_player.angle()

			$Sprite2D.scale = Vector2.ONE * dist_ratio

			var dynamic_rot = 5.0 * lerp(1.0, 4.0, speed_modifier)
			$Sprite2D.rotation += dynamic_rot * delta

			if current_radius <= 4.0 or dist_ratio <= 0.0:
				player.on_cloud_absorbed(point_value)
				$Sprite2D.visible = false
				fading_out = true

				var cleanup_tween = create_tween()
				cleanup_tween.tween_property(self, "modulate:a", 0.0, $GPUParticles2D.lifetime)
				cleanup_tween.parallel().tween_property(
					$GPUParticles2D.process_material,
					"scale_min",
					0.0,
					$GPUParticles2D.lifetime,
				)
				cleanup_tween.parallel().tween_property(
					$GPUParticles2D.process_material,
					"scale_max",
					0.0,
					$GPUParticles2D.lifetime,
				)
				cleanup_tween.finished.connect(queue_free)
		else:
			var spin_dir = 1.0 if calculated_spiral_speed >= 0 else -1.0
			spiral_angle += max_spiral_speed * 2.0 * spin_dir * delta
			var drain_offset = Vector2(cos(spiral_angle), sin(spiral_angle)) * 3.0
			global_position = player.global_position + drain_offset


func _get_random_tier() -> Dictionary:
	var roll = randf_range(0, 100)

	if roll < 40:
		return TIERS["SMALL"]
	elif roll < 60:
		return TIERS["MEDIUM"]
	elif roll < 80:
		return TIERS["LARGE"]
	else:
		return TIERS["SUPER"]
