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
	var collected_score: int = game.score
	for death in 2:
		game.restart(true)
		await frames()
		game = current_scene
		game.set_physics_process(false)
		check(game.score == collected_score and game.elapsed > before, "death retains time and score")
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
	game._clear_stage()
	check(find_button(game.get_node("HUD"), "リトライ") != null, "result offers retry")
	check(find_button(game.get_node("HUD"), "ステージ選択へ") == null, "result contains no stage selection")
	find_button(game.get_node("HUD"), "リトライ").pressed.emit()
	await frames()
	check(not current_scene.debug_checkpoint_used and current_scene.elapsed == 0.0, "result retry resets run")
	DirAccess.remove_absolute("/tmp/verify-time-attack-replay.dat")
	if failures == 0:
		print("PASS: Time Attack startup, timer, death state, title, clean start and result retry")
	quit(1 if failures else 0)
