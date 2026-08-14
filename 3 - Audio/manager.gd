extends Node

const WORLD_SCENE = preload("res://world.tscn")

var last_death_location: Vector2 = Vector2.ZERO
var should_trigger_spawn_effect: bool = true
var current_world_instance: Node = null
var is_restarting: bool = false


func register_world_instance(world_node: Node):
	current_world_instance = world_node


func player_died(killer_black_hole_position: Vector2):
	if is_restarting:
		return
	is_restarting = true

	should_trigger_spawn_effect = true

	await TransitionOverlay.play_implosion(killer_black_hole_position, 1.4)
	TransitionOverlay.set_progress(1.0)

	await restart_world()

	if TransitionOverlay.has_method("play_explosion"):
		await TransitionOverlay.play_explosion(killer_black_hole_position, 0.8)
	elif TransitionOverlay.has_method("fade_out"):
		await TransitionOverlay.fade_out()

	is_restarting = false


func restart_world():
	if is_instance_valid(current_world_instance):
		current_world_instance.queue_free()
		current_world_instance = null

	await get_tree().process_frame

	var new_world = WORLD_SCENE.instantiate()
	current_world_instance = new_world
	get_tree().root.add_child(new_world)


func register_player_spawn(player_position: Vector2):
	if should_trigger_spawn_effect:
		should_trigger_spawn_effect = false
		TransitionOverlay.set_progress(1.0)
		await get_tree().process_frame
		await TransitionOverlay.play_expansion(player_position, 5.0)
	else:
		TransitionOverlay.set_progress(0.0)
