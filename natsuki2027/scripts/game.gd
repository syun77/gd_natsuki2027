extends Node2D
## Fixed-step owner: platforms -> validate / input -> gum -> player -> presentation.
const Checkpoint = preload("res://scripts/checkpoint.gd")
const MovingPlatform = preload("res://scripts/moving_platform.gd")
const ContactPickup = preload("res://scripts/contact_pickup.gd")
const OneUpCollectible = preload("res://scripts/one_up_collectible.gd")
const Settings = preload("res://scripts/game_settings.gd")
const TIME_ATTACK_RECORD := "user://time_attack_sprint.cfg"
const SPIKE_LAYER := 64
const RESPAWN_META := &"checkpoint_respawn"
const INITIAL_LIVES := 3
const CLEAR_BONUS := 1000
const TIME_BONUS_PER_SECOND := 10
const TIME_LIMIT := 180.0
const TIME_WARNING := 30.0
var active_checkpoint: NodePath
@export var settings: Settings
@export var stage_scene: PackedScene
@export var stage_width := 5120
@export var fall_restart_offset := 0.0
var elapsed := 0.0
var best_time := 0.0
var debug_checkpoint_used := false
var timer_label: Label
var timer_gauge: ProgressBar
var collected_items: Dictionary = {}
var note_count := 0
var star_count := 0
var new_best := false
var result_data: Dictionary = {}
var score := 0
var lives_remaining := INITIAL_LIVES
var dying := false
var game_over := false
var death_voice: AudioStreamPlayer
var lives_label: Label
var lives_blink: Tween
var cleared := false
var exit_door: Sprite2D
var entrance: Sprite2D
var pause_menu: CanvasLayer
var suppress_gameplay_tick := false
@onready var player: CharacterBody2D = $Player
@onready var player_shape: CollisionShape2D = $Player/CollisionShape2D
@onready var camera: Camera2D = $Camera2D
@onready var gum: Node2D = $Gum
var spike_sweep: ShapeCast2D
var restarting := false
var preserve_bgm_on_exit := false
var death_effect: Sprite2D
var aim_direction := Vector2.RIGHT
var up_wait_release := false
var down_wait_release := false
var manual_down_pressed := false

func _exit_tree() -> void:
	if game_over or cleared:
		get_tree().paused = false
	BackgroundMusic.process_mode = Node.PROCESS_MODE_PAUSABLE
	if not preserve_bgm_on_exit:
		BackgroundMusic.stop()

func _ready() -> void:
	BackgroundMusic.start()
	_setup_stage()
	$TheaterStage/MovingPlatformRoutes.bind(settings)
	_setup_pickups()
	spike_sweep = ShapeCast2D.new()
	spike_sweep.shape = player_shape.shape
	spike_sweep.collision_mask = SPIKE_LAYER
	spike_sweep.collide_with_areas = true
	spike_sweep.collide_with_bodies = false
	spike_sweep.margin = 0.0
	spike_sweep.enabled = false
	add_child(spike_sweep)
	player.settings = settings
	gum.settings = settings
	player.global_position = $TheaterStage/PlacementMarkers/PlayerSpawn.global_position
	_setup_checkpoints()
	if stage_scene != null:
		for prop in [$LightBox, $HeavyBox, $PuzzleLightBox, $PuzzleHeavyBox, $PulleyTrolley]:
			prop.free()
	else:
		_setup_puzzle_props()
	_setup_timer()
	gum.player = player
	player.gum = gum
	$GumAttachmentEffect.bind(gum)
	$GumShotParticles.bind(gum, settings)
	$GumHitParticles.bind(gum, settings)
	$GumHitShockwave.bind(gum, settings)
	$LandingDustEffect.bind(player)
	_setup_pause_menu()
	aim_direction = Vector2.LEFT if player.sprite.flip_h else Vector2.RIGHT
	camera.position = player.position
	camera.zoom = Vector2.ONE * settings.camera_normal_zoom
	_setup_entrance()
	_setup_exit()
	ReplayStore.begin(self)

