extends RigidBody2D

@export var initial_zoom: float = 1.0
@export var camera_zoom_speed: float = 3.0

var target_zoom: Vector2 = Vector2(1.0, 1.0)
var res: int = 512
var base_radius: float = 40.0
var max_amplitude: float = 250.0
var morph_speed: float = 0.1
var peak_decay: float = 0.98
var silence_threshold: float = 0.001
var thrust_force: float = 2.0
var friction: float = 0.98
var low_freq_color: Color = Color.RED
var mid_freq_color: Color = Color.GREEN
var high_freq_color: Color = Color.PURPLE
var max_freq: float = 22050.0
var min_freq: float = 20.0
var current_scale: float = 1.0
var growth_rate: float = 0.1
var pull_radius: float = 400.0
var pull_strength: float = 500.0
var dynamic_min_freq: float = 20.0
var dynamic_max_freq: float = 11025.0
var treble_boost: float = 4.0
var vol: float = 0.0
var ring_count: int = 6
var calibration_threshold: float = 0.00001
var energy_exponent: float = 1.0
var bass_floor_cut: float = 0.005
var expansion_speed: float = 10.0
var contraction_speed: float = 10.0
var spectrum: AudioEffectSpectrumAnalyzerInstance
var current_freqs: Array[float] = []
var target_freqs: Array[float] = []
var is_audio_active: bool = false
var was_audio_active: bool = false
var silence_debounce_timer: float = 0.0
var silence_debounce_duration: float = 0.15
var frequency_memory_window: float = 10.0
var detected_min_actual_freq: float = dynamic_min_freq
var detected_max_actual_freq: float = dynamic_max_freq
var time_since_min_freq_detected: float = 0.0
var time_since_max_freq_detected: float = 0.0
var burst_min_freq_detected: float = dynamic_min_freq
var burst_max_freq_detected: float = dynamic_max_freq
var total_points: int = 0
var current_tier: int = 0
var tier_thresholds: Array[int] = [0, 25, 75, 200, 500]
var tier_base_scales: Array[float] = [1.0, 2.0, 3.0, 5.0, 8.0]
var initial_base_radius: float
var initial_pull_radius: float
var prey_despawn_distance: float = 2000.0
var bh_despawn_distance: float = 5000.0
var record_bus_index: int = -1
var pb_debug_timer: float = 0.0
var watchdog_treshold: float = 5.0
var watchdog_timer: float = 0.0
var mic_reset_cooldown: float = 0.0
var cooldown_duration: float = 5.0
var is_dead: bool = false


func _ready():
	var cam = get_node_or_null("Camera2D")
	if cam and cam is Camera2D:
		cam.enabled = true
		cam.make_current()
		cam.reset_smoothing()
	initial_base_radius = base_radius
	initial_pull_radius = pull_radius

	record_bus_index = AudioServer.get_bus_index("Record")
	if record_bus_index >= 0:
		var effect_count = AudioServer.get_bus_effect_count(record_bus_index)
		for i in range(effect_count):
			var fx = AudioServer.get_bus_effect(record_bus_index, i)
			if fx is AudioEffectSpectrumAnalyzer:
				spectrum = AudioServer.get_bus_effect_instance(record_bus_index, i)
	for i in range(res):
		current_freqs.append(0.0)
		target_freqs.append(0.0)

	detected_min_actual_freq = dynamic_min_freq
	detected_max_actual_freq = dynamic_max_freq

	can_sleep = false
	gravity_scale = 0.0
	mass = 1.0

	update_collision_shape()
	add_to_group("player")
	Manager.register_player_spawn(global_position)


func _physics_process(delta):
	if not spectrum:
		_bind_spectrum()
		if not spectrum:
			return

	var mag = spectrum.get_magnitude_for_frequency_range(0.0, 10000.0)
	var calculated_vol = mag.length()

	if "vol" in self:
		self.vol = calculated_vol * 100.0
	if mic_reset_cooldown > 0.0:
		mic_reset_cooldown -= delta
	if self.vol < 0.001 and watchdog_timer > watchdog_treshold and mic_reset_cooldown <= 0.0:
		reset_mic_input()

	$Camera2D.zoom = $Camera2D.zoom.lerp(target_zoom, camera_zoom_speed * delta)

	linear_velocity *= friction
	angular_velocity *= friction
	_process_audio_data(delta)
	queue_redraw()
	_apply_spectrum_thrust()
	_apply_vacuum_gravity(delta)
	_check_collisions()
	_despawn_far_objects()


func _draw():
	draw_ball()


func reset_mic_input():
	mic_reset_cooldown = cooldown_duration
	watchdog_timer = 0.0
	var mic_node = get_node_or_null("/root/GlobalMicInput")
	if mic_node and mic_node is AudioStreamPlayer:
		mic_node.stop()
		await get_tree().create_timer(0.1).timeout
		mic_node.play()


