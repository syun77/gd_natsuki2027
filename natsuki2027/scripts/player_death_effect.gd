extends Sprite2D
## World-fixed disappearance smoke and a windblown hat, stepped together by Game.
const HAT = preload("res://assets/effects/player_death_hat.png")
const SMOKE = preload("res://assets/effects/player_death_smoke.png")
const DURATION := 0.6
const SMOKE_FPS := 30.0
const SMOKE_LAST_FRAME := 18
const LIFT_TIME := 0.32
const FALL_SPEED_SCALE := 0.25
const DISPLAY_SCALE := 0.6
const HEAD_OFFSET := Vector2(0, -32)
var elapsed := 0.0
var origin := Vector2.ZERO
var smoke: Sprite2D

func _init() -> void:
	texture = HAT
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 8
	z_as_relative = false

func start(body_center: Vector2) -> void:
	if not is_instance_valid(smoke):
		smoke = Sprite2D.new()
		smoke.texture = SMOKE
		smoke.hframes = 5
		smoke.vframes = 4
		smoke.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		smoke.z_index = 7
		smoke.z_as_relative = false
		add_child(smoke)
		smoke.top_level = true
	smoke.global_position = body_center
	smoke.frame = 0
	origin = body_center + HEAD_OFFSET
	elapsed = 0.0
	_update_hat_pose()

func step(delta: float) -> bool:
	elapsed = minf(elapsed + delta, DURATION)
	_update_hat_pose()
	smoke.frame = mini(int(elapsed * SMOKE_FPS), SMOKE_LAST_FRAME)
	return elapsed >= DURATION

func _update_hat_pose() -> void:
	var fall := maxf(0.0, elapsed - LIFT_TIME)
	var phase := TAU * fall / 1.25
	var amplitude := 42.0 * minf(1.0, fall / 0.45)
	var descent := fall * FALL_SPEED_SCALE
	var lift := -12.0 * sin(minf(elapsed / LIFT_TIME, 1.0) * PI / 2.0)
	global_position = origin + Vector2(amplitude * sin(phase), lift + 62.0 * descent + 10.0 * descent * descent)
	rotation = deg_to_rad(-24.0 * cos(phase) * minf(1.0, fall / 0.35))
	scale = DISPLAY_SCALE * Vector2(1.0, 0.88 + 0.12 * cos(phase * 2.0))