func _setup_puzzle_props() -> void:
	$PuzzleLightBox.global_position = $TheaterStage/PlacementMarkers/LightBoxSpawn.global_position
	$PuzzleHeavyBox.global_position = $TheaterStage/PlacementMarkers/HeavyBoxSpawn.global_position
	$PulleyTrolley.bind(gum)

func _setup_timer() -> void:
	timer_label = $HUD/Timer
	timer_label.show()
	var record := ConfigFile.new()
	if record.load(TIME_ATTACK_RECORD) == OK:
		best_time = record.get_value("record", "seconds", 0.0)
	timer_gauge = $HUD/TimeGauge
	_update_timer()

func _update_timer() -> void:
	var remaining := maxf(TIME_LIMIT - elapsed, 0.0)
	var seconds := _remaining_seconds()
	timer_label.text = "%sTIME %d:%02d" % ["DEBUG " if debug_checkpoint_used else "", seconds / 60, seconds % 60]
	timer_gauge.value = remaining
	var warning := remaining <= TIME_WARNING
	var red_phase := int(floor((TIME_WARNING - remaining) / 0.35)) % 2 == 0
	timer_label.modulate = Color(1.0, 0.2, 0.2) if warning and red_phase else Color.WHITE
	timer_gauge.modulate = Color(1.0, 0.2, 0.2) if warning else Color.WHITE

func _finish_time_attack() -> void:
	if debug_checkpoint_used:
		_update_timer()
		return
	if best_time <= 0.0 or elapsed < best_time:
		new_best = true
		best_time = elapsed
		var record := ConfigFile.new()
		record.set_value("record", "seconds", best_time)
		var error := record.save(TIME_ATTACK_RECORD)
		if error != OK:
			push_warning("Cannot save Time Attack record: %s" % error_string(error))
	_update_timer()

func _setup_pickups() -> void:
	if get_tree().has_meta(RESPAWN_META):
		var saved: Dictionary = get_tree().get_meta(RESPAWN_META)
		if saved.get("scene") == scene_file_path:
			collected_items = saved.get("collected_items", {}).duplicate()
			score = saved.get("score", 0)
			note_count = saved.get("note_count", 0)
			star_count = saved.get("star_count", 0)
			lives_remaining = saved.get("lives_remaining", INITIAL_LIVES)
	$HUD/Score.text = "SCORE: %d" % score
	lives_label = $HUD/Lives
	_update_lives()
	_register_pickups($TheaterStage)

func _register_pickups(host: Node) -> void:
	if host is TileMapLayer:
		host.update_internals()
	for child in host.get_children():
		if child is ContactPickup or child is OneUpCollectible:
			# Capture the placed position before gum reeling can move the item.
			child.collection_allowed = can_collect
			var key := "%s:%s" % [get_path_to(host), child.position]
			if collected_items.has(key):
				host.remove_child(child)
				child.queue_free()
				continue
			child.collected.connect(_collect_pickup.bind(key, child))
		else:
			_register_pickups(child)

func _collect_pickup(key: String, item: Node) -> void:
	if collected_items.has(key):
		return
	collected_items[key] = true
	if item is OneUpCollectible:
		_add_life()
	else:
		if item.kind == ContactPickup.Kind.NOTE:
			note_count += 1
		else:
			star_count += 1
		_add_score(item.points)

func _add_life() -> void:
	lives_remaining += 1
	_update_lives()