func trigger_game_over():
	if is_dead:
		return
	is_dead = true

	set_physics_process(false)
	freeze = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	$CollisionPolygon2D.set_deferred("disabled", true)

	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.3) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_IN)

	tween.finished.connect(
		func():
			if Manager.has_method("player_died"):
				Manager.player_died(global_position)
			else:
				Manager.restart_world(),
	)


func on_cloud_absorbed(cloud_points: int):
	total_points += cloud_points

	var new_tier = current_tier
	for i in range(tier_thresholds.size()):
		if total_points >= tier_thresholds[i]:
			new_tier = i

	if new_tier > current_tier:
		current_tier = new_tier

	var base_tier_scale = tier_base_scales[current_tier]

	current_scale = base_tier_scale
	base_radius = initial_base_radius * current_scale
	pull_radius = initial_pull_radius * (1.0 + (current_scale - 1.0) * 0.5)

	if current_scale >= 1.0 and current_scale < 2.0:
		target_zoom = Vector2.ONE * initial_zoom * 1.0
	elif current_scale >= 2.0 and current_scale < 3.0:
		target_zoom = Vector2.ONE * initial_zoom * 0.75
	elif current_scale >= 3.0 and current_scale < 5.0:
		target_zoom = Vector2.ONE * initial_zoom * 0.5
	elif current_scale >= 5.0 and current_scale < 8.0:
		target_zoom = Vector2.ONE * initial_zoom * 0.3
	elif current_scale >= 8.0:
		target_zoom = Vector2.ONE * initial_zoom * 0.25


func update_collision_shape():
	var poly = $CollisionPolygon2D
	var points = PackedVector2Array()
	var segments = 32
	for i in range(segments):
		var angle = (float(i) / segments) * TAU
		points.append(Vector2(cos(angle), sin(angle)) * base_radius)
	poly.polygon = points


func draw_ball():
	var rotation_offset = global_rotation
	var core_radius = base_radius

	for r in range(ring_count - 1, -1, -1):
		var ring_norm = float(r) / (ring_count - 1)
		var base_col: Color

		if ring_norm < 0.5:
			base_col = low_freq_color.lerp(mid_freq_color, ring_norm * 2.0)
		else:
			base_col = mid_freq_color.lerp(high_freq_color, (ring_norm - 0.5) * 2.0)
		var points_inner = PackedVector2Array()
		var points_outer = PackedVector2Array()
		var colors = PackedColorArray()

		var f_min = 20.0 * pow(10, r * 0.4)
		var f_max = 20.0 * pow(10, (r + 1) * 0.4)

		for i in range(res + 1):
			var t = float(i) / res
			var mirror_t = 1.0 - abs(1.0 - 2.0 * t)
			var angle = (t * TAU) + rotation_offset
			var dir = Vector2(cos(angle), sin(angle))

			var energy = _get_sampled_energy(f_min, f_max, int(mirror_t * (res - 1)))
			var ring_amplitude = max_amplitude * (0.3 + (r * 0.15)) * current_scale
			var dist_outer = core_radius + (energy * ring_amplitude)

			points_inner.append(dir * core_radius)
			points_outer.append(dir * dist_outer)

			colors.append(base_col)

		_draw_full_color_slope(points_inner, points_outer, base_col)

	draw_circle(Vector2.ZERO, core_radius, Color.BLACK)


func _bind_spectrum():
	var mic_node = get_node_or_null("/root/GlobalMicInput")
	if not mic_node:
		mic_node = get_tree().root.find_child("GlobalMicInput", true, false)

	if mic_node and mic_node is AudioStreamPlayer:
		if not mic_node.playing:
			mic_node.play()

	var effect_count = AudioServer.get_bus_effect_count(record_bus_index)
	for i in range(effect_count):
		var fx = AudioServer.get_bus_effect(record_bus_index, i)
		if fx is AudioEffectSpectrumAnalyzer:
			spectrum = AudioServer.get_bus_effect_instance(record_bus_index, i)


func _apply_vacuum_gravity(delta):
	var targets = get_tree().get_nodes_in_group("prey")
	for target in targets:
		var dist_vec = global_position - target.global_position
		var distance = dist_vec.length()

		if distance < pull_radius * current_scale:
			var force = dist_vec.normalized() * (pull_strength / max(1.0, distance))
			if target is RigidBody2D:
				target.apply_central_force(force)
			else:
				target.global_position += force * delta


func _check_collisions():
	for body in get_colliding_bodies():
		if body.is_in_group("prey"):
			pass
		elif body.is_in_group("black_hole"):
			_interact_with_black_hole(body)


