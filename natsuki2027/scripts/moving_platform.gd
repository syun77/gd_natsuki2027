@tool
extends AnimatableBody2D
## One-way motor-driven platform; Game owns its fixed-step clock.
signal route_changed
const COLLISION_OVERHANG := 4.0
const DIRECTIONS := {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
@export var placement_id := ""
@export_enum("up", "down", "left", "right") var direction := "right":
	set(value):
		direction = value
		if is_node_ready(): route_changed.emit()
@export_range(1, 192, 1) var travel_cells := 4:
	set(value):
		travel_cells = value
		if is_node_ready(): route_changed.emit()
@export_range(1, 192, 1) var width_cells := 3:
	set(value):
		width_cells = value
		if is_node_ready():
			_update_width()
@export_range(32.0, 160.0) var speed := 64.0
@export_range(0.0, 5.0) var endpoint_wait := 0.0
var start_position := Vector2.ZERO
var elapsed := 0.0
var motion_velocity := Vector2.ZERO
var passenger_band := RectangleShape2D.new()
var passenger_query := PhysicsShapeQueryParameters2D.new()

func _ready() -> void:
	_update_width()
	start_position = position
	passenger_query.shape = passenger_band
	passenger_query.collision_mask = 4
	set_notify_transform(Engine.is_editor_hint())
	route_changed.emit()

func _update_width() -> void:
	var width := float(width_cells * 32)
	$Surface.size = Vector2(width, 10)
	passenger_band.size = Vector2(width + COLLISION_OVERHANG * 2.0, 8)
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(width + COLLISION_OVERHANG * 2.0, 5)
	$CollisionShape2D.shape = rectangle
	$CollisionShape2D.position = Vector2(width * 0.5, 2.5)
	if is_node_ready(): route_changed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and Engine.is_editor_hint() and is_node_ready():
		route_changed.emit()

func route_endpoints() -> PackedVector2Array:
	var origin := position if Engine.is_editor_hint() or not is_node_ready() else start_position
	var start := origin + Vector2(width_cells * 16.0, 5)
	var end: Vector2 = start + DIRECTIONS[direction] * travel_cells * 32.0
	var host := get_parent() as Node2D
	return PackedVector2Array([host.to_global(start), host.to_global(end)])

func support_rect() -> Rect2:
	return global_transform * Rect2(Vector2(-COLLISION_OVERHANG, 0), Vector2(width_cells * 32.0 + COLLISION_OVERHANG * 2.0, 5))

func step(delta: float) -> void:
	if delta <= 0.0:
		return
	var old := position
	elapsed += delta
	var duration := travel_cells * 32.0 / speed
	var cycle := fposmod(elapsed, 2.0 * (duration + endpoint_wait))
	var distance: float
	if cycle < duration:
		distance = cycle * speed
	elif cycle < duration + endpoint_wait:
		distance = travel_cells * 32.0
	elif cycle < duration * 2.0 + endpoint_wait:
		distance = (duration * 2.0 + endpoint_wait - cycle) * speed
	else:
		distance = 0.0
	var target: Vector2 = start_position + DIRECTIONS[direction] * distance
	motion_velocity = (target - old) / delta
	_wake_passengers()
	position = target

func placement() -> Dictionary:
	var origin := position if Engine.is_editor_hint() or not is_node_ready() else start_position
	return {"id": placement_id, "x": roundi(origin.x / 32.0), "y": roundi(origin.y / 32.0),
		"direction": direction, "travel_cells": travel_cells, "width_cells": width_cells,
		"speed": speed, "endpoint_wait": endpoint_wait}

func configure(data: Dictionary) -> void:
	placement_id = data.id
	var origin := Vector2(data.x, data.y) * 32.0
	position = origin
	direction = data.direction
	travel_cells = int(data.travel_cells)
	width_cells = int(data.width_cells)
	speed = float(data.speed)
	endpoint_wait = float(data.endpoint_wait)
	start_position = origin
	elapsed = 0.0
	motion_velocity = Vector2.ZERO
	route_changed.emit()

func _wake_passengers() -> void:
	# Moving an AnimatableBody does not wake sleeping rigid passengers in Godot 4.5.
	# Wake only; contact friction and normal impulses remain owned by the solver.
	if motion_velocity.is_zero_approx():
		return
	passenger_query.transform = Transform2D(0.0, global_position + Vector2(width_cells * 16.0, -2.0))
	for hit in get_world_2d().direct_space_state.intersect_shape(passenger_query, 32):
		var body = hit.collider
		if body is RigidBody2D and not body.freeze and body.sleeping:
			body.sleeping = false