func _update_lives() -> void:
	lives_label.text = "LIFE × %d" % maxi(lives_remaining - 1, 0)
	if lives_remaining <= 1:
		if lives_blink == null:
			lives_label.modulate = Color(1.0, 0.2, 0.2)
			lives_blink = create_tween().set_loops()
			lives_blink.tween_interval(0.35)
			lives_blink.tween_property(lives_label, "modulate", Color.WHITE, 0.0)
			lives_blink.tween_interval(0.35)
			lives_blink.tween_property(lives_label, "modulate", Color(1.0, 0.2, 0.2), 0.0)
	else:
		if lives_blink != null:
			lives_blink.kill()
			lives_blink = null
		lives_label.modulate = Color.WHITE

func can_collect() -> bool:
	return not (dying or game_over or cleared or restarting or (is_instance_valid(exit_door) and exit_door.started))

func _add_score(points: int) -> void:
	score += points
	$HUD/Score.text = "SCORE %d" % score

func _setup_pause_menu() -> void:
	pause_menu = preload("res://scripts/pause_menu.gd").new()
	add_child(pause_menu)
	pause_menu.retry_requested.connect(restart)
	pause_menu.back_requested.connect(return_to_title)
	pause_menu.add_replay_action(func(): ReplayStore.play("res://scenes/title.tscn"))
	pause_menu.add_checkpoint_action(_debug_checkpoint_entries)
	pause_menu.checkpoint_selected.connect(_debug_move_to_checkpoint)
	pause_menu.resumed.connect(func(): suppress_gameplay_tick = true)

func _debug_checkpoint_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var checkpoints := get_node_or_null("TheaterStage/Checkpoints")
	if checkpoints == null:
		return entries
	var spawn: Vector2 = $TheaterStage/PlacementMarkers/PlayerSpawn.global_position
	for checkpoint in checkpoints.get_children():
		if checkpoint is Checkpoint:
			entries.append({"path": get_path_to(checkpoint),
				"distance": spawn.distance_squared_to(checkpoint.global_position)})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.distance == b.distance:
			return str(a.path) < str(b.path)
		return a.distance < b.distance
	)
	for index in entries.size():
		entries[index].number = index + 1
	return entries

func _debug_move_to_checkpoint(path: NodePath) -> void:
	var checkpoint := get_node_or_null(path) as Checkpoint
	if restarting or game_over or checkpoint == null or checkpoint.get_parent() != get_node_or_null("TheaterStage/Checkpoints"):
		return
	debug_checkpoint_used = true
	active_checkpoint = path
	restart(true)

func _setup_entrance() -> void:
	entrance = preload("res://scripts/stage_entrance.gd").new()
	entrance.name = "StageEntrance"
	add_child(entrance)
	move_child(entrance, player.get_index())
	var spawn: Vector2 = $TheaterStage/PlacementMarkers/PlayerSpawn.global_position
	entrance.global_position = _door_floor_position(spawn)
	if active_checkpoint.is_empty():
		player.global_position = entrance.global_position
		player.reset_motion()
		entrance.begin(player.sprite)
		gum.hide()
		camera.position = player.position

func _door_floor_position(marker_position: Vector2) -> Vector2:
	var query := PhysicsRayQueryParameters2D.create(marker_position - Vector2(0, 1), marker_position + Vector2(0, 64), 1)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() else marker_position

func _setup_exit() -> void:
	exit_door = preload("res://scripts/stage_exit.gd").new()
	exit_door.name = "StageExit"
	add_child(exit_door)
	move_child(exit_door, player.get_index())
	exit_door.global_position = _door_floor_position($TheaterStage/PlacementMarkers/Exit.global_position)
	exit_door.player_entered.connect(_begin_exit)

func _begin_exit() -> void:
	if restarting or game_over or dying or cleared or entrance.active or exit_door.started:
		return
	_finish_time_attack()
	var vertical_speed: float = player.velocity.y
	gum.detach("STAGE EXIT")
	gum.hide()
	player.reset_motion()
	player.afterimages.clear()
	$LandingDustEffect.stop()
	exit_door.begin(player, vertical_speed)

