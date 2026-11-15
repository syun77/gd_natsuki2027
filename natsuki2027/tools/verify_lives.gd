extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("verify")
func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1
func frames() -> void:
	for i in 5:
		await process_frame
		await physics_frame
func start() -> Node:
	change_scene_to_file("res://scenes/game_time_attack.tscn")
	await frames()
	var game := current_scene
	game.set_physics_process(false)
	if game.entrance.active:
		game._physics_process(game.entrance.TOTAL_TIME)
	return game
func find_button(host: Node, caption: String) -> Button:
	for child in host.get_children():
		if child is Button and child.text == caption:
			return child
		var found := find_button(child, caption)
		if found != null:
			return found
	return null
func verify() -> void:
	root.get_node("ReplayStore").save_path = "/tmp/verify-lives-replay.dat"
	var game = await start()
	check(game.lives_remaining == 3 and game.lives_label.text == "LIFE × 2", "Initial total3, reserves2")
	var layer = game.get_node("TheaterStage/Foods")
	var count: int = layer.get_child_count()
	var pickup = layer.get_child(0)
	var previous_replay: Dictionary = root.get_node("ReplayStore").latest.duplicate(true)
	var best: float = game.best_time
	var score: int = game.score
	pickup.global_position += Vector2(17, -9)
	pickup.collect()
	pickup.collect()
	check(game.lives_remaining == 4 and game.score == score, "1UP increments once with no score")
	var text_found := false
	for child in game.get_node("TheaterStage").get_children():
		if child is Label and child.text == "1UP": text_found = true
	check(text_found, "Pickup popup is 1UP")
	game.restart(true)
	await frames()
	game = current_scene
	game.set_physics_process(false)
	if game.entrance.active:
		game._physics_process(game.entrance.TOTAL_TIME)
	check(game.lives_remaining == 4, "Non-death checkpoint reload does not consume life")
	check(game.get_node("TheaterStage/Foods").get_child_count() == count - 1, "Moved pickup remains absent")
	game.restart()
	await frames()
	game = current_scene
	game.set_physics_process(false)
	if game.entrance.active:
		game._physics_process(game.entrance.TOTAL_TIME)
	check(game.lives_remaining == 3 and game.elapsed == 0.0, "Retry resets lives and run")
	for expected in [2, 1]:
		game._die_on_spikes(game.player.global_position)
		game._die_on_spikes(game.player.global_position)
		check(game.lives_remaining == expected, "Repeated spike callbacks consume once")
		var item = game.get_node("TheaterStage/Foods").get_child(0)
		item.collect()
		check(not item.is_collected and game.lives_remaining == expected, "Death blocks pickups")
		game._physics_process(2.0)
		await frames()
		game = current_scene
		game.set_physics_process(false)
		if game.entrance.active:
			game._physics_process(game.entrance.TOTAL_TIME)
		check(game.lives_remaining == expected, "Death reload preserves decremented life")
	check(game.lives_label.text == "LIFE × 0", "Last active life displays0")
	check(game.lives_blink != null and game.lives_label.modulate.g < 0.3, "Zero reserves starts red blink")
	game.lives_blink.stop()
	game.lives_blink.custom_step(0.36)
	check(game.lives_label.modulate == Color.WHITE, "Zero reserve blink switches to opaque white")
	game.lives_blink.custom_step(0.35)
	check(game.lives_label.modulate == Color(1.0, 0.2, 0.2), "Zero reserve blink switches back to opaque red")
	game.lives_blink.play()
	game.elapsed = 20.0
	game.player.position.y = game.settings.restart_y + game.fall_restart_offset + 1.0
	game._physics_process(1.0 / 60.0)
	check(game.game_over and game.lives_remaining == 0 and paused, "Last-life fall ends run and freezes world")
	var time: float = game.elapsed
	game._physics_process(1.0)
	check(game.elapsed == time and game.lives_remaining == 0, "Game over stops timer and repeat deaths")
	check(not game._begin_death(), "No duplicate death after game over")
	check(game.best_time == best and root.get_node("ReplayStore").latest == previous_replay, "Game over preserves completed records")
	var entries: Array = game._debug_checkpoint_entries()
	if not entries.is_empty():
		game._debug_move_to_checkpoint(entries[0].path)
	check(not game.restarting, "Game-over debug navigation cannot revive player")
	check(not game.has_node("HUD/ClearResults"), "Game over waits for death SE")
	check(game.death_voice.playing and game.death_voice.can_process(), "Death SE continues during game-over pause")
	await game.death_voice.finished
	var result := game.get_node("HUD/ClearResults")
	check(result.data.bonus == 0 and result.data.time_bonus == 0 and result.data.score == game.score, "Game-over result preserves score without bonuses")
	check(result.data.notes == game.note_count and result.data.stars == game.star_count, "Game-over result snapshots pickups")
	var text := ""
	for label in result.find_children("*", "Label", true, false):
		text += label.text
	check(text.contains("GAME OVER") and text.contains("TOTAL SCORE") and not text.contains("ボーナス") and not text.contains("BEST TIME"), "Game-over summary excludes clear rewards and best")
	var title := find_button(result, "タイトルへ")
	check(title != null and not title.has_focus() and title.disabled and title.can_process(), "Game-over title waits for reveal without focus")
	game._show_game_over()
	game._clear_stage()
	check(game.score == result.data.score, "Repeated ending cannot award bonuses")
	game.restart()
	await frames()
	game = current_scene
	game.set_physics_process(false)
	if game.entrance.active:
		game._physics_process(game.entrance.TOTAL_TIME)
	check(not paused and game.lives_remaining == 3 and game.score == 0, "Game-over retry resumes clean run")
	game.lives_remaining = 1
	game._update_lives()
	game.get_node("TheaterStage/Foods").get_child(0).collect()
	check(game.lives_remaining == 2 and game.lives_label.text == "LIFE × 1", "1UP rescues zero reserve state")
	check(game.lives_blink == null and game.lives_label.modulate == Color.WHITE, "1UP clears warning and restores normal color")
	game._die_on_spikes(game.player.global_position)
	game._physics_process(2.0)
	await frames()
	game = current_scene
	game.set_physics_process(false)
	if game.entrance.active:
		game._physics_process(game.entrance.TOTAL_TIME)
	check(not game.game_over and game.lives_remaining == 1, "Extra life permits next respawn")
	game._die_on_spikes(game.player.global_position)
	game._physics_process(2.0)
	check(game.game_over, "Last-life spike also ends run")
	Input.action_press("restart")
	await physics_frame
	game._physics_process(1.0 / 60.0)
	Input.action_release("restart")
	await frames()
	game = current_scene
	game.set_physics_process(false)
	check(paused and game.game_over and game.lives_remaining == 0, "R cannot bypass game-over result")
	game.restart()
	await frames()
	game = current_scene
	game.set_physics_process(false)
	game._physics_process(game.entrance.TOTAL_TIME)
	game.lives_remaining = 1
	game._die_on_spikes(game.player.global_position)
	game._physics_process(2.0)
	if not game.has_node("HUD/ClearResults"):
		await game.death_voice.finished
	game.get_node("HUD/ClearResults").reveal_tween.custom_step(10.0)
	find_button(game.get_node("HUD"), "タイトルへ").pressed.emit()
	await frames()
	check(not paused and current_scene.scene_file_path == "res://scenes/title.tscn", "Game-over title navigation unpauses")
	print("Lives: ", "PASS" if failures == 0 else "FAIL")
	quit(1 if failures else 0)
