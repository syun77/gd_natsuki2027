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
		var edge := before.duplicate(true)
		edge.base = Exchange.token(before)
		edge.movingPlatforms.append({"id": "far_edge", "x": before.width - 1, "y": 1,
			"direction": "left", "travel_cells": 1, "width_cells": 1, "speed": 64.0, "endpoint_wait": 0.0})
		assert(Exchange.validate(stage, before, edge).is_empty())
		edge.movingPlatforms[-1].x = before.width
		assert(not Exchange.validate(stage, before, edge).is_empty())
		if path == "res://scenes/stages/time_attack.tscn":
			assert(before.width == 692)
			var backgrounds := stage.get_children().filter(func(node): return node is Polygon2D)
			assert(backgrounds.size() == 1 and backgrounds[0].polygon[1].x == 22144)
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
		# JSON uses float numbers; platform comparisons must match typed scene values.
		var wire_placed: Dictionary = JSON.parse_string(JSON.stringify(placed))
		assert(Exchange.diff(placed, wire_placed).platforms_next.is_empty())
		assert(Exchange.diff(placed, wire_placed).platforms_old.is_empty())
		var wire_edited: Dictionary = JSON.parse_string(JSON.stringify(edited))
		var roundtrip := Exchange.merge_stale(stage, placed, wire_edited)
		assert(roundtrip.has("data"))
		assert(Exchange.index_platforms(roundtrip.data.movingPlatforms) == Exchange.index_platforms(edited.movingPlatforms))
		var wire_deletion: Dictionary = JSON.parse_string(JSON.stringify(edited))
		wire_deletion.movingPlatforms = wire_deletion.movingPlatforms.filter(func(item): return item.id != "test_floor")
		var deleted := Exchange.merge_stale(stage, placed, wire_deletion)
		assert(deleted.has("data") and not Exchange.index_platforms(deleted.data.movingPlatforms).has("test_floor"))
		# Resending an already applied edit must be unchanged, including new IDs.
		var resent := Exchange.merge_stale(stage, edited, wire_edited)
		assert(resent.has("data") and Exchange.diff(edited, resent.data).platforms_next.is_empty())
		var wire_addition := data.duplicate(true)
		wire_addition.source = {"cells": before.cells, "markers": before.markers, "movingPlatforms": before.movingPlatforms}
		wire_addition = JSON.parse_string(JSON.stringify(wire_addition))
		assert(Exchange.merge_stale(stage, before, wire_addition).has("data"))
		assert(Exchange.merge_stale(stage, placed, wire_addition).has("data"))
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
		var overlap := placed.duplicate(true)
		overlap.base = Exchange.token(placed)
		overlap.movingPlatforms.append(platform.merged({"id": "partial_overlap", "x": 10}, true))
		assert(Exchange.validate(stage, placed, overlap).contains("配置範囲"))
		for offset in [Vector2i(11,10), Vector2i(8,11)]:
			var adjacent := placed.duplicate(true)
			adjacent.base = Exchange.token(placed)
			adjacent.movingPlatforms.append(platform.merged({"id": "adjacent", "x": offset.x, "y": offset.y}, true))
			assert(Exchange.validate(stage, placed, adjacent).is_empty())
		var overlapping_current := placed.duplicate(true)
		overlapping_current.movingPlatforms.append(platform.merged({"id": "different_edit", "x": 10}, true))
		assert(Exchange.merge_stale(stage, overlapping_current, edited).has("error"))
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
