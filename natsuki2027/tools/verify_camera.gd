extends SceneTree
var failures := 0

func _initialize() -> void:
	call_deferred("verify")

func check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		failures += 1

func key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_X
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func verify() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	game._physics_process(game.entrance.TOTAL_TIME)
	game.set_physics_process(false)
	# Isolate camera timing without changing the shared resource on disk.
	game.settings = game.settings.duplicate()
	var settings = game.settings
	game.gum.settings = settings
	settings.maximum_length = 900.0
	settings.attachment_range = 900.0
	check(game.camera.zoom.is_equal_approx(Vector2.ONE * settings.camera_normal_zoom), "Spawn uses close normal zoom")
	settings.camera_zoom_response = 0.0
	key(true)
	game._update_camera(1.0)
	check(is_equal_approx(game.camera.zoom.x, settings.camera_normal_zoom), "Unattached X never changes zoom")
	key(false)
	game._update_camera(0.01)
	check(is_equal_approx(game.camera.zoom.x, settings.camera_normal_zoom), "Release keeps normal view")
	# Real ray attachment provides the connection; only the measured path is varied.
	check(game.gum.attach_at(game.gum.origin() + Vector2.UP * 800.0), "Camera fixture attaches to saved-map ceiling")
	game.gum.path.length = settings.camera_gum_zoom_start
	game._update_camera(0.01)
	check(is_equal_approx(game.camera.zoom.x, settings.camera_normal_zoom), "Short connection stays close")
	key(true)
	game._update_camera(1.0)
	check(is_equal_approx(game.camera.zoom.x, settings.camera_normal_zoom), "Attached X never widens view or accumulates hold")
	key(false)
	game.gum.path.length = (settings.camera_gum_zoom_start + settings.camera_gum_zoom_end) * 0.5
	game._update_camera(0.01)
	check(is_equal_approx(game.camera.zoom.x, (settings.camera_normal_zoom + settings.camera_long_gum_zoom) * 0.5), "Path midpoint interpolates zoom")
	game.gum.path.length = settings.camera_gum_zoom_end + 100.0
	key(true)
	game._update_camera(1.0)
	check(is_equal_approx(game.camera.zoom.x, settings.camera_long_gum_zoom), "Long connection wins over held X and clamps at maximum distance")
	key(false)
	settings.camera_gum_zoom_end = settings.camera_gum_zoom_start
	game._update_camera(0.01)
	check(is_equal_approx(game.camera.zoom.x, settings.camera_long_gum_zoom), "Equal thresholds remain finite")
	key(true)
	game.gum.detach()
	game._update_camera(0.01)
	check(is_equal_approx(game.camera.zoom.x, settings.camera_normal_zoom), "Detach returns to normal view regardless of held X")
	key(false)
	# Start wide to measure the smooth return.
	game.camera.zoom = Vector2.ONE * settings.camera_long_gum_zoom
	settings.camera_zoom_response = 5.0
	var initial: float = game.camera.zoom.x
	game._update_camera(0.1)
	check(game.camera.zoom.x > initial and game.camera.zoom.x < settings.camera_normal_zoom, "Detach smoothly restores close view")
	var one_step: float = game.camera.zoom.x
	game.camera.zoom = Vector2.ONE * initial
	game._update_camera(0.05)
	game._update_camera(0.05)
	check(is_equal_approx(game.camera.zoom.x, one_step), "Exponential transition is independent of timestep subdivision")
	check(game.camera.position == game.player.position, "Camera continues player follow")
	game.free()
	var time_game = load("res://scenes/game_time_attack.tscn").instantiate()
	root.add_child(time_game)
	time_game.set_physics_process(false)
	var camera: Camera2D = time_game.camera
	var map_right := 0.0
	for child in time_game.get_node("TheaterStage").get_children():
		if child is Polygon2D and child.z_index == -10:
			for point in child.polygon:
				map_right = maxf(map_right, point.x)
	check(camera.limit_right == 692 * 32 and camera.limit_right == int(map_right), "Time Attack camera limit matches full saved map width")
	camera.position_smoothing_enabled = false
	var half_width := root.get_visible_rect().size.x / camera.zoom.x / 2.0
	for target_x in [7000.0, map_right - half_width - 64.0, map_right]:
		time_game.player.position = Vector2(target_x, 384)
		time_game._update_camera(1.0)
		camera.force_update_scroll()
		await process_frame
		var expected := minf(target_x, map_right - half_width)
		check(absf(camera.get_screen_center_position().x - expected) < 1.0, "Camera follows full map and clamps viewport at right edge: %s" % target_x)
	time_game.free()
	if failures == 0:
		print("PASS: camera zoom and full Time Attack map scrolling")
	quit(1 if failures else 0)
