extends Control
## Artwork and menu share one reference canvas so cropping never separates them.
const ART_SIZE := Vector2(1672, 941)
const GAME_SCENE := "res://scenes/game_time_attack.tscn"

@onready var artwork: Control = $Artwork
@onready var start_button: Button = $Artwork/Menu/Start
@onready var replay_button: Button = $Artwork/Menu/Replay

func _ready() -> void:
	resized.connect(_fit_artwork)
	_fit_artwork()
	start_button.pressed.connect(_start)
	replay_button.pressed.connect(func(): ReplayStore.play(scene_file_path))
	ReplayStore.availability_changed.connect(_update_replay)
	_update_replay()
	start_button.grab_focus()

func _fit_artwork() -> void:
	var factor := maxf(size.x / ART_SIZE.x, size.y / ART_SIZE.y)
	artwork.scale = Vector2.ONE * factor
	artwork.position = (size - ART_SIZE * factor) * 0.5

func _start() -> void:
	if get_tree().has_meta(&"checkpoint_respawn"):
		get_tree().remove_meta(&"checkpoint_respawn")
	var error := get_tree().change_scene_to_file(GAME_SCENE)
	if error != OK:
		push_error("Cannot open %s: %s" % [GAME_SCENE, error_string(error)])

func _update_replay() -> void:
	replay_button.disabled = not ReplayStore.available()
	replay_button.focus_mode = Control.FOCUS_NONE if replay_button.disabled else Control.FOCUS_ALL
