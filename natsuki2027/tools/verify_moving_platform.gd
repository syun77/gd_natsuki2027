extends SceneTree
## Actual physics ticks: motor, one-way contacts, carry, release and Game lifecycle.
const Platform = preload("res://scenes/props/moving_platform.tscn")
var platform
var player
var failures := 0
var moving := false

func _initialize() -> void:
	call_deferred("verify")

func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1

func ticks(count: int, kick := false) -> void:
	for i in count:
		await physics_frame
		if moving:
			platform.step(1.0 / 60.0)
		player.simulate(1.0 / 60.0, kick and i == 0)
		await process_frame

func fixture(direction := "right", speed := 64.0) -> void:
	moving = false
	if is_instance_valid(player): player.free()
	if is_instance_valid(platform): platform.free()
	platform = Platform.instantiate()
	platform.position = Vector2(200, 300)
	platform.direction = direction
	platform.speed = speed
	root.add_child(platform)
	player = load("res://scenes/characters/player.tscn").instantiate()
	player.settings = load("res://resources/game_settings.tres").duplicate()
	player.position = Vector2(248, 280)
	root.add_child(player)
	await ticks(25)
	check(player.is_on_floor(), "fixture lands on top")

func verify() -> void:
	for direction in ["right", "left", "up", "down"]:
		for speed in [32.0, 160.0]:
			await fixture(direction, speed)
			moving = true
			await ticks(8)
			var offset: Vector2 = player.position - platform.position
			for i in 240:
				await ticks(1)
				check(player.is_on_floor(), "%s/%s support at tick %s" % [direction, speed, i])
				check((player.position - platform.position).distance_to(offset) < 0.2, "%s/%s stable relative carry" % [direction, speed])
			var motor_velocity: Vector2 = platform.motion_velocity
			await ticks(1, true)
			check(not player.is_on_floor(), "kick leaves moving floor")
			check(absf(player.external_velocity.x - motor_velocity.x) < 0.1, "horizontal motor momentum inherited once")
			check(absf(player.external_velocity.y - (motor_velocity.y - player.settings.kick_speed + player.settings.gravity / 60.0)) < 0.1, "vertical motor momentum inherited once")
	# Walking off transfers momentum once, including floor-snap-only edge support.
	for direction in ["right", "left"]:
		await fixture(direction, 64)
		moving = true
		await ticks(8)
		var action := "move_right" if direction == "right" else "move_left"
		var expected := 64.0 if direction == "right" else -64.0
		Input.action_press(action)
		for i in 60:
			await ticks(1)
			if not player.is_on_floor(): break
		Input.action_release(action)
		check(not player.is_on_floor() and absf(player.external_velocity.x - expected) < 0.1, "mirrored walk-off inherits motor momentum")
		await ticks(5)
		check(absf(player.external_velocity.x - expected) < 0.1, "walk-off momentum is not added repeatedly")
	# Upward passage and side entry have no underside/side response.
	await fixture("up", 64)
	player.position = Vector2(248, 370)
	player.external_velocity = Vector2(0, -600)
	await ticks(1)
	moving = true
	var minimum: float = player.position.y
	for i in 20:
		await ticks(1)
		minimum = minf(minimum, player.position.y - platform.position.y)
		check(not player.is_on_ceiling(), "no underside head collision")
	check(minimum < -10, "upward player passes rising platform")
	await fixture()
	player.position = Vector2(160, 330)
	player.external_velocity = Vector2(600, 0)
	await ticks(14)
	check(player.position.x > 280 and not player.is_on_wall(), "side passage")
	# Native support at mirrored capsule edges; no diagonal drift.
	for edge in [196.0, 300.0]:
		for offset in [0.0, 7.0, 8.0]:
			await fixture()
			player.position = Vector2(edge + offset * (-1 if edge == 196 else 1), 260)
			player.external_velocity = Vector2(0, 400)
			await ticks(60)
			check(player.is_on_floor(), "edge landing/support")
	# Point queries distinguish the physical 4px overhang from capsule-radius support.
	await fixture()
	for x in [197.0, 299.0, 195.0, 301.0]:
		var point := PhysicsPointQueryParameters2D.new()
		point.position = Vector2(x, 302)
		point.collision_mask = 8
		var hits := root.get_world_2d().direct_space_state.intersect_point(point)
		check(not hits.is_empty() if x in [197.0, 299.0] else hits.is_empty(), "exact collision overhang at x=%s" % x)
	for x in [185.0, 311.0]:
		await fixture()
		player.position = Vector2(x, 260)
		player.external_velocity = Vector2(0, 400)
		await ticks(60)
		check(not player.is_on_floor(), "outside expanded capsule support must fall")
	# Fast landing and drop-through on a floor descending at maximum speed.
	await fixture("down", 160)
	player.position.y = 200
	player.external_velocity = Vector2(0, 1000)
	await ticks(20)
	check(player.is_on_floor(), "fast landing")
	moving = true
	await ticks(10)
	Input.action_press("aim_down")
	await ticks(1, true)
	check(not player.get_collision_mask_value(4) and player.external_velocity.y > 0, "moving-floor drop without kick")
	for i in 75:
		await ticks(1)
		if not player.get_collision_mask_value(4):
			check(not player.is_on_floor(), "ignored platform cannot catch dropping player")
	Input.action_release("aim_down")
	check(player.get_collision_mask_value(4), "drop restores after capsule clearance")
	# Rising-floor drop keeps the collision exception until the whole capsule clears.
	await fixture("up", 160)
	moving = true
	await ticks(10)
	Input.action_press("aim_down")
	await ticks(1, true)
	for i in 75:
		await ticks(1)
		if not player.get_collision_mask_value(4):
			check(not player.is_on_floor(), "rising platform cannot recapture drop")
	Input.action_release("aim_down")
	check(player.get_collision_mask_value(4), "rising-floor drop restores collision")
	# Box uses real reciprocal engine contacts; motor remains on its path.
	await fixture("right", 64)
	player.position = Vector2(-1000, -1000)
	var box = load("res://scenes/props/gum_box.tscn").instantiate()
	box.position = Vector2(248, 260)
	root.add_child(box)
	await ticks(45)
	moving = true
	await ticks(60)
	check(absf(box.position.y - 280) < 2, "rigid box rests on moving top")
	check(box.position.x > 280, "rigid box carried horizontally")
	var ray := PhysicsRayQueryParameters2D.create(Vector2(platform.position.x + 48, 220), Vector2(platform.position.x + 48, 380), 53)
	ray.exclude = [box.get_rid(), player.get_rid()]
	check(root.get_world_2d().direct_space_state.intersect_ray(ray).is_empty(), "gum ray ignores motor floor")
	box.free()
	# Width changes update independent collision resources and 9-slice geometry.
	platform.width_cells = 6
	check(platform.get_node("Surface").size == Vector2(192, 10), "nine-slice target width")
	check(platform.get_node("CollisionShape2D").shape.size == Vector2(200, 5), "collision extends four pixels on each side")
	var second = Platform.instantiate()
	root.add_child(second)
	check(second.get_node("CollisionShape2D").shape.size.x == 104, "width does not mutate shared shape")
	second.free()
	player.free()
	platform.free()
	# Saved gameplay owns progression: entrance/exit/death freeze motor, gameplay advances.
	var game = load("res://scenes/game_time_attack.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var saved = game.get_node("TheaterStage/MovingPlatforms").get_child(0)
	var initial: Vector2 = saved.position
	game._physics_process(0.1)
	check(saved.elapsed == 0 and saved.position == initial, "entrance freezes platforms")
	game._physics_process(game.entrance.TOTAL_TIME)
	game._physics_process(1.0 / 60.0)
	check(saved.elapsed > 0, "Game advances platform during gameplay")
	game.suppress_gameplay_tick = true
	var clock: float = saved.elapsed
	game._physics_process(1.0 / 60.0)
	check(saved.elapsed == clock, "resume suppression does not advance clock")
	game.free()
	var reset_game = load("res://scenes/game_time_attack.tscn").instantiate()
	root.add_child(reset_game)
	check(reset_game.get_node("TheaterStage/MovingPlatforms").get_child(0).elapsed == 0, "scene recreation resets motor")
	reset_game.free()
	if failures == 0:
		print("PASS: moving platform directions/speeds/reversals, carry/momentum, one-way passage/drop, box/gum, nine-slice and Game lifecycle")
	quit(1 if failures else 0)
