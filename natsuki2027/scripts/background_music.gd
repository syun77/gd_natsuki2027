extends AudioStreamPlayer
## Persistent music; Game and Replay own entry/exit, Game owns death-reload policy.
func _ready() -> void:
	stream = preload("res://assets/bgm/bgm_01.mp3")

func start() -> void:
	if not playing:
		play()
