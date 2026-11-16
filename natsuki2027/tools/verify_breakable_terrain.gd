extends SceneTree
const Breakable = preload("res://scripts/breakable_terrain.gd")
var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1

func ticks() -> void:
	await physics_frame
	await process_frame
	await physics_frame
	await process_frame

func _initialize() -> void:
	call_deferred("verify")

func verify() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	var layer := TileMapLayer.new()
	layer.name = "TerrainTiles"
	layer.tile_set = load("res://assets/tilesets/theater_tileset.tres")
	layer.collision_enabled = false
	stage.add_child(layer)
	layer.set_cell(Vector2i(4, -2), 4, Vector2i.ZERO)
	layer.set_cell(Vector2i(5, -2), 4, Vector2i.ZERO)
	layer.set_cell(Vector2i(6, -2), 0, Vector2i(8, 3))
	var body := StaticBody2D.new()
	body.name = "Terrain"
	body.collision_layer = 1
	stage.add_child(body)
	Breakable._rebuild(stage, body, layer)
	var player = load("res://scenes/characters/player.tscn").instantiate()
	stage.add_child(player)
	var gum = load("res://scripts/gum_connection.gd").new()
	gum.player = player
	gum.settings = load("res://resources/game_settings.tres").duplicate()
	gum.settings.attachment_range = 300.0
	gum.settings.gum_shot_speed = 2400.0
	stage.add_child(gum)
	await ticks()
	var effects: Array[Node] = []
	for index in 2:
		gum.cancel_return()
		gum.fire(Vector2.RIGHT)
		for step in 20:
			gum.step(1.0 / 60)
			if gum.state != gum.State.OUTBOUND:
				break
		check(layer.get_cell_source_id(Vector2i(4 + index, -2)) == -1, "Shot destroys first encountered brick only")
		if index == 0:
			check(layer.get_cell_source_id(Vector2i(5, -2)) == 4, "Neighbor brick survives first impact")
		var audio = root.get_node("SoundEffects")
		check(audio.get_child(audio.get_child_count() - 1).stream == audio.CLIPS[&"crash"], "Successful destruction plays crash cue")
		var bursts := get_nodes_in_group("brick_break_effects")
		check(bursts.size() == index + 1, "One independent effect per destroyed cell")
		var effect = bursts.back()
		effects.append(effect)
		check(effect.global_position == Vector2(144 + index * 32, -48), "Effect anchors at cell center, not hit face")
		check(effect.hframes == 4 and effect.vframes == 4 and effect.texture.get_size() == Vector2(512, 512), "PixelFX sheet slicing")
		check(effect.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and effect.is_set_as_top_level(), "Nearest world-space debris")
		check(not gum.connected() and gum.player_force == Vector2.ZERO and gum.tension == 0, "Destruction retracts with no attachment force")
		check(layer.get_cell_source_id(Vector2i(6, -2)) == 0, "Ordinary terrain remains")
		await ticks()
		gum.path.geometry.refresh(stage, 1.0)
		check(not gum.path.geometry.inside(Vector2(144 + index * 32, -48)), "Destroyed cell removed from wrapping geometry")
		check(gum.path.geometry.inside(Vector2(208, -48)), "Normal terrain retained in wrapping geometry")
	gum.cancel_return()
	gum.fire(Vector2.RIGHT)
	for step in 20:
		gum.step(1.0 / 60)
		if gum.state != gum.State.OUTBOUND:
			break
	check(gum.connected(), "Shot passes through destroyed cells and attaches to normal terrain")
	check(not Breakable.destroy_hit(gum.cast_to(Vector2(300, -34))), "Normal terrain cannot be destroyed")
	check(get_nodes_in_group("brick_break_effects").size() == 2, "Ordinary hits do not spawn debris")
	for effect in effects:
		var point: Vector2 = effect.global_position
		effect._process(0.2)
		check(effect.frame >= 6 and effect.global_position == point, "Animation advances without drifting center")
		effect._process(0.5)
		check(effect.is_queued_for_deletion(), "Effect expires independently")
	await process_frame
	check(get_nodes_in_group("brick_break_effects").is_empty(), "Expired effects leave no nodes")
	stage.free()
	for scene in ["res://scenes/stages/theater_stage.tscn", "res://scenes/stages/time_attack.tscn"]:
		var saved = load(scene).instantiate()
		var tiles: TileMapLayer = saved.get_node("TerrainTiles")
		var original := tiles.get_used_cells().size()
		tiles.erase_cell(tiles.get_used_cells()[0])
		saved.free()
		var reloaded = load(scene).instantiate()
		check(reloaded.get_node("TerrainTiles").get_used_cells().size() == original, "Fresh scene restores authored terrain")
		reloaded.free()
	await verify_title_letters()
	if failures == 0:
		print("PASS: swept gum brick destruction, single-cell isolation, collision/wrapping rebuild, normal attachment, scene reset and PixelFX effect lifecycle")
	quit(0 if failures == 0 else 1)

