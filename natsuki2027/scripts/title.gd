extends "res://scripts/game.gd"
## A safe practice stage; the shared player step owns all action rules.
const GAME_SCENE := "res://scenes/game_time_attack.tscn"
var spawn_position: Vector2

func _ready() -> void:
	spawn_position = $PlacementMarkers/PlayerSpawn.position
	player.position = spawn_position
	player.settings = settings
	gum.settings = settings
	gum.player = player
	player.gum = gum
	$GumAttachmentEffect.bind(gum)
	$GumShotParticles.bind(gum, settings)
	$GumHitParticles.bind(gum, settings)
	$GumHitShockwave.bind(gum, settings)
	$LandingDustEffect.bind(player)
	_setup_exit(self)
	for checkpoint in $Checkpoints.get_children():
		checkpoint.reached.connect(_on_checkpoint_reached)

func _exit_tree() -> void:
	pass

func _physics_process(delta: float) -> void:
	if restarting:
		return
	if Input.is_action_just_pressed("restart"):
		get_tree().call_deferred("reload_current_scene")
		restarting = true
		return
	if exit_door.active:
		exit_door.step(delta)
		if not exit_door.active:
			_start()
		return
	for platform in $MovingPlatforms.get_children():
		if platform is MovingPlatform:
			platform.step(delta)
	_step_player(delta)
	gum.update_aim(_aim_target())
	if player.position.y > 850:
		player.position = spawn_position
		player.reset_motion()
		player.afterimages.clear()
		gum.detach("TITLE RESET")

func _begin_exit() -> void:
	if restarting or exit_door.started:
		return
	var vertical_speed: float = player.velocity.y
	gum.detach("TITLE GOAL")
	gum.hide()
	player.reset_motion()
	player.afterimages.clear()
	$LandingDustEffect.stop()
	exit_door.begin(player, vertical_speed)

func _start() -> void:
	if restarting:
		return
	restarting = true
	if get_tree().has_meta(RESPAWN_META):
		get_tree().remove_meta(RESPAWN_META)
	get_tree().call_deferred("change_scene_to_file", GAME_SCENE)

func _on_checkpoint_reached(checkpoint: Area2D) -> void:
	if restarting or exit_door.started or checkpoint.activated:
		return
	checkpoint.activate()
	spawn_position = checkpoint.respawn_position()
	SoundEffects.play(&"checkpoint")
