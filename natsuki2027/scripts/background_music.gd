extends AudioStreamPlayer
## Persistent gameplay music; Game owns entry, exit and death-reload policy.
func _ready() -> void:
	stream = preload("res://assets/bgm/bgm_01.mp3")

func start() -> void:
	if not playing:
		play()