func _setup_stage() -> void:
	if stage_scene != null:
		var old_stage := $TheaterStage
		var stage_index := old_stage.get_index()
		remove_child(old_stage)
		old_stage.free()
		var selected_stage := stage_scene.instantiate()
		selected_stage.name = "TheaterStage"
		add_child(selected_stage)
		move_child(selected_stage, stage_index)
	camera.limit_right = stage_width
	var prop_markers := {"LightBox": "EntranceLightBox", "HeavyBox": "EntranceHeavyBox", "PulleyTrolley": "PulleySpawn"}
	for prop in prop_markers:
		var placement := get_node_or_null("TheaterStage/PlacementMarkers/" + prop_markers[prop])
		if placement != null:
			get_node(prop).position = placement.position

func _physics_process(delta: float) -> void:
	if restarting or cleared or game_over:
		return
	if suppress_gameplay_tick:
		suppress_gameplay_tick = false
		return
	if Input.is_action_just_pressed("restart"):
		restart()
		return
	if exit_door.active:
		player.reset_motion()
		exit_door.step(delta)
		if not player.sprite.visible and player.visible:
			player.hide()
			player.collision_layer = 0
			player.collision_mask = 0
		if not exit_door.active:
			_clear_stage()
		return
	if entrance.active:
		player.reset_motion()
		entrance.step(delta)
		up_wait_release = Input.is_action_pressed("aim_up")
		down_wait_release = Input.is_action_pressed("aim_down")
		if not entrance.active:
			gum.show()
		return
	elapsed = minf(elapsed + delta, TIME_LIMIT)
	_update_timer()
	if elapsed >= TIME_LIMIT:
		_show_game_over("TIME UP")
		return
	if is_instance_valid(death_effect):
		if death_effect.step(delta):
			_finish_death()
		return
	if player.position.y > settings.restart_y + fall_restart_offset:
		if _begin_death():
			_finish_death()
		return
	var previous_shape_transform: Transform2D = player_shape.global_transform
	if _touches_spikes(previous_shape_transform, Vector2.ZERO):
		_die_on_spikes(previous_shape_transform.origin)
		return
	var platforms := get_node_or_null("TheaterStage/MovingPlatforms")
	if platforms:
		for platform in platforms.get_children():
			if platform is MovingPlatform:
				platform.step(delta)
	gum.validate_connection()
	var was_reeling: bool = gum.reeling_one_up()
	var jump_requested := Input.is_action_just_pressed("jump") and not was_reeling
	var attached_jump: bool = jump_requested and gum.connected() and not was_reeling
	_update_direction()
	var length_input := _read_length_input(jump_requested)
	_handle_actions(jump_requested)
	gum.step(delta, length_input)
	player.one_up_reel_locked = was_reeling or gum.reeling_one_up()
	player.simulate(delta, jump_requested, attached_jump)
	var movement: Vector2 = player_shape.global_position - previous_shape_transform.origin
	if _touches_spikes(previous_shape_transform, movement):
		_die_on_spikes(previous_shape_transform.origin + movement * spike_sweep.get_closest_collision_safe_fraction())
		return
	_update_camera(delta)
	gum.update_aim(_aim_target())

func _setup_checkpoints() -> void:
	var checkpoints := get_node_or_null("TheaterStage/Checkpoints")
	if checkpoints != null:
		for checkpoint in checkpoints.get_children():
			checkpoint.reached.connect(_on_checkpoint_reached)
	if not get_tree().has_meta(RESPAWN_META):
		return
	var saved: Dictionary = get_tree().get_meta(RESPAWN_META)
	get_tree().remove_meta(RESPAWN_META)
	if saved.get("scene") != scene_file_path:
		return
	debug_checkpoint_used = saved.get("debug_checkpoint_used", false)
	if debug_checkpoint_used:
		suppress_gameplay_tick = true
	elapsed = saved.get("elapsed", 0.0)
	var checkpoint = get_node_or_null(saved.get("checkpoint", NodePath()))
	if checkpoint != null and checkpoint.get_parent() == checkpoints:
		active_checkpoint = get_path_to(checkpoint)
		checkpoint.activate(false)
		player.global_position = checkpoint.respawn_position()