func _gobble(target):
	if target.is_in_group("black_hole"):
		current_scale += growth_rate
		base_radius += growth_rate * 10.0
		target.queue_free()
	else:
		var tween = create_tween()
		tween.tween_property(target, "modulate:a", 0.0, 0.3)
		tween.finished.connect(
			func():
				target.queue_free(),
		)
	update_collision_shape()


func _interact_with_black_hole(bh_node: Node2D):
	var bh_size = 1.0
	if "mass" in bh_node:
		bh_size = bh_node.mass
	elif "base_radius" in bh_node:
		bh_size = bh_node.base_radius
	elif "current_scale" in bh_node:
		bh_size = bh_node.current_scale * 40.0

	if base_radius > bh_size:
		_gobble(bh_node)
		target_freqs.fill(1.0)
	else:
		trigger_game_over()


func _game_over():
	if freeze:
		return

	set_physics_process(false)
	freeze = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	$CollisionPolygon2D.set_deferred("disabled", true)

	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.4) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_IN)

	tween.finished.connect(
		func():
			Manager.restart_world(),
	)


func _process_audio_data(delta):
	silence_threshold = 0.5
	calibration_threshold = 0.001
	var peak_treshold_multiplier = 0.15

	var audio_on_threshold = silence_threshold * 0.9
	var audio_off_threshold = silence_threshold * 0.5

	var raw_vol_db = AudioServer.get_bus_peak_volume_left_db(AudioServer.get_bus_index("Record"), 0)
	var raw_vol = db_to_linear(raw_vol_db)
	vol = clamp(raw_vol * 15.0, 0.0, 10.0)

	if is_audio_active:
		if vol > audio_off_threshold && vol != 0.0:
			silence_debounce_timer = 0.0
			is_audio_active = true
		else:
			silence_debounce_timer += delta
			if silence_debounce_timer >= silence_debounce_duration:
				is_audio_active = false
	else:
		is_audio_active = vol > audio_on_threshold
		if is_audio_active:
			silence_debounce_timer = 0.0

	if was_audio_active and not is_audio_active:
		for i in range(res):
			target_freqs[i] = current_freqs[i]

	var audio_burst_started = not was_audio_active and is_audio_active
	if audio_burst_started:
		for i in range(res):
			target_freqs[i] = 0.0
		burst_min_freq_detected = max_freq
		burst_max_freq_detected = min_freq
		detected_min_actual_freq = dynamic_max_freq
		detected_max_actual_freq = dynamic_min_freq

	was_audio_active = is_audio_active

	if is_audio_active:
		var full_scan_resolution = 1024
		var active_bins = []
		var magnitudes = []

		for i in range(full_scan_resolution):
			var f_start = min_freq * pow(max_freq / min_freq, float(i) / full_scan_resolution)
			var f_end = min_freq * pow(max_freq / min_freq, float(i + 1) / full_scan_resolution)
			var mag = spectrum.get_magnitude_for_frequency_range(f_start, f_end).length()
			magnitudes.append(mag)

			if (mag * vol) > calibration_threshold:
				active_bins.append(i)

		var current_frame_min_freq = dynamic_min_freq
		var current_frame_max_freq = dynamic_max_freq

		var peak_mag = magnitudes.max() if magnitudes.size() > 0 else 0.0
		var peak_threshold = peak_mag * peak_treshold_multiplier

		var significant_bins = []
		for idx in active_bins:
			if magnitudes[idx] >= peak_threshold:
				significant_bins.append(idx)

		if significant_bins.size() > 0:
			var lowest_idx = significant_bins[0]
			var highest_idx = significant_bins[significant_bins.size() - 1]

			current_frame_min_freq = min_freq * pow(
				max_freq / min_freq,
				float(lowest_idx) / full_scan_resolution,
			)
			current_frame_max_freq = min_freq * pow(
				max_freq / min_freq,
				float(highest_idx) / full_scan_resolution,
			)

			burst_min_freq_detected = min(burst_min_freq_detected, current_frame_min_freq)
			burst_max_freq_detected = max(burst_max_freq_detected, current_frame_max_freq)

		if burst_min_freq_detected < detected_min_actual_freq:
			detected_min_actual_freq = burst_min_freq_detected
		else:
			time_since_min_freq_detected += delta

		if burst_max_freq_detected > detected_max_actual_freq:
			detected_max_actual_freq = burst_max_freq_detected
		else:
			time_since_max_freq_detected += delta

		if detected_max_actual_freq > dynamic_max_freq:
			dynamic_max_freq = lerp(
				dynamic_max_freq,
				detected_max_actual_freq,
				expansion_speed * delta,
			)
			time_since_max_freq_detected = 0.0
		else:
			time_since_max_freq_detected += delta
		if detected_min_actual_freq < dynamic_min_freq:
			dynamic_min_freq = lerp(
				dynamic_min_freq,
				detected_min_actual_freq,
				expansion_speed * delta,
			)
			time_since_min_freq_detected = 0.0
		else:
			time_since_min_freq_detected += delta

		var min_allowed_width = 500.0
		dynamic_min_freq = clamp(dynamic_min_freq, min_freq, dynamic_max_freq - min_allowed_width)
		dynamic_max_freq = clamp(dynamic_max_freq, dynamic_min_freq + min_allowed_width, max_freq)

		for i in range(res):
			var freq_norm = float(i) / res
			var f_start_log = log(dynamic_min_freq)
			var f_end_log = log(dynamic_max_freq)
			var f_log = f_start_log + (f_end_log - f_start_log) * freq_norm
			var f_start = exp(f_log)
			var f_end = exp(f_start_log + (f_end_log - f_start_log) * (freq_norm + 1.0 / res))

			var mag = spectrum.get_magnitude_for_frequency_range(f_start, f_end).length()
			var adaptive_floor = lerp(bass_floor_cut, 0.0, freq_norm)
			mag = max(0.0, mag - adaptive_floor)
			var peak_focused_mag = pow(mag * vol * 40.0, energy_exponent)
			var sensitivity = lerp(1.0, treble_boost, freq_norm)
			var calibrated_energy = clamp(peak_focused_mag * sensitivity, 0.0, 1.0)

			if calibrated_energy > target_freqs[i]:
				target_freqs[i] = calibrated_energy
			else:
				target_freqs[i] *= peak_decay

		for i in range(res):
			var prev_idx = max(0, i - 1)
			var next_idx = min(res - 1, i + 1)
			var smoothed_target = (target_freqs[prev_idx] * 0.25) + (target_freqs[i] * 0.5) + (
				target_freqs[next_idx] * 0.25
			)
			current_freqs[i] = lerp(current_freqs[i], smoothed_target, morph_speed * delta * 10.0)
	else:
		for i in range(res):
			current_freqs[i] *= peak_decay
	if (
		time_since_min_freq_detected > frequency_memory_window
		and detected_min_actual_freq > dynamic_min_freq
	):
		dynamic_min_freq = lerp(
			dynamic_min_freq,
			detected_min_actual_freq,
			contraction_speed * delta,
		)
	if (
		time_since_max_freq_detected > frequency_memory_window
		and detected_max_actual_freq < dynamic_max_freq
	):
		dynamic_max_freq = lerp(
			dynamic_max_freq,
			detected_max_actual_freq,
			contraction_speed * delta,
		)


