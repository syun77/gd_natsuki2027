extends SceneTree
var failures := 0
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
	check(startup == "res://scenes/game_time_attack.tscn", "F5 starts Time Attack")
	change_scene_to_file(startup)
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
	var start := find_button(current_scene, "挑戦する")
	check(start != null and start.has_focus(), "Time Attack start has focus")
	set_meta(&"checkpoint_respawn", {"scene": startup, "score": 999})
	start.pressed.emit()
	await frames()
	game = current_scene
	game.set_physics_process(false)
	check(game.scene_file_path == startup and game.score == 0 and game.elapsed == 0.0, "title starts clean Time Attack")
	game.debug_checkpoint_used = true
	game.elapsed = 12.34
	game._finish_time_attack()
	game.note_count = 24
	game.star_count = 2
	game.score = 300
	game._clear_stage()
	check(game.result_data.remaining_seconds == 168 and game.result_data.time_bonus == 1680, "Remaining seconds round up like HUD")
	check(game.score == 2980 and game.result_data.notes == 24 and game.result_data.stars == 2, "Result adds clear bonus and snapshots counts")
	check(root.get_node("ReplayStore").latest.frames[-1].score == 2980, "Replay final score includes bonus")
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
	result.reveal_tween.stop()
	var labels := result.find_children("*", "Label", true, false)
	result.reveal_tween.custom_step(0.16)
	check(labels[0].modulate.a == 1.0 and labels[1].modulate.a == 0.0, "Heading appears before time")
	result.reveal_tween.custom_step(0.28)
	check(labels[1].modulate.a == 1.0 and labels[2].get_parent().modulate.a == 0.0, "Time appears before item rows")
	result.reveal_tween.custom_step(10.0)
	check(not buttons[0].disabled, "Title enables after all results")
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
	find_button(current_scene, "挑戦する").pressed.emit()
	await frames()
	check(current_scene.score == 0 and current_scene.note_count == 0 and current_scene.star_count == 0, "New run resets result counts")
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
	check(root.get_node("BackgroundMusic").process_mode == Node.PROCESS_MODE_PAUSABLE and not root.get_node("BackgroundMusic").playing, "Result exit restores normal BGM pause policy")
	change_scene_to_file(startup)
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
	DirAccess.remove_absolute("/tmp/verify-time-attack-replay.dat")
	if failures == 0:
		print("PASS: Time Attack startup, timer, death state, title, clean start and mouse-only sequential results")
	quit(1 if failures else 0)