func _on_checkpoint_reached(checkpoint: Area2D) -> void:
	if restarting or game_over or dying or cleared or exit_door.started:
		return
	if not checkpoint.activated:
		SoundEffects.play(&"checkpoint")
	active_checkpoint = get_path_to(checkpoint)
	checkpoint.activate()

func _die_on_spikes(center: Vector2) -> void:
	if not _begin_death():
		return
	gum.detach("SPIKES")
	gum.hide()
	player.hide()
	player.afterimages.clear()
	$LandingDustEffect.stop()
	death_effect = preload("res://scripts/player_death_effect.gd").new()
	add_child(death_effect)
	death_effect.start(center)
	camera.global_position = center - player_shape.position

func _begin_death() -> bool:
	if dying or game_over or cleared or restarting or exit_door.started:
		return false
	dying = true
	lives_remaining -= 1
	_update_lives()
	death_voice = SoundEffects.play(&"dead")
	death_voice.process_mode = Node.PROCESS_MODE_ALWAYS
	return true

func _finish_death() -> void:
	if lives_remaining > 0:
		restart(true)
	else:
		_show_game_over()

func _show_game_over(caption := "GAME OVER") -> void:
	if game_over or cleared:
		return
	game_over = true
	for child in get_children():
		child.process_mode = Node.PROCESS_MODE_PAUSABLE
	process_mode = Node.PROCESS_MODE_ALWAYS
	ReplayStore.suspend(false)
	pause_menu.close()
	pause_menu.set_process_input(false)
	get_tree().paused = true
	gum.detach("GAME OVER")
	gum.hide()
	player.reset_motion()
	player.hide()
	player.afterimages.clear()
	if is_instance_valid(death_effect):
		death_effect.queue_free()
	if get_tree().has_meta(RESPAWN_META):
		get_tree().remove_meta(RESPAWN_META)
	if is_instance_valid(death_voice) and death_voice.playing:
		death_voice.finished.connect(_present_game_over_results.bind(caption), CONNECT_ONE_SHOT)
	else:
		_present_game_over_results(caption)

func _present_game_over_results(caption: String) -> void:
	if not restarting:
		_present_results(caption)

func restart(from_checkpoint := false) -> void:
	if restarting:
		return
	restarting = true
	get_tree().paused = false
	preserve_bgm_on_exit = from_checkpoint
	ReplayStore.suspend(from_checkpoint)
	pause_menu.close()
	if from_checkpoint:
		get_tree().set_meta(RESPAWN_META, {
			"scene": scene_file_path, "checkpoint": active_checkpoint, "elapsed": elapsed,
			"debug_checkpoint_used": debug_checkpoint_used,
			"collected_items": collected_items.duplicate(), "score": score,
			"lives_remaining": lives_remaining, "note_count": note_count, "star_count": star_count,
		})
	elif get_tree().has_meta(RESPAWN_META):
		get_tree().remove_meta(RESPAWN_META)
	gum.detach("RESTART")
	$LandingDustEffect.stop()
	$GumShotParticles.stop()
	$GumHitParticles.stop()
	$GumHitShockwave.stop()
	get_tree().call_deferred("reload_current_scene")

func _touches_spikes(start: Transform2D, movement: Vector2) -> bool:
	spike_sweep.global_transform = start
	spike_sweep.target_position = start.basis_xform_inv(movement)
	spike_sweep.force_shapecast_update()
	return spike_sweep.is_colliding()

