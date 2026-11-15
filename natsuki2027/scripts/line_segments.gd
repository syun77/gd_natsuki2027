@tool
extends Node2D
## One batched draw for independent presentation-only line pairs.
var points := PackedVector2Array()
var color := Color.WHITE
var width := 2.0

func set_segments(value: PackedVector2Array, tint: Color, thickness: float) -> void:
	points = value
	color = tint
	width = thickness
	queue_redraw()

func _draw() -> void:
	if not points.is_empty() and color.a > 0.0:
		draw_multiline(points, color, width)

func replay_segments() -> Dictionary:
	return {"kind": "segments", "points": points, "color": color, "width": width}