func verify_title_letters() -> void:
	var title = load("res://scenes/title.tscn").instantiate()
	root.add_child(title)
	title.set_physics_process(false)
	await ticks()
	var label: Label = title.get_node("TitleLabel")
	var letters := label.get_children().filter(func(node: Node) -> bool: return node is StaticBody2D)
	var expected := 0
	for character in label.text:
		if not character.strip_edges().is_empty() and character != "　":
			expected += 1
	check(letters.size() == expected, "Every non-space title character has an independent target")
	check(label.self_modulate.a == 0.0, "Intact text is hidden while child letters stay visible")
	var gum = title.gum
	var player = title.player
	var settings = title.settings.duplicate()
	gum.settings = settings
	settings.gum_shot_speed = 1200.0
	var destroyed := 0
	for letter in letters:
		var center: Vector2 = letter.to_global(letter.glyph_size / 2)
		player.position = center + Vector2(0, 110)
		player.reset_motion()
		await ticks()
		var hit: Dictionary = gum.cast_to(center)
		check(not hit.is_empty() and hit.collider == letter, "Gum ray selects the individual title character")
		check(not letter.destroyed, "Preview does not break title text")
		var passage_query := PhysicsRayQueryParameters2D.create(center + Vector2(0, 60), center, player.collision_mask)
		var player_hit: Dictionary = title.get_world_2d().direct_space_state.intersect_ray(passage_query)
		check(player_hit.is_empty(), "Title glyph does not block player movement")
		gum.cancel_return()
		gum.fire((center - gum.origin()).normalized())
		gum.step(0.001)
		check(not letter.destroyed, "Title letter survives until the actual gum tip arrives")
		for i in 20:
			gum.step(1.0 / 60.0)
			if gum.state != gum.State.OUTBOUND:
				break
		check(letter.destroyed and letter.collision_layer == 0 and not letter.glyph.visible, "Actual swept tip shatters hit letter and removes its collision")
		check(gum.release_reason == "LETTER DESTROYED" and not gum.connected() and gum.player_force == Vector2.ZERO, "Letter break retracts without attachment force")
		check(not letter.break_from_gum(), "A destroyed letter cannot break twice")
		destroyed += 1
		for other in letters:
			if is_instance_valid(other) and other != letter and not other.is_queued_for_deletion():
				check(not other.destroyed and other.glyph.visible, "Neighboring title letters remain intact")
		await ticks()
		check(label.get_children().filter(func(node: Node) -> bool: return node is StaticBody2D).size() == expected - destroyed, "Only the impacted character disappears")
	check(get_nodes_in_group("title_letter_debris").size() > 0, "Letter destruction produces visible debris")
	for i in 40:
		await physics_frame
		await process_frame
	check(get_nodes_in_group("title_letter_debris").is_empty(), "Letter debris expires without accumulating nodes")
	title.free()
	var restored = load("res://scenes/title.tscn").instantiate()
	root.add_child(restored)
	restored.set_physics_process(false)
	check(restored.get_node("TitleLabel").get_child_count() == expected, "Reentering title restores every character")
	restored.free()
	print("TITLE LETTER CHECK COMPLETE")
