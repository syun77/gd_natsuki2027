extends Node
## Global one-shots survive stage reloads, including immediate pit respawns.
const CLIPS := {
	&"door_open": preload("res://assets/sounds/door1.wav"),
	&"door_close": preload("res://assets/sounds/door2.wav"),
	&"crash": preload("res://assets/sounds/crash.wav"),
	&"checkpoint_voice": preload("res://assets/sounds/vo_checkpoint.wav"),
	&"checkpoint": preload("res://assets/sounds/checkpoint.wav"),
	&"dead": preload("res://assets/sounds/dead.wav"),
	&"hit": preload("res://assets/sounds/hit.wav"),
	&"score_item": preload("res://assets/sounds/item3.wav"),
	&"one_up_voice": preload("res://assets/sounds/vo_1up.wav"),
	&"item": preload("res://assets/sounds/item.wav"),
	&"jump": preload("res://assets/sounds/jump.wav"),
	&"landing": preload("res://assets/sounds/landing.wav"),
	&"pull": preload("res://assets/sounds/pull.wav"),
	&"shoot": preload("res://assets/sounds/shoot.wav"),
}
const MAX_VOICES := 24
signal played(cue: StringName)

func play(cue: StringName) -> AudioStreamPlayer:
	if get_child_count() >= MAX_VOICES:
		var oldest := get_child(0)
		remove_child(oldest)
		oldest.queue_free()
	var voice := AudioStreamPlayer.new()
	voice.stream = CLIPS[cue]
	voice.bus = &"DUCKING" if cue in [&"checkpoint_voice", &"dead", &"one_up_voice"] else &"Master"
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()
	played.emit(cue)
	return voice