func _apply_spectrum_thrust():
	var total_magnitude = 0.0
	var weighted_x = 0.0
	var weighted_y = 0.0

	for i in range(res):
		if current_freqs[i] > 0.01:
			var angle = ((float(i) / res) * TAU) + global_rotation
			var freq_energy = current_freqs[i]
			weighted_x += cos(angle) * freq_energy
			weighted_y += sin(angle) * freq_energy
			total_magnitude += freq_energy

	if total_magnitude > 0.01:
		var thrust_dir = Vector2(weighted_x, weighted_y).normalized()
		apply_central_force(-thrust_dir * total_magnitude * thrust_force * current_scale)


func _draw_full_color_slope(inner: PackedVector2Array, outer: PackedVector2Array, color: Color):
	var transparent = color
	transparent.a = 0.0
	for i in range(inner.size() - 1):
		var strip = PackedVector2Array([inner[i], inner[i + 1], outer[i + 1], outer[i]])
		var strip_colors = PackedColorArray([color, color, transparent, transparent])
		draw_primitive(strip, strip_colors, PackedVector2Array())


func _get_sampled_energy(f_min: float, f_max: float, index: int) -> float:
	var freq_norm = float(index) / res
	var f_target_log = log(f_min) + (log(f_max) - log(f_min)) * freq_norm
	var f_target = exp(f_target_log)

	if f_target <= dynamic_min_freq:
		return current_freqs[0]
	if f_target >= dynamic_max_freq:
		return current_freqs[res - 1]

	var window_norm = (log(f_target) - log(dynamic_min_freq)) / (
		log(dynamic_max_freq) - log(dynamic_min_freq)
	)
	var array_idx = clamp(int(window_norm * res), 0, res - 1)

	var val = current_freqs[array_idx]
	if array_idx > 0 and array_idx < res - 1:
		val = (
			current_freqs[array_idx - 1] + current_freqs[array_idx] + current_freqs[array_idx + 1]
		) / 3.0

	return val


func _despawn_far_objects():
	var prey_nodes = get_tree().get_nodes_in_group("prey")
	for prey in prey_nodes:
		if global_position.distance_to(prey.global_position) > prey_despawn_distance:
			prey.queue_free()
	var black_holes = get_tree().get_nodes_in_group("black_hole")
	for bh in black_holes:
		if global_position.distance_to(bh.global_position) > bh_despawn_distance:
			bh.queue_free()
