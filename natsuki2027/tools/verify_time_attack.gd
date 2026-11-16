extends SceneTree
var failures := 0
var result_cues := 0
func count_result_cue(cue: StringName) -> void:
	if cue == &"score_item":
		result_cues += 1
func _initialize() -> void:
	call_deferred("verify")
func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1
func frames() -> void:
	for i in 4:
		await physics_frame
		await process_frame
func find_button(host: Node, caption: String) -> Button:
	for child in host.get_children():
		if child is Button and child.text == caption:
			return child
		var found := find_button(child, caption)
		if found != null:
			return found
	return null
func verify() -> void:
	root.get_node("ReplayStore").save_path = "/tmp/verify-time-attack-replay.dat"
	var startup: String = ProjectSettings.get_setting("application/run/main_scene")
	if startup.begins_with("uid://"):
		startup = ResourceUID.get_id_path(ResourceUID.text_to_id(startup))
	check(startup == "res://scenes/title.tscn", "F5 starts title")
	change_scene_to_file(startup)
	await frames()
	check(current_scene.find_children("*", "Button", true, false).is_empty(), "Title starts through a physical goal")
	var title = current_scene
	check(title.get_node_or_null("Background") == null, "Title has no background image")
	var rings: TileMapLayer = title.get_node("GumAnchors")
	check(rings.get_used_cells().size() == 4 and rings.physics_quadrant_size == 1, "Title has four individual functional rings")
	for cell in rings.get_used_cells():
		var center := rings.to_global(rings.map_to_local(cell))
		var hit: Dictionary = title.get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(center + Vector2(0, 64), center, 16))
		check(not hit.is_empty() and hit.collider == rings and rings.get_cell_source_id(cell) == 2, "Title ring has attachment collision")
		var player_hit: Dictionary = title.get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(center + Vector2(0, 30), center, 1))
		check(player_hit.is_empty(), "Title ring does not block the player")
	for x in [384.0, 704.0]:
		var hit: Dictionary = title.get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(Vector2(x, 480), Vector2(x, 420), 1))
		check(not hit.is_empty() and hit.position.is_equal_approx(Vector2(x, 448)), "Shelf artwork matches attachable collision")
	var spawn: Vector2 = title.player.position
	Input.action_press("move_right")
	for i in 30:
		await physics_frame
		await process_frame
	Input.action_release("move_right")
	check(title.player.position.x > spawn.x + 50 and title.player.is_on_floor(), "Title player walks on physical terrain")
	check(title.elapsed == 0 and not title.exit_door.started, "Practice has no countdown or automatic start")
	Input.action_press("aim_down")
	Input.action_press("gum_action")
	await frames()
	Input.action_release("gum_action")
	Input.action_release("aim_down")
	await frames()
	check(title.gum.connected(), "Title uses the live gum attachment rules")
	Input.action_press("jump")
	await frames()
	Input.action_release("jump")
	check(not title.gum.connected(), "Title jump detaches gum")
	for i in 60:
		await physics_frame
		await process_frame
	Input.action_press("aim_up")
	Input.action_press("gum_action")
	await frames()
	Input.action_release("gum_action")
	Input.action_release("aim_up")
	await frames()
	check(title.gum.connected() and title.gum.target == rings, "Title upward shot attaches to the overhead ring")
	check(title.gum.endpoint().is_equal_approx(Vector2(272, 528)), "Title ring uses center adhesion")
	Input.action_press("jump")
	await frames()
	Input.action_release("jump")
	for i in 90:
		await physics_frame
		await process_frame
	# Reach the raised goal using real movement and one contact kick.
	Input.action_press("move_right")
	var kicked := false
	for i in 300:
		if title.exit_door.started:
			break
		if title.player.position.x >= 976 and not kicked:
			Input.action_press("jump")
			kicked = true
		else:
			Input.action_release("jump")
		await physics_frame
		await process_frame
	Input.action_release("move_right")
	Input.action_release("jump")
	check(title.exit_door.started, "Entering title goal begins the door sequence")
	for i in 240:
		if current_scene != title:
			break
		await physics_frame
		await process_frame
	await frames()
	var game = current_scene
	game.set_physics_process(false)
	game._physics_process(game.entrance.TOTAL_TIME)
	var before: float = game.elapsed
	game._physics_process(1.0 / 60.0)
	check(game.elapsed > before and game.timer_label.visible, "run always counts time")
	var counts: Dictionary = {}
	for layer_name in ["Foods", "Baguettes", "MusicNotes"]:
		var layer := game.get_node("TheaterStage/" + layer_name)
		counts[layer_name] = layer.get_child_count()
		check(layer.get_child_count() > 0, "map contains " + layer_name)
		var pickup = layer.get_child(0)
		var score_before: int = game.score
		if layer_name == "Foods":
			pickup.global_position += Vector2(17, -9)
		pickup.collect()
		pickup.collect()
		check(game.score == score_before + {"Foods": 0, "Baguettes": 30, "MusicNotes": 10}[layer_name], "pickup scores once: " + layer_name)
	check(game.note_count == 1 and game.star_count == 1, "Pickup kinds count once, 1UP excluded")
	var collected_score: int = game.score
	for death in 2:
		game.restart(true)
		await frames()
		game = current_scene
		game.set_physics_process(false)
		check(game.score == collected_score and game.elapsed > before, "death retains time and score")
		check(game.note_count == 1 and game.star_count == 1, "Death retains each item count")
		for layer_name in counts:
			check(game.get_node("TheaterStage/" + layer_name).get_child_count() == counts[layer_name] - 1, "death retains absent pickup: " + layer_name)
	game.pause_menu.open()
	check(game.pause_menu.buttons[1].text == "タイトルに戻る", "pause names title destination")
	game.pause_menu.buttons[1].pressed.emit()
	await frames()
	check(current_scene.scene_file_path == "res://scenes/title.tscn" and not paused, "pause returns to title")
	check(find_button(current_scene, "ステージを選ぶ") == null, "title contains no Stage Mode")
	check(current_scene.player.visible, "Returned title has controllable player")
	set_meta(&"checkpoint_respawn", {"scene": "res://scenes/game_time_attack.tscn", "score": 999})
	current_scene._start()
	await frames()
	game = current_scene
	game.set_physics_process(false)
	check(game.scene_file_path == "res://scenes/game_time_attack.tscn" and game.score == 0 and game.elapsed == 0.0, "title starts clean Time Attack")
	game.debug_checkpoint_used = true
	game.elapsed = 12.34
	game._finish_time_attack()
	game.note_count = 24
	game.star_count = 2
	game.score = 300
	root.get_node("SoundEffects").played.connect(count_result_cue)
	game._clear_stage()
	check(game.result_data.remaining_seconds == 168 and game.result_data.time_bonus == 1680, "Remaining seconds round up like HUD")
	check(game.score == 2980 and game.result_data.notes == 24 and game.result_data.stars == 2, "Result adds clear bonus and snapshots counts")
	if root.get_node("ReplayStore").ENABLED:
		check(root.get_node("ReplayStore").latest.frames[-1].score == 2980, "Replay final score includes bonus")
	else:
		check(root.get_node("ReplayStore").frames.is_empty(), "Clear creates no replay frames while disabled")
	game._clear_stage()
	check(game.score == 2980, "Clear bonus cannot repeat")
	var result = game.get_node("HUD/ClearResults")
	check(paused and result.can_process() and root.get_node("BackgroundMusic").can_process(), "Result pauses world and keeps UI/music processing")
	check(not game.player.can_process(), "Result freezes player")
	for button in result.find_children("*", "Button", true, false):
		check(button.focus_mode == Control.FOCUS_NONE and not button.has_focus(), "Result buttons have no keyboard/gamepad focus")
	for key in [KEY_R, KEY_ESCAPE, KEY_ENTER, KEY_SPACE, KEY_Z, KEY_X, KEY_DOWN]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = true
		root.push_input(event)
		event = event.duplicate()
		event.pressed = false
		root.push_input(event)
	var joy := InputEventJoypadButton.new()
	joy.button_index = JOY_BUTTON_A
	joy.pressed = true
	root.push_input(joy)
	joy = joy.duplicate()
	joy.pressed = false
	root.push_input(joy)
	await frames()
	check(current_scene == game and not game.restarting and paused and not game.pause_menu.is_open, "Keyboard and gamepad cannot dismiss or pause results")
	var buttons := result.find_children("*", "Button", true, false)
	check(buttons.size() == 1 and buttons[0].text == "タイトルへ", "Only title button remains")
	check(buttons[0].disabled, "Title cannot skip reveal")
	var music = root.get_node("BackgroundMusic")
	var music_bus := AudioServer.get_bus_index(&"BGM")
	var filter_index: int = music.RESULT_FILTER_INDEX
	var low_pass = AudioServer.get_bus_effect(music_bus, filter_index)
	check(low_pass is AudioEffectLowPassFilter and low_pass.cutoff_hz == 1200.0, "Result low-pass cutoff")
	check(music.playing and is_equal_approx(music.volume_linear, 1.0) and AudioServer.is_bus_effect_enabled(music_bus, filter_index), "Results keep BGM playing with low pass")
	result.reveal_tween.stop()
	result_cues = 0
	var labels := result.find_children("*", "Label", true, false)
	result.reveal_tween.custom_step(0.16)
	check(labels[0].modulate.a == 1.0 and labels[1].modulate.a == 0.0, "Heading appears before time")
	result.reveal_tween.custom_step(0.28)
	check(labels[1].modulate.a == 1.0 and labels[2].get_parent().modulate.a == 0.0, "Time appears before item rows")
	result.reveal_tween.custom_step(10.0)
	check(not buttons[0].disabled, "Title enables after all results")
	check(result_cues == 8, "Each result item sounds once; separators are silent")
	var voices := root.get_node("SoundEffects").get_children()
	check(voices[-1].can_process() and voices[-1].playing, "Result note sound plays while world is paused")
	root.get_node("SoundEffects").played.disconnect(count_result_cue)
	await frames()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = buttons[0].get_global_rect().get_center()
	click.pressed = true
	root.push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	await frames()
	check(current_scene.scene_file_path == "res://scenes/title.tscn" and not paused, "Mouse title button exits results")
	music.fade_tween.stop()
	music.fade_tween.custom_step(0.5)
	check(music.playing and music.volume_linear > 0.0 and music.volume_linear < 1.0, "Title transition fades continuing BGM")
	current_scene._start()
	await frames()
	check(not AudioServer.is_bus_effect_enabled(music_bus, filter_index), "New run disables result filter")
	check(current_scene.score == 0 and current_scene.note_count == 0 and current_scene.star_count == 0, "New run resets result counts")
	check(music.playing and is_equal_approx(music.volume_linear, 1.0), "New run restores normal BGM volume")
	game = current_scene
	game.set_physics_process(false)
	game.debug_checkpoint_used = false
	game.new_best = true
	game.elapsed = 83.45
	game.best_time = 83.45
	game._clear_stage()
	check(game.score == 1970 and game.result_data.notes == 0 and game.result_data.stars == 0, "Zero pickups award clear and time bonuses")
	result = game.get_node("HUD/ClearResults")
	var text := ""
	for label in result.find_children("*", "Label", true, false):
		text += label.text + "\n"
	check(text.contains("STAGE CLEAR!") and text.contains("NEW BEST") and text.contains("01:23.45"), "Normal result displays time and best record")
	check(text.contains("× 0") and not text.contains("音符") and not text.contains("★") and not text.contains("マウスで") and text.contains("+1,000点") and text.contains("97秒 × 10   +970点"), "Zero counts and bonus remain visible")
	result.reveal_tween.custom_step(10.0)
	await frames()
	var title_button := find_button(result, "タイトルへ")
	click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = title_button.get_global_rect().get_center()
	click.pressed = true
	root.push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	await frames()
	check(current_scene.scene_file_path == "res://scenes/title.tscn" and not paused, "Mouse title exit restores tree pause")
	check(music.process_mode == Node.PROCESS_MODE_PAUSABLE and music.playing, "Title keeps BGM alive for fade")
	music.fade_tween.stop()
	music.fade_tween.custom_step(1.0)
	music.fade_tween.custom_step(0.001)
	check(not music.playing and music.volume_linear < 0.0001, "Title BGM stops after one-second fade")
	change_scene_to_file("res://scenes/game_time_attack.tscn")
	await frames()
	game = current_scene
	game.set_physics_process(false)
	check(game.timer_label.text == "TIME 3:00" and game.timer_gauge.value == 180.0, "Countdown starts full at three minutes")
	game._physics_process(game.entrance.TOTAL_TIME)
	game.elapsed = 149.99
	game._update_timer()
	check(game.timer_label.modulate == Color.WHITE, "No warning before thirty seconds")
	game.elapsed = 150.0
	game._update_timer()
	check(game.timer_label.text == "TIME 0:30" and game.timer_label.modulate.g < 0.5, "Thirty seconds starts red warning")
	game.elapsed = 150.36
	game._update_timer()
	check(game.timer_label.modulate == Color.WHITE and game.timer_gauge.value < 30.0, "Warning alternates white and red with falling gauge")
	var best_before: float = game.best_time
	game.elapsed = 180.1
	check(game._remaining_seconds() == 0, "Time bonus seconds cannot become negative")
	game.elapsed = 179.99
	game._physics_process(0.02)
	check(game.game_over and paused and game.elapsed == 180.0, "Timeout clamps at180 and pauses world")
	check(game.timer_label.text == "TIME 0:00" and game.timer_gauge.value == 0.0, "Timeout displays empty countdown")
	check(game.score == 0 and game.best_time == best_before and not game.cleared, "Timeout awards no bonus or record")
	check(game.has_node("HUD/ClearResults"), "Timeout without death SE shows results immediately")
	var timeout_text := ""
	for label in game.get_node("HUD").find_children("*", "Label", true, false):
		timeout_text += label.text
	check(timeout_text.contains("TIME UP"), "Timeout names its ending")
	check(game.result_data.bonus == 0 and game.result_data.time_bonus == 0 and game.has_node("HUD/ClearResults"), "Timeout shows result without bonuses")
	game.restart()
	await frames()
	game = current_scene
	game.set_physics_process(false)
	check(not paused and game.elapsed == 0.0 and game.timer_gauge.value == 180.0, "Timeout retry resets three minutes")
	var editable = load("res://scenes/title.tscn").instantiate()
	editable.get_node("PlacementMarkers/PlayerSpawn").position = Vector2(192, 672)
	editable.get_node("PlacementMarkers/Exit").position = Vector2(1152, 608)
	var practice_checkpoint = load("res://scenes/props/checkpoint.tscn").instantiate()
	practice_checkpoint.name = "PracticeCheckpoint"
	practice_checkpoint.position = Vector2(192, 672)
	editable.get_node("Checkpoints").add_child(practice_checkpoint)
	practice_checkpoint.owner = editable
	var lift = load("res://scenes/props/moving_platform.tscn").instantiate()
	lift.name = "PracticeLift"
	lift.configure({"id": "practice_lift", "x": 18, "y": 18, "direction": "up", "travel_cells": 2, "width_cells": 2, "speed": 64.0, "endpoint_wait": 0.0})
	editable.get_node("MovingPlatforms").add_child(lift)
	lift.owner = editable
	var edited_title := PackedScene.new()
	check(edited_title.pack(editable) == OK, "Edited title packs for gameplay")
	editable.free()
	change_scene_to_packed(edited_title)
	await frames()
	var practice = current_scene
	check(absf(practice.player.position.x - 192.0) < 0.1, "Edited start marker owns actual title spawn")
	check(practice.exit_door.position.is_equal_approx(Vector2(1152, 608)), "Edited goal marker owns actual door")
	check(practice.get_node("Checkpoints/PracticeCheckpoint").activated, "Transferred practice checkpoint activates")
	check(practice.get_node("MovingPlatforms/PracticeLift").position.y < 576.0, "Transferred title lift moves on physics ticks")
	DirAccess.remove_absolute("/tmp/verify-time-attack-replay.dat")
	if failures == 0:
		print("PASS: Time Attack startup, timer, death state, title, clean start and mouse-only sequential results")
	quit(1 if failures else 0)
