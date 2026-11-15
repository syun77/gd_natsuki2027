extends AudioStreamPlayer
## Persistent music; Game owns entry/exit and death-reload policy.
const RESULT_FILTER_INDEX := 1
var fade_tween: Tween

func _ready() -> void:
	bus = &"BGM"
	stream = preload("res://assets/bgm/bgm_01.mp3")

func start() -> void:
	if fade_tween != null:
		fade_tween.kill()
	set_results_filter(false)
	volume_linear = 1.0
	if not playing:
		play()

func set_results_filter(enabled: bool) -> void:
	AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index(bus), RESULT_FILTER_INDEX, enabled)

func fade_out(duration: float) -> void:
	if fade_tween != null:
		fade_tween.kill()
	fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade_tween.tween_property(self, "volume_linear", 0.0, duration)
	fade_tween.tween_callback(stop)
