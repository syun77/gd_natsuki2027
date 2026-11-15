@tool
extends "res://scripts/line_segments.gd"
## Static stage-space routes; movement never rebuilds the geometry.
const Platform = preload("res://scripts/moving_platform.gd")
const Settings = preload("res://scripts/game_settings.gd")
const DASH_LENGTH := 4.0
const DASH_PERIOD := 8.0
const STOPPER_LENGTH := 8.0
const LINE_WIDTH := 2.0
@export var settings: Settings
var platforms: Node2D
var refresh_pending := false

func _ready() -> void:
	bind(settings if settings != null else load("res://resources/game_settings.tres"))
	platforms = get_parent().get_node_or_null("MovingPlatforms")
	if platforms != null:
		platforms.child_entered_tree.connect(_platform_added)
		platforms.child_exiting_tree.connect(_platform_removed)
		for platform in platforms.get_children():
			_platform_added(platform)
	refresh()

func bind(value: Settings) -> void:
	if settings != null and settings.changed.is_connected(_apply_appearance):
		settings.changed.disconnect(_apply_appearance)
	settings = value
	settings.changed.connect(_apply_appearance)
	_apply_appearance()

func _apply_appearance() -> void:
	# Alpha-zero keeps the batch in replay snapshots, preserving sibling draw order.
	var tint := settings.moving_platform_route_color
	if not settings.moving_platform_route_enabled:
		tint.a = 0.0
	set_segments(points, tint, LINE_WIDTH)

func _platform_added(platform: Node) -> void:
	if platform is Platform:
		if not platform.route_changed.is_connected(_queue_refresh):
			platform.route_changed.connect(_queue_refresh)
		_queue_refresh()

func _platform_removed(platform: Node) -> void:
	if platform is Platform:
		if platform.route_changed.is_connected(_queue_refresh):
			platform.route_changed.disconnect(_queue_refresh)
		_queue_refresh()

func _queue_refresh() -> void:
	if not refresh_pending:
		refresh_pending = true
		call_deferred("refresh")

func refresh() -> void:
	refresh_pending = false
	var segments := PackedVector2Array()
	if is_instance_valid(platforms):
		for platform in platforms.get_children():
			if platform is Platform:
				var endpoints: PackedVector2Array = platform.route_endpoints()
				append_route(segments, to_local(endpoints[0]), to_local(endpoints[1]))
	set_segments(segments, color, LINE_WIDTH)

static func append_route(segments: PackedVector2Array, start: Vector2, end: Vector2) -> void:
	var distance := start.distance_to(end)
	if distance <= 0.0:
		return
	var tangent := (end - start) / distance
	var offset := 0.0
	while offset < distance:
		segments.append(start + tangent * offset)
		segments.append(start + tangent * minf(offset + DASH_LENGTH, distance))
		offset += DASH_PERIOD
	var half_stop := Vector2(-tangent.y, tangent.x) * STOPPER_LENGTH * 0.5
	for endpoint in [start, end]:
		segments.append(endpoint - half_stop)
		segments.append(endpoint + half_stop)
