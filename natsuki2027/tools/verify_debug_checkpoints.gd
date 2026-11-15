extends SceneTree
## Menu-driven real reloads, stable distance numbering and Time Attack record exclusion.
const CheckpointScene = preload("res://scenes/props/checkpoint.tscn")
var failures := 0

func _initialize() -> void:
	create_timer(20.0, true).timeout.connect(func(): quit(1))
	call_deferred("verify")

func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1

func frames(count := 4) -> void:
	for i in count:
		await process_frame

func ui(action: String) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await frames(1)

func verify() -> void:
	for scene in ["res://scenes/game_time_attack.tscn", "res://scenes/game.tscn"]:
		change_scene_to_file(scene)
		await frames()
		var game = current_scene
		game.set_physics_process(false)
		var group := game.get_node("TheaterStage/Checkpoints")
		var originals: Array[Dictionary] = game._debug_checkpoint_entries()
		check(originals.size() == group.get_child_count() and not originals.is_empty(), "all saved checkpoints enumerated")
		for i in originals.size():
			check(originals[i].number == i + 1, "numbers start at one")
			if i > 0:
				check(originals[i - 1].distance <= originals[i].distance, "sort by spawn distance")
		# Insertion order and player position must not affect numbering; ties use paths.
		var spawn: Vector2 = game.get_node("TheaterStage/PlacementMarkers/PlayerSpawn").global_position
		for name in ["DebugTieZ", "DebugTieA"]:
			var checkpoint := CheckpointScene.instantiate()
			checkpoint.name = name
			group.add_child(checkpoint)
			checkpoint.global_position = spawn + Vector2(10 if name == "DebugTieA" else -10, 10)
		game.player.position += Vector2(1500, -200)
		var ordered: Array[Dictionary] = game._debug_checkpoint_entries()
		check(str(ordered[0].path).ends_with("DebugTieA") and str(ordered[1].path).ends_with("DebugTieZ"), "equal distances use stable path order")
		game.pause_menu.open()
		game.pause_menu.checkpoint_action.pressed.emit()
		await frames()
		check(paused and game.pause_menu.checkpoint_column.visible, "submenu remains paused")
		var panel: Control = game.pause_menu.checkpoint_column.get_parent().get_parent()
		check(panel.size.x <= root.get_visible_rect().size.x and panel.size.y <= root.get_visible_rect().size.y, "checkpoint panel fits viewport")
		check(game.pause_menu.checkpoint_buttons.size() == ordered.size(), "numbered list includes runtime placements")
		check(game.pause_menu.checkpoint_buttons[0].text == "チェックポイント 1", "number visible")
		check(game.pause_menu.checkpoint_buttons[0].has_focus(), "first checkpoint focused")
		await ui("ui_down")
		check(game.pause_menu.checkpoint_buttons[1].has_focus(), "keyboard/pad UI navigation selects next checkpoint")
		game.pause_menu.checkpoint_back.pressed.emit()
		check(game.pause_menu.main_column.visible and game.pause_menu.checkpoint_action.has_focus(), "back retains pause and restores menu focus")
		# A removed list entry must not trigger reload or set debug mode.
		var removed_path: NodePath = ordered[0].path
		game.get_node(removed_path).free()
		game._debug_move_to_checkpoint(removed_path)
		check(not game.restarting and not game.debug_checkpoint_used, "deleted target safely ignored")
		group.get_node("DebugTieZ").free()
		game.pause_menu.checkpoint_action.pressed.emit()
		check(game.pause_menu.checkpoint_buttons.size() == originals.size(), "list refreshes on entry")
		var target_path: NodePath = originals[-1].path
		var target: Vector2 = game.get_node(target_path).respawn_position()
		game.elapsed = 12.5
		game.score = 30
		game.collected_items = {"test_item": true}
		game.player.external_velocity = Vector2(700, -200)
		# Real menu signal invokes the shared restart path, even during entrance.
		game.pause_menu.checkpoint_buttons[-1].grab_focus()
		await frames(2)
		for pressed in [true, false]:
			var cross := InputEventJoypadButton.new()
			cross.button_index = JOY_BUTTON_A
			cross.pressed = pressed
			Input.parse_input_event(cross)
			Input.flush_buffered_events()
		check(game.restarting and not paused, "selection unpauses and requests reload")
		await frames()
		game = current_scene
		game.set_physics_process(false)
		check(game.active_checkpoint == target_path and game.debug_checkpoint_used, "selected checkpoint/debug state survives reload")
		check(not game.entrance.active and game.player.position.distance_to(target) < 8, "reload starts at selected checkpoint, skips entrance")
		check(game.player.external_velocity.length() < 100 and not game.gum.connected(), "reload removes old velocity and gum")
		check(game.score >= 30 and game.collected_items.has("test_item"), "debug reload preserves collected state")
		if game.time_attack:
			check(game.elapsed >= 12.5 and game.elapsed < 12.7 and game.timer_label.text.begins_with("DEBUG "), "debug time retained and labelled")
			var best: float = game.best_time
			game.elapsed = 0.001
			game._finish_time_attack()
			check(game.best_time == best and game.timer_label.text.begins_with("DEBUG "), "debug clear never updates best")
		# Death must retain exclusion; manual retry must start a clean normal run.
		game.restart(true)
		await frames()
		game = current_scene
		game.set_physics_process(false)
		check(game.debug_checkpoint_used and game.active_checkpoint == target_path, "death preserves debug exclusion")
		game.restart()
		await frames()
		game = current_scene
		game.set_physics_process(false)
		check(not game.debug_checkpoint_used and game.active_checkpoint.is_empty(), "manual retry resets debug flag/checkpoint")
		# Empty maps remain navigable and cancel never moves the player.
		for checkpoint in game.get_node("TheaterStage/Checkpoints").get_children(): checkpoint.free()
		var position: Vector2 = game.player.position
		game.pause_menu.open()
		game.pause_menu.checkpoint_action.pressed.emit()
		check(game.pause_menu.checkpoint_buttons.is_empty() and game.pause_menu.checkpoint_back.has_focus(), "empty list focuses back")
		game.pause_menu.close()
		check(not paused and game.player.position == position, "cancel preserves location")
		print("Debug checkpoint menu checked ", scene)
	if failures == 0:
		print("PASS: debug checkpoint ordering/menu/navigation/reload/safety and record exclusion")
	quit(1 if failures else 0)
