extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("verify")
func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1
func tick(game: Node) -> void:
	await physics_frame
	game._physics_process(1.0 / 60.0)
	await process_frame
func add_one_up(point: Vector2) -> Node2D:
	var item = load("res://scenes/items/one_up.tscn").instantiate()
	item.position = point
	root.add_child(item)
	return item
func verify() -> void:
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	game._physics_process(game.entrance.TOTAL_TIME)
	game.set_physics_process(false)
	game.settings = game.settings.duplicate()
	game.settings.one_up_reel_speed = 200.0
	game.settings.attachment_range = 400.0
	game.settings.maximum_length = 500.0
	game.settings.gum_shot_speed = 2400.0
	game.player.settings = game.settings
	game.gum.settings = game.settings
	var player = game.player
	var gum = game.gum
	player.position = Vector2(800, -300)
	player.external_velocity = Vector2(100, 70)
	var item = add_one_up(gum.origin() + Vector2(120, 0))
	await physics_frame
	var wall := StaticBody2D.new()
	wall.position = gum.origin() + Vector2(50, 0)
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10, 80)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	root.add_child(wall)
	await physics_frame
	check(gum.cast_to(item.position).collider == wall, "Terrain occludes item targeting")
	wall.queue_free()
	await process_frame
	await physics_frame
	check(gum.attachable(gum.cast_to(item.position)), "Preview ray recognizes item Area")
	gum.fire(Vector2.RIGHT)
	for i in 15:
		await tick(game)
		if gum.reeling_one_up():
			break
	check(gum.reeling_one_up(), "Actual swept tip hits and starts reel")
	check(player.velocity == Vector2.ZERO and player.external_velocity == Vector2.ZERO and player.control_velocity == Vector2.ZERO, "Arrival resets all momentum")
	var frozen: Vector2 = player.position
	Input.action_press("move_right")
	Input.action_press("jump")
	Input.action_press("gum_action")
	var previous_distance: float = item.position.distance_to(player.gum_visual_origin())
	for i in 120:
		await tick(game)
		check(player.position == frozen and player.velocity == Vector2.ZERO, "Lock holds position and suppresses gravity/movement/jump")
		check(gum.player_force == Vector2.ZERO and gum.target_force == Vector2.ZERO, "OneUp reel bypasses ordinary spring force")
		if not gum.reeling_one_up():
			break
		var distance: float = item.position.distance_to(player.gum_visual_origin())
		check(distance < previous_distance, "OneUp moves toward hand")
		previous_distance = distance
	check(not is_instance_valid(item), "Reaching hand collects item")
	var popup := root.get_node_or_null("ScorePopup") as Label
	check(popup != null and popup.text == "1UP", "Gum collection displays 1UP")
	check(get_nodes_in_group("one_up_collect_effects").size() == 1, "Successful reel spawns collection burst")
	check(player.one_up_jump_available and gum.state == gum.State.READY, "Successful collection grants jump and restores ready")
	Input.action_release("jump")
	Input.action_release("gum_action")
	Input.action_release("move_right")
	await tick(game)
	check(player.velocity.y > 0 and not player.one_up_reel_locked, "Gravity resumes after reel")
	Input.action_press("jump")
	await tick(game)
	Input.action_release("jump")
	check(player.velocity.y < -350 and not player.one_up_jump_available, "Fresh Z jumps in air and consumes reward")
	await tick(game)
	Input.action_press("jump")
	await tick(game)
	Input.action_release("jump")
	check(is_equal_approx(player.external_velocity.y, -game.settings.double_jump_kick_speed) and not player.air_jump_available, "OneUp reward preserves the separate one-use double jump")
	await tick(game)
	var before: float = player.external_velocity.y
	Input.action_press("jump")
	await tick(game)
	Input.action_release("jump")
	check(player.external_velocity.y > before, "Exhausted item reward and air allowance reject a third jump")
	player.reset_motion()
	item = add_one_up(gum.origin() + Vector2(100, 0))
	await physics_frame
	check(gum.attach_at(item.position), "Direct item fixture attaches")
	item.queue_free()
	await process_frame
	await tick(game)
	check(not player.one_up_reel_locked and not player.one_up_jump_available, "Deleted target releases lock without jump reward")
	item = add_one_up(gum.origin() + Vector2(100, 0))
	await physics_frame
	check(gum.attach_at(item.position), "Restart fixture attaches")
	gum.detach("RESTART")
	await tick(game)
	check(not player.one_up_reel_locked and not item.being_pulled and not player.one_up_jump_available, "Restart cleanup releases item and lock")
	item.queue_free()
	var floor_body := StaticBody2D.new()
	floor_body.position = player.position + Vector2(0, 20)
	var floor_shape := CollisionShape2D.new()
	var floor_rect := RectangleShape2D.new()
	floor_rect.size = Vector2(400, 40)
	floor_shape.shape = floor_rect
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	for i in 5:
		await tick(game)
	check(player.is_on_floor(), "Ground reel fixture has actual support")
	item = add_one_up(gum.origin() + Vector2(100, 0))
	await physics_frame
	check(gum.attach_at(item.position), "Grounded item can attach")
	frozen = player.position
	for i in 90:
		await tick(game)
		check(player.position == frozen, "Grounded player remains fixed through collection")
		if not gum.reeling_one_up():
			break
	check(not is_instance_valid(item) and player.one_up_jump_available, "Grounded reel also completes")
	Input.action_press("jump")
	await tick(game)
	Input.action_release("jump")
	check(player.velocity.y < -350, "Grounded player jumps after completion")
	floor_body.queue_free()
	game.queue_free()
	await process_frame
	print("OneUp reel: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
