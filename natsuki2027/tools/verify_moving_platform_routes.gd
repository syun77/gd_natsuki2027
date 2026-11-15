extends SceneTree
const Platform = preload("res://scenes/props/moving_platform.tscn")
const Routes = preload("res://scripts/moving_platform_routes.gd")
const RouteScene = preload("res://scenes/props/moving_platform_routes.tscn")
var failures := 0

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(1))
	call_deferred("verify")

func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1

func flush() -> void:
	await process_frame
	await process_frame

func verify() -> void:
	var stage := Node2D.new()
	stage.position = Vector2(30,40)
	root.add_child(stage)
	var group := Node2D.new()
	group.name = "MovingPlatforms"
	group.position = Vector2(64,32)
	stage.add_child(group)
	var guide = RouteScene.instantiate()
	stage.add_child(guide)
	var settings = load("res://resources/game_settings.tres").duplicate()
	guide.bind(settings)
	for direction in ["up", "down", "left", "right"]:
		for distance in [1,4,8]:
			for width in [1,3,6]:
				var platform = Platform.instantiate()
				platform.position = Vector2(64,64)
				platform.direction = direction
				platform.travel_cells = distance
				platform.width_cells = width
				group.add_child(platform)
				await flush()
				var points: PackedVector2Array = guide.points
				var a := group.position + Vector2(64 + width*16,69)
				var b: Vector2 = a + platform.DIRECTIONS[direction]*distance*32
				check(points.size() == (distance*4+2)*2, "dash/stop count")
				check(points[0].is_equal_approx(a), "stage-space start and y5 offset")
				check(((points[-4]+points[-3])*0.5).is_equal_approx(a), "first end stop")
				check(((points[-2]+points[-1])*0.5).is_equal_approx(b), "last end stop")
				for i in range(0,points.size()-4,2):
					check(is_equal_approx(points[i].distance_to(points[i+1]),4), "4px dash")
				check(is_equal_approx(points[-2].distance_to(points[-1]),8), "8px stopper")
				var immutable := points.duplicate()
				for i in 3:
					await physics_frame
					platform.step(1.0/60.0)
					await process_frame
				check(guide.points == immutable, "moving floor cannot move route")
				platform.width_cells = 2
				platform.travel_cells = 2
				await flush()
				check(guide.points[0].is_equal_approx(group.position+Vector2(96,69)), "parameter edits update route, not current floor position")
				var changed: Dictionary = platform.placement().merged({"x":9,"y":8,"direction":"left","travel_cells":1,"width_cells":1},true)
				platform.configure(changed)
				await flush()
				check(guide.points[0].is_equal_approx(group.position+Vector2(304,261)), "live configure uses new saved origin despite physics sync")
				platform.free()
				await flush()
				check(guide.points.is_empty(), "deletion removes route")
	# Trim the last dash rather than extending past a non-grid endpoint.
	var clipped := PackedVector2Array()
	Routes.append_route(clipped,Vector2.ZERO,Vector2(10,0))
	check(clipped[2] == Vector2(8,0) and clipped[3] == Vector2(10,0), "dash clipped at endpoint")
	var floor = Platform.instantiate()
	group.add_child(floor)
	await flush()
	var before: PackedVector2Array = guide.points.duplicate()
	settings.moving_platform_route_enabled = false
	check(guide.color.a == 0 and guide.points == before and guide.visible, "disabled appearance keeps stable replay batch")
	settings.moving_platform_route_color = Color(0.3,0.4,0.5,0.7)
	check(guide.color.a == 0, "color change does not re-enable guide")
	settings.moving_platform_route_enabled = true
	check(guide.color == settings.moving_platform_route_color, "shared visibility/color change applies immediately")
	check(guide.get_child_count() == 0 and not guide is CollisionObject2D, "one batch without physical nodes")
	var snapshot := {}
	var store := root.get_node("ReplayStore")
	store._collect(stage,snapshot)
	var visual: Dictionary = snapshot[guide.get_instance_id()]
	check(visual.kind == "segments" and visual.points == before and store._valid_visual(visual), "replay includes fixed route geometry/color")
	var invalid := visual.duplicate(true)
	invalid.points.append(Vector2.ZERO)
	check(not store._valid_visual(invalid), "replay rejects odd segment list")
	invalid = visual.duplicate(true)
	invalid.width = NAN
	check(not store._valid_visual(invalid), "replay rejects invalid thickness")
	stage.free()
	# Real Game setup: both saved stages put guide after backgrounds and before solids.
	for scene in ["res://scenes/game.tscn", "res://scenes/game_time_attack.tscn"]:
		var game = load(scene).instantiate()
		root.add_child(game)
		game.set_physics_process(false)
		await flush()
		var saved: Node = game.get_node("TheaterStage")
		var routes = saved.get_node("MovingPlatformRoutes")
		check(saved.get_index() < game.player.get_index(), "stage remains behind player after replacement")
		check(routes.get_index() < saved.get_node("TerrainTiles").get_index(), "guide behind solids")
		for name in ["Background", "BackgroundIron", "BackgroundDecor"]:
			if saved.has_node(name): check(saved.get_node(name).get_index() < routes.get_index(), "guide in front of background")
		check(routes.settings == game.settings and routes.width == 2.0, "Game binds actual shared settings")
		var fixed_points: PackedVector2Array = routes.points.duplicate()
		if scene == "res://scenes/game_time_attack.tscn":
			check(not fixed_points.is_empty(), "Time Attack saved routes visible")
		game._physics_process(game.entrance.TOTAL_TIME)
		for i in 5:
			await physics_frame
			game._physics_process(1.0/60.0)
			await process_frame
		check(routes.points == fixed_points, "Game updates do not move paths")
		game.pause_menu.open()
		await create_timer(0.03,true).timeout
		check(routes.points == fixed_points, "pause keeps path visible and fixed")
		game.pause_menu.close()
		game.free()
	if failures == 0:
		print("PASS: platform routes 36 layouts, fixed geometry, edits/removal, appearance, replay schema and stage layering")
	quit(1 if failures else 0)
