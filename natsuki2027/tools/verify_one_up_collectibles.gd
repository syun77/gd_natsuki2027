extends SceneTree
var failures := 0
var pickups := 0
const Layout = preload("res://scripts/stage_layout.gd")
func _initialize() -> void:
	call_deferred("verify")
func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1
func ticks() -> void:
	for i in 5:
		await physics_frame
func verify() -> void:
	var stage = load("res://scenes/stages/theater_stage.tscn").instantiate()
	root.add_child(stage)
	var layer: TileMapLayer = stage.get_node("Foods")
	await ticks()
	check(layer.get_used_cells().size() == 36, "Saved map has36 pickups")
	check(layer.get_child_count() == 36, "Saved items instantiate")
	var variants := {}
	var sections := [0, 0, 0, 0, 0, 0]
	for item in Layout.ONE_UPS:
		var cell := Vector2i(item.x, item.y)
		check(layer.get_cell_alternative_tile(cell) == item.z, "Saved item matches layout")
		variants[item.z] = true
		sections[mini((item.x - 2) / 26, 5)] += 1
		var supported := false
		for rect in Layout.TERRAIN + Layout.ONE_WAY_FLOORS:
			check(not rect.has_point(cell), "OneUp is outside terrain")
			supported = supported or (rect.position.y == cell.y + 1 and cell.x >= rect.position.x and cell.x < rect.end.x)
		check(supported, "OneUp has a supporting floor directly below")
	check(variants.size() == 11, "All eleven variants appear in map")
	check(sections == [6, 6, 6, 6, 6, 6], "Six items in each section")
	layer.clear()
	await ticks()
	var source: TileSetScenesCollectionSource = layer.tile_set.get_source(0)
	check(source.get_scene_tiles_count() == 11, "All eleven items are paintable")
	var player = load("res://scenes/characters/player.tscn").instantiate()
	player.position = Vector2(-1000, -1000)
	root.add_child(player)
	var box := RigidBody2D.new()
	box.collision_layer = 4
	box.gravity_scale = 0
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	box.add_child(shape)
	root.add_child(box)
	for id in 11:
		var cell := Vector2i(200 + id * 3, -10)
		layer.set_cell(cell, 0, Vector2i.ZERO, id)
		await ticks()
		check(layer.get_child_count() == 1, "Painting instantiates one item")
		if layer.get_child_count() != 1:
			continue
		var item = layer.get_child(0)
		check(item.get_node("Sprite2D").texture.get_size() == Vector2(32, 32), "1UP texture is 32px")
		item.collected.connect(func(): pickups += 1)
		box.position = item.global_position
		await ticks()
		check(is_instance_valid(item), "Props cannot collect")
		player.position = item.global_position + Vector2(0, 26)
		await ticks()
		check(not is_instance_valid(item), "Player contact collects scene tile")
		check(pickups == id + 1, "Each item signals exactly once")
		check(not get_nodes_in_group("one_up_collect_effects").is_empty(), "Contact pickup spawns collection burst")
		layer.erase_cell(cell)
		player.position = Vector2(-1000, -1000)
		await ticks()
	stage.queue_free()
	await process_frame
	stage = load("res://scenes/stages/theater_stage.tscn").instantiate()
	root.add_child(stage)
	layer = stage.get_node("Foods")
	await ticks()
	check(layer.get_child_count() == 36, "Reload restores authored item availability")
	print("OneUp collectibles: ", "PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
