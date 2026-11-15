extends SceneTree
const Exchange = preload("res://addons/mapedit/stage_exchange.gd")

func _initialize() -> void:
	create_timer(15.0).timeout.connect(func(): quit(1))
	call_deferred("verify")

func verify() -> void:
	var plugin := EditorPlugin.new()
	for path in Exchange.WIDTHS:
		EditorInterface.open_scene_from_path(path)
		for i in 10:
			await process_frame
		var stage := EditorInterface.get_edited_scene_root()
		var before := Exchange.snapshot(stage)
		var data := before.duplicate(true)
		data.base = Exchange.token(before)
		var platform := {"id": "test_floor", "x": 8, "y": 10, "direction": "right",
			"travel_cells": 4, "width_cells": 3, "speed": 160.0, "endpoint_wait": 0.25}
		data.movingPlatforms.append(platform)
		assert(Exchange.validate(stage, before, data).is_empty())
		var changes := Exchange.diff(before, data)
		assert(changes.platforms_next.size() == 1 and not changes.terrain_changed)
		var history := plugin.get_undo_redo()
		Exchange.commit(history, stage, changes)
		var placed := Exchange.snapshot(stage)
		assert(Exchange.index_platforms(placed.movingPlatforms).test_floor == platform)
		var body := stage.get_node("MovingPlatforms/Platform_test_floor")
		assert(body.owner == stage and body.get_node("Surface").size == Vector2(96, 10))
		var packed := PackedScene.new()
		assert(packed.pack(stage) == OK)
		assert(ResourceSaver.save(packed, "/tmp/moving-platform-roundtrip.tscn") == OK)
		var reloaded = load("/tmp/moving-platform-roundtrip.tscn").instantiate()
		assert(reloaded.get_node("MovingPlatforms/Platform_test_floor").placement() == platform)
		reloaded.free()
		var undo := history.get_history_undo_redo(history.get_object_history_id(stage))
		assert(undo.undo())
		assert(Exchange.snapshot(stage) == before)
		assert(undo.redo())
		var edited := placed.duplicate(true)
		edited.base = Exchange.token(placed)
		edited.source = {"cells": placed.cells, "markers": placed.markers, "movingPlatforms": placed.movingPlatforms}
		for item in edited.movingPlatforms:
			if item.id == "test_floor":
				item.direction = "up"
				item.travel_cells = 2
				item.width_cells = 5
		var changed := Exchange.diff(placed, edited)
		Exchange.commit(history, stage, changed)
		assert(stage.get_node("MovingPlatforms/Platform_test_floor").width_cells == 5)
		assert(undo.undo())
		assert(Exchange.snapshot(stage) == placed)
		var independent := placed.duplicate(true)
		independent.movingPlatforms.append(platform.merged({"id": "independent", "x": 20}, true))
		var merged := Exchange.merge_stale(stage, independent, edited)
		assert(merged.has("data") and merged.data.movingPlatforms.size() == independent.movingPlatforms.size())
		var concurrent := placed.duplicate(true)
		for item in concurrent.movingPlatforms:
			if item.id == "test_floor": item.speed = 80
		assert(Exchange.merge_stale(stage, concurrent, edited).has("error"))
		var deletion := edited.duplicate(true)
		deletion.movingPlatforms = deletion.movingPlatforms.filter(func(item): return item.id != "test_floor")
		assert(Exchange.merge_stale(stage, concurrent, deletion).has("error"))
		for invalid in [platform.merged({"id": "other"}, true), platform.merged({"id": "outside", "x": before.width - 1}, true), platform.merged({"id": "bad", "speed": 0}, true)]:
			var rejected := placed.duplicate(true)
			rejected.base = Exchange.token(placed)
			rejected.movingPlatforms.append(invalid)
			assert(not Exchange.validate(stage, placed, rejected).is_empty())
		var removed := placed.duplicate(true)
		removed.movingPlatforms = removed.movingPlatforms.filter(func(item): return item.id != "test_floor")
		Exchange.commit(history, stage, Exchange.diff(placed, removed))
		assert(not stage.has_node("MovingPlatforms/Platform_test_floor"))
		assert(undo.undo())
		assert(Exchange.snapshot(stage) == placed)
		# Export the same v2 snapshot consumed by Swift model verification.
		var fixture := placed.duplicate(true)
		fixture.base = Exchange.token(placed)
		fixture.source = {"cells": placed.cells, "markers": placed.markers, "movingPlatforms": placed.movingPlatforms}
		var file := FileAccess.open("/tmp/moving-platform-mapedit.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(fixture))
		file.close()
		print("Moving platform exchange PASS ", path)
	plugin.free()
	quit()
