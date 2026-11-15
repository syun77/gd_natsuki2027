extends AudioStreamPlayer
## Persistent music; Game owns entry/exit and death-reload policy.
var fade_tween: Tween

func _ready() -> void:
	stream = preload("res://assets/bgm/bgm_01.mp3")

func start() -> void:
	if fade_tween != null:
		fade_tween.kill()
	volume_linear = 1.0
	if not playing:
		play()

func fade_out(duration: float) -> void:
	if fade_tween != null:
		fade_tween.kill()
	fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade_tween.tween_property(self, "volume_linear", 0.0, duration)
	fade_tween.tween_callback(stop)
