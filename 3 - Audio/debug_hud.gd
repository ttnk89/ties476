extends CanvasLayer

const WORLD_SCENE = preload("res://world.tscn")

var color_normal = Color.CYAN
var color_peak = Color.RED
var available_devices: PackedStringArray = []
var selected_device_index: int = 0
var game_started: bool = false
var desired_col_width: int = 120
var hovered_device_index: int = -1
var world_instance: Node = null
var preview_timer: float = 0.0
var pending_preview_index: int = -1

@onready var device_list = $VBoxContainer/DeviceListContainer/DeviceList


func _ready():
	game_started = false

	var raw_devices = AudioServer.get_input_device_list()
	available_devices.clear()
	for dev in raw_devices:
		available_devices.append(dev)

	if available_devices.is_empty():
		available_devices = ["No valid input devices found"]

	_refresh_device_list()
	call_deferred("_update_device_layout")
	if available_devices.size() > 0 and available_devices[0] != "No valid input devices found":
		hovered_device_index = 0
		_preview_device(0)


func _process(delta):
	if not game_started:
		if is_instance_valid(device_list):
			var mouse_pos = device_list.get_viewport().get_mouse_position()
			var found_hover = -1

			for i in range(device_list.get_child_count()):
				var col = device_list.get_child(i) as Control
				if col and col.get_global_rect().has_point(mouse_pos):
					found_hover = i
					break

			if found_hover != hovered_device_index:
				hovered_device_index = found_hover
				if (
					hovered_device_index != -1
					and available_devices[0] != "No valid input devices found"
				):
					pending_preview_index = hovered_device_index
					preview_timer = 0.25

		if preview_timer > 0.0:
			preview_timer -= delta
			if preview_timer <= 0.0 and pending_preview_index != -1:
				_preview_device(pending_preview_index)
				pending_preview_index = -1

		_update_device_rows_direct()


func _input(event: InputEvent):
	if game_started:
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_instance_valid(device_list):
			var mouse_pos = device_list.get_viewport().get_mouse_position()

			for i in range(device_list.get_child_count()):
				var col = device_list.get_child(i) as Control
				if col and col.get_global_rect().has_point(mouse_pos):
					select_and_start(i)
					get_viewport().set_input_as_handled()
					break


func select_and_start(index: int):
	if index < 0 or index >= available_devices.size():
		return
	if available_devices[0] == "No valid input devices found":
		return

	preview_timer = 0.0
	pending_preview_index = -1

	selected_device_index = index
	var device_name = available_devices[index]

	if AudioServer.input_device != device_name:
		AudioServer.input_device = device_name

	game_started = true
	get_tree().paused = false

	var list_container = get_node_or_null("VBoxContainer")
	if list_container:
		list_container.visible = false

	await get_tree().create_timer(0.25).timeout

	var mic_node = get_node_or_null("/root/GlobalMicInput")
	if not mic_node:
		mic_node = get_tree().root.find_child("GlobalMicInput", true, false)

	if mic_node and mic_node is AudioStreamPlayer:
		mic_node.stop()

		await get_tree().process_frame
		mic_node.play()

	if not is_instance_valid(world_instance):
		world_instance = WORLD_SCENE.instantiate()
		get_tree().root.add_child(world_instance)
		Manager.register_world_instance(world_instance)


func _refresh_device_list():
	if not device_list:
		return

	for child in device_list.get_children():
		child.queue_free()

	for i in range(available_devices.size()):
		var idx = i
		var col = VBoxContainer.new()
		col.name = "DeviceCol%d" % idx
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.mouse_filter = Control.MOUSE_FILTER_PASS

		var meter = ProgressBar.new()
		meter.min_value = 0.0
		meter.max_value = 1.0
		meter.value = 0.0
		meter.custom_minimum_size = Vector2(40, 200)
		meter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		meter.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
		meter.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var label = Label.new()
		label.text = "%d. %s" % [idx + 1, available_devices[idx]]
		label.custom_minimum_size = Vector2(100, 40)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE

		col.add_child(meter)
		col.add_child(label)
		device_list.add_child(col)


func _preview_device(index: int):
	if index < 0 or index >= available_devices.size():
		return
	var dev_name = available_devices[index]

	var mic_node = get_node_or_null("/root/GlobalMicInput")
	if not mic_node:
		mic_node = get_tree().root.find_child("GlobalMicInput", true, false)

	if AudioServer.input_device == dev_name and mic_node and mic_node.playing:
		return

	AudioServer.input_device = dev_name

	if mic_node and mic_node is AudioStreamPlayer:
		if not mic_node.stream is AudioStreamMicrophone:
			mic_node.stream = AudioStreamMicrophone.new()

		mic_node.stop()
		mic_node.play()


func _update_device_layout():
	if not device_list:
		return

	var viewport_size = get_viewport().get_visible_rect().size
	var width = viewport_size.x * 0.85
	if width <= 0:
		width = 800

	var cols = max(1, int(width / desired_col_width))

	device_list.columns = cols
	device_list.queue_sort()


func _update_device_rows_direct():
	if not device_list:
		return

	var record_bus = AudioServer.get_bus_index("Record")
	if record_bus < 0:
		record_bus = 0

	var db_peak_right = AudioServer.get_bus_peak_volume_right_db(record_bus, 0)
	var db_peak_left = AudioServer.get_bus_peak_volume_left_db(record_bus, 0)
	var db_peak = max(db_peak_right, db_peak_left)

	var linear_vol = db_to_linear(db_peak)
	linear_vol = clamp(linear_vol * 3.0, 0.0, 1.0)

	for i in range(device_list.get_child_count()):
		if i >= available_devices.size():
			break

		var col = device_list.get_child(i)
		if col.get_child_count() < 2:
			continue

		var meter = col.get_child(0) as ProgressBar
		var label = col.get_child(1) as Label
		if meter == null or label == null:
			continue

		var is_hovered = (i == hovered_device_index)
		var is_selected = (i == selected_device_index)
		var device_name = available_devices[i]

		var suffix = ""
		if is_selected:
			suffix = " [ACTIVE]"
		elif is_hovered:
			suffix = " [PREVIEW]"

		label.text = "%d. %s%s" % [i + 1, device_name, suffix]
		label.modulate = (
			Color(1.0, 1.0, 1.0, 1.0)
			if (is_hovered or is_selected)
			else Color(0.7, 0.7, 0.7, 0.9)
		)

		var level = linear_vol if is_hovered else 0.0
		meter.value = level

		var fill = meter.get_theme_stylebox("fill")
		if fill == null:
			fill = StyleBoxFlat.new()
		else:
			fill = fill.duplicate()
		fill.bg_color = color_normal.lerp(color_peak, level)
		meter.add_theme_stylebox_override("fill", fill)


func _update_bar(bar: ProgressBar, value: float):
	bar.value = value

	var sb = bar.get_theme_stylebox("fill")
	if sb == null:
		sb = StyleBoxFlat.new()
	else:
		sb = sb.duplicate()

	sb.bg_color = color_normal.lerp(color_peak, value)
	bar.add_theme_stylebox_override("fill", sb)