func _update_camera(delta: float) -> void:
	camera.position = player.position
	var target_zoom: float = settings.camera_normal_zoom
	if gum.connected():
		var start: float = settings.camera_gum_zoom_start
		var end: float = settings.camera_gum_zoom_end
		# Equal/reversed thresholds become a step, avoiding division by zero.
		var weight := float(gum.path.length >= start)
		if end > start:
			weight = clampf((gum.path.length - start) / (end - start), 0.0, 1.0)
		target_zoom = minf(target_zoom, lerpf(settings.camera_normal_zoom, settings.camera_long_gum_zoom, weight))
	var blend := 1.0 - exp(-settings.camera_zoom_response * delta) if settings.camera_zoom_response > 0.0 else 1.0
	camera.zoom = camera.zoom.lerp(Vector2.ONE * target_zoom, blend)

func _aim_target() -> Vector2:
	return gum.origin() + aim_direction * gum.settings.attachment_range

func _read_length_input(jump_requested: bool) -> float:
	var up := Input.is_action_pressed("aim_up")
	var down := Input.is_action_pressed("aim_down")
	up_wait_release = up_wait_release and up
	down_wait_release = down_wait_release and down
	manual_down_pressed = false
	if not gum.connected() or jump_requested:
		up_wait_release = up
		down_wait_release = down
		return 0.0
	manual_down_pressed = down and not down_wait_release
	if manual_down_pressed:
		gum.relax()
	return float(manual_down_pressed) - float(up and not up_wait_release)

func _update_direction() -> void:
	# Quantize keyboard/pad input to eight directions; neutral preserves the last direction.
	var direction := Vector2(Input.get_axis("aim_left", "aim_right"), Input.get_axis("aim_up", "aim_down"))
	if not direction.is_zero_approx():
		aim_direction = direction.sign().normalized()

func _handle_actions(jump_requested: bool) -> void:
	if gum.reeling_one_up():
		return
	if jump_requested:
		gum.detach()
		return
	if not Input.is_action_just_pressed("gum_action"):
		return
	if gum.connected():
		if not manual_down_pressed:
			gum.contract()
	elif gum.state != gum.State.OUTBOUND:
		gum.fire(aim_direction)
		player.fire_gum()

func return_to_title() -> void:
	if restarting:
		return
	get_tree().paused = false
	ReplayStore.suspend(false)
	restarting = true
	pause_menu.close()
	if get_tree().has_meta(RESPAWN_META):
		get_tree().remove_meta(RESPAWN_META)
	gum.detach("TITLE")
	get_tree().call_deferred("change_scene_to_file", "res://scenes/title.tscn")

func _remaining_seconds() -> int:
	return ceili(maxf(TIME_LIMIT - elapsed, 0.0))

func _clear_stage() -> void:
	if cleared or game_over or restarting:
		return
	cleared = true
	var remaining_seconds := _remaining_seconds()
	var time_bonus := remaining_seconds * TIME_BONUS_PER_SECOND
	_add_score(CLEAR_BONUS + time_bonus)
	ReplayStore.finish()
	gum.detach("STAGE CLEAR")
	_present_results("DEBUG CLEAR" if debug_checkpoint_used else "STAGE CLEAR!", CLEAR_BONUS, time_bonus)

func _present_results(caption: String, clear_bonus := 0, time_bonus := 0) -> void:
	result_data = {"notes": note_count, "stars": star_count, "bonus": clear_bonus,
		"remaining_seconds": _remaining_seconds(), "time_bonus": time_bonus,
		"score": score, "elapsed": elapsed, "best": best_time,
		"new_best": new_best, "debug": debug_checkpoint_used,
		"cleared": cleared, "caption": caption}
	pause_menu.close()
	pause_menu.set_process_input(false)
	BackgroundMusic.process_mode = Node.PROCESS_MODE_ALWAYS
	BackgroundMusic.fade_out(1.0)
	get_tree().paused = true
	var results := preload("res://scripts/clear_results.gd").new()
	results.data = result_data.duplicate(true)
	results.replay_failure = ReplayStore.failure if cleared else ""
	$HUD.add_child(results)
	results.title_requested.connect(return_to_title)
