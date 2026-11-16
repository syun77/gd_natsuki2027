extends SceneTree
## Run with Godot --headless --path natsuki2027 --log-file /tmp/replay.log --script res://tools/verify_replay.gd.
var failures := 0
var store: Node
const TEST_PATH := "/tmp/bungee-gum-verify-replay.dat"

func _initialize() -> void:
	call_deferred("verify")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func wait_frames(count := 3) -> void:
	for i in count:
		await process_frame

func verify() -> void:
	store = root.get_node("ReplayStore")
	if not store.ENABLED:
		await verify_disabled()
		return
	store.save_path = TEST_PATH
	DirAccess.remove_absolute(TEST_PATH)
	store.load_latest()
	check(not store.available(), "No completed run means no replay")
	change_scene_to_file("res://scenes/game_time_attack.tscn")
	await wait_frames()
	var game = current_scene
	check(store.frames.size() > 0, "Scene entry starts recording entrance")
	check(game.pause_menu.buttons[3].disabled, "Replay action disabled without completed data")
	var first_frame: Dictionary = store.frames[0]
	var has_tiles := false
	var has_platform := false
	var has_routes := false
	for data in first_frame.changed.values():
		has_tiles = has_tiles or data.kind == "tiles"
		has_routes = has_routes or (data.kind == "segments" and not data.points.is_empty())
		has_platform = has_platform or (data.kind == "nine_patch" and data.size == Vector2(96, 10) and data.margins == Vector4i(8, 2, 8, 2))
	check(has_routes, "Moving platform routes recorded")
	check(has_platform, "Moving platform nine-slice artwork recorded")
	check(has_tiles, "Initial frame contains saved map artwork")
	var count: int = store.frames.size()
	game.pause_menu.open()
	await create_timer(0.08, true).timeout
	check(store.frames.size() == count, "Pause never adds replay time")
	game.pause_menu.close()
	game.entrance.step(game.entrance.TOTAL_TIME)
	game.gum.show()
	Input.action_press("move_right")
	for i in 12:
		await physics_frame
		await process_frame
	Input.action_release("move_right")
	check(store.frames.size() > count, "Actual physics ticks append frames")
	var final_position: Vector2 = game.player.sprite.global_position
	var sprite_id: int = game.player.sprite.get_instance_id()
	store.capture()
	check(store.previous.has(sprite_id), "Player animation recorded")
	var player_visual: Dictionary = store.previous[sprite_id]
	check(player_visual.transform.origin.is_equal_approx(final_position), "Recorded position uses actual sprite transform")
	check(not player_visual.texture.is_empty(), "Sprite texture is persistable")
	game.gum.fire(Vector2.UP)
	game.gum.step(0.01)
	store.capture()
	check(store.previous[-1].kind == "gum" and not store.previous[-1].ready, "Outbound gum path recorded")
	check(store.frames[-1].sounds.has(&"shoot"), "Sound cues recorded")
	var box = load("res://scenes/props/gum_box.tscn").instantiate()
	game.add_child(box)
	box.position = Vector2(400, 300)
	box.rotation = 0.7
	store.capture()
	var box_visual: Dictionary = store.previous[box.get_node("Color").get_instance_id()]
	check(box_visual.transform == box.get_node("Color").global_transform, "Rigid rotation and position recorded")
	var tiles: TileMapLayer = game.get_node("TheaterStage/TerrainTiles")
	var cell: Vector2i = tiles.get_used_cells()[0]
	tiles.erase_cell(cell)
	store.capture()
	check(store.frames[-1].changed[tiles.get_instance_id()].cells == tiles.tile_map_data, "Terrain changes recorded as tile deltas")
	box.free()
	store.capture()
	check(store.frames[-1].removed.size() >= 2, "Deleted objects remove all visuals")
	# Actual checkpoint death reload keeps the beginning, and replaces old visual IDs.
	count = store.frames.size()
	var initial_frame: Dictionary = store.frames[0]
	game.restart(true)
	await wait_frames(5)
	game = current_scene
	check(store.frames.size() > count and store.frames[0] == initial_frame, "Death reload preserves start-to-goal recording")
	check(store.game == game, "Recording follows replacement Game")
	# An unfinished run cannot overwrite the completed replay.
	check(not FileAccess.file_exists(TEST_PATH), "No replay file written before clear")
	game.entrance.step(game.entrance.TOTAL_TIME)
	game.best_time = 0.000001 # Avoid changing the user's separate Time Attack best.
	game.player.global_position = game.exit_door.global_position
	game._begin_exit()
	for i in 120:
		await physics_frame
		await process_frame
		if game.cleared:
			break
	check(game.cleared, "Actual exit sequence completes recording")
	check(store.available() and FileAccess.file_exists(TEST_PATH), "Goal saves complete replay")
	check(not is_instance_valid(store.game), "Clear stops capture")
	var recorded: Dictionary = store.latest.duplicate(true)
	store.latest = {}
	store.load_latest()
	check(store.latest == recorded, "Compressed disk roundtrip preserves every snapshot")
	var background_store = load("res://scripts/replay_store.gd").new()
	background_store.save_path = TEST_PATH
	root.add_child(background_store)
	check(background_store.latest.is_empty() and background_store._loader != null, "Startup returns before replay loading is adopted")
	var loaded_signal := [false]
	background_store.availability_changed.connect(func(): loaded_signal[0] = true)
	paused = true
	for attempt in 600:
		if loaded_signal[0]:
			break
		await create_timer(0.01, true).timeout
	check(loaded_signal[0] and background_store.latest == recorded, "Background replay validates and notifies UI even while paused")
	paused = false
	background_store.queue_free()

	var shared_settings = load("res://resources/game_settings.tres")
	var original_zoom: float = shared_settings.camera_normal_zoom
	shared_settings.camera_normal_zoom = original_zoom * 1.25
	game.pause_menu.open()
	check(not game.pause_menu.buttons[3].disabled, "Completed run enables replay action")
	game.pause_menu.buttons[3].pressed.emit()
	await wait_frames(5)
	var replay = current_scene
	check(root.get_node("BackgroundMusic").playing, "Replay starts background music")
	check(replay.scene_file_path == "res://scenes/replay.tscn" and not paused, "Game menu launches unpaused replay")
	check(replay.get_node_or_null("Player") == null and replay.get_node_or_null("TheaterStage") == null, "Playback has no live gameplay scene")
	check(not replay.visuals.is_empty(), "Replay renders recorded visuals")
	check(replay.camera.zoom.is_equal_approx(Vector2.ONE * original_zoom * 1.25), "Saved run uses current shared normal zoom at playback entry")
	replay.settings = replay.settings.duplicate()
	shared_settings.camera_normal_zoom = original_zoom
	for zoom in [0.75, 1.5]:
		replay.settings.camera_normal_zoom = zoom
		var frame: Dictionary = recorded.frames[replay.cursor - 1].duplicate(true)
		frame["zoom"] = Vector2(3, 3)
		frame.sounds = []
		replay._apply_frame(frame)
		check(replay.camera.zoom.is_equal_approx(Vector2.ONE * zoom), "Playback uses current normal zoom instead of recorded zoom")
		check(replay.camera.position == frame.camera, "Changing zoom preserves recorded camera center")
	for node in replay.visuals.values():
		check(not node is PhysicsBody2D and not node is Area2D, "Playback visual is never a physics actor")
		if node is TileMapLayer:
			check(not node.collision_enabled and not node.navigation_enabled, "Replay tiles cannot affect physics")
			for i in node.tile_set.get_source_count():
				check(not node.tile_set.get_source(node.tile_set.get_source_id(i)) is TileSetScenesCollectionSource, "Replay tiles cannot spawn live pickups")
	replay.pause_menu.open()
	var cursor: int = replay.cursor
	await create_timer(0.05, true).timeout
	check(replay.cursor == cursor, "Replay pause freezes cursor")
	replay.pause_menu.close()
	# Advance the normal playback clock through the remaining saved ticks.
	replay._physics_process(float(store.latest.frames.size()) / store.latest.tick_rate + 1.0)
	check(replay.finished and replay.pause_menu.is_open, "Replay ends with replay/back controls")
	check(replay.score.text == "SCORE %d" % store.latest.frames[-1].score, "Final score reproduced")
	var expected: Dictionary = {}
	for frame in recorded.frames:
		for id in frame.removed:
			expected.erase(id)
		expected.merge(frame.changed, true)
	check(replay.visuals.size() == expected.size(), "Final visual set exactly matches recorded run")
	for id in expected:
		check(replay.visuals.has(id), "Recorded final visual exists")
		if replay.visuals.has(id):
			check(replay.visuals[id].transform == expected[id].transform, "Final transform reproduces recorded state without drift")
			if expected[id].kind == "segments":
				check(replay.visuals[id].points == expected[id].points and replay.visuals[id].color == expected[id].color, "Replay restores route lines without running motors")
			if expected[id].kind == "nine_patch":
				var patch: NinePatchRect = replay.visuals[id].get_child(0)
				check(patch.size == expected[id].size and patch.patch_margin_left == 8 and patch.patch_margin_right == 8, "Replay restores nine-slice width and fixed caps")
	check(store.latest == recorded, "Playback never changes saved run")
	replay.pause_menu.buttons[0].pressed.emit()
	await wait_frames()
	replay = current_scene
	check(not replay.finished and not paused, "Replay can restart from menu")
	check(root.get_node("BackgroundMusic").playing, "Replay restart starts background music")
	replay.pause_menu.open()
	replay.pause_menu.buttons[1].pressed.emit()
	await wait_frames()
	check(current_scene.scene_file_path == "res://scenes/title.tscn" and not paused, "Replay back returns to title")
	check(not root.get_node("BackgroundMusic").playing, "Leaving replay stops background music")
	var menu_buttons := current_scene.find_children("*", "Button", true, false)
	var replay_button: Button
	for button in menu_buttons:
		if button.text == "RELAY再生":
			replay_button = button
	check(replay_button != null and not replay_button.disabled, "Mode menu has enabled replay action")
	replay_button.pressed.emit()
	await wait_frames()
	check(current_scene.scene_file_path == "res://scenes/replay.tscn", "Mode menu launches replay")
	check(root.get_node("BackgroundMusic").playing, "Title replay starts background music")
	# Manual retry starts a new run while retaining the previous completed run.
	paused = false
	change_scene_to_file("res://scenes/game.tscn")
	await wait_frames()
	game = current_scene
	store.capture()
	count = store.frames.size()
	game.restart()
	await wait_frames()
	check(store.frames.size() < count + 4 and store.latest == recorded, "Manual retry resets recording and retains saved replay")
	store.suspend(false)
	check(not store.valid_recording({}), "Missing replay schema rejected")
	var invalid: Dictionary = recorded.duplicate(true)
	invalid.frames[0].erase("camera")
	check(not store.valid_recording(invalid), "Malformed frame rejected")
	invalid = recorded.duplicate(true)
	invalid.frames[0].changed.values()[0].kind = "unknown"
	check(not store.valid_recording(invalid), "Unknown visual schema rejected")
	# A write failure retains the completed replay and its on-disk bytes.
	store.begin(current_scene)
	store.save_path = "/tmp/bungee-replay-missing-directory/replay.dat"
	store.finish()
	check(not store.failure.is_empty() and store.latest == recorded, "Save failure retains previous completed run")
	store.save_path = TEST_PATH
	var file := FileAccess.open_compressed(TEST_PATH, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	file.store_var({"version": -1})
	file.close()
	store.load_latest()
	check(not store.available(), "Unsupported saved replay disabled safely")
	DirAccess.remove_absolute(TEST_PATH)
	print("Replay: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)

func verify_disabled() -> void:
	check(not store.is_processing() and not store.is_physics_processing() and store._loader == null, "Disabled replay starts no loader or recording callbacks")
	store.save_path = TEST_PATH
	var sentinel := PackedByteArray([12, 34, 56, 78])
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_buffer(sentinel)
	file.close()
	store.load_latest()
	check(store.latest.is_empty(), "Disabled replay does not read saved data")
	change_scene_to_file("res://scenes/title.tscn")
	await wait_frames()
	check(current_scene.find_children("*", "Button", true, false).is_empty(), "Playable title has no replay menu")
	store.latest = {"frames": []}
	store.availability_changed.emit()
	check(not store.available(), "In-memory data cannot enable replay")
	current_scene._start()
	await wait_frames()
	var game = current_scene
	check(game.pause_menu.buttons[3].disabled and game.pause_menu.buttons[3].focus_mode == Control.FOCUS_NONE, "Pause replay action disabled without focus")
	check(store.frames.is_empty() and not is_instance_valid(store.game), "Game entry does not record")
	game.entrance.step(game.entrance.TOTAL_TIME)
	Input.action_press("move_right")
	for i in 10:
		await physics_frame
		await process_frame
	Input.action_release("move_right")
	store.capture()
	store.finish()
	check(store.frames.is_empty() and store.previous.is_empty() and store.sounds.is_empty(), "Live ticks and explicit capture/finish create no recording")
	game.pause_menu.buttons[3].pressed.emit()
	await wait_frames()
	check(current_scene == game, "Forced pause replay signal cannot launch playback")
	game._clear_stage()
	await wait_frames()
	check(game.cleared and store.frames.is_empty(), "Clear still works without recording")
	check(FileAccess.get_file_as_bytes(TEST_PATH) == sentinel and not FileAccess.file_exists(TEST_PATH + ".tmp"), "Clear never overwrites saved replay or writes temporary file")
	game.restart()
	await wait_frames()
	check(store.frames.is_empty() and not is_instance_valid(store.game), "Retry does not restart recording")
	change_scene_to_file("res://scenes/replay.tscn")
	await wait_frames(5)
	check(current_scene.scene_file_path == "res://scenes/title.tscn", "Direct replay scene returns safely to title")
	store.latest = {}
	DirAccess.remove_absolute(TEST_PATH)
	store.save_path = TEST_PATH + ".new"
	DirAccess.remove_absolute(store.save_path)
	store.finish()
	check(not FileAccess.file_exists(store.save_path), "Disabled replay cannot create a new save")
	print("Replay disabled: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
