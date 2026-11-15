extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("verify")
func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failures += 1
func verify() -> void:
	var audio = root.get_node("SoundEffects")
	for cue in audio.CLIPS:
		var clip: AudioStreamWAV = audio.CLIPS[cue]
		check(clip.get_length() > 0.0 and clip.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Valid one-shot %s" % cue)
		var voice = audio.play(cue)
		check(voice.bus == (&"DUCKING" if cue in [&"checkpoint_voice", &"dead", &"one_up_voice"] else &"Master"), "Cue bus %s" % cue)
	check(audio.get_child_count() == audio.CLIPS.size(), "All registered cues overlap")
	for i in 30:
		audio.play(&"jump")
	check(audio.get_child_count() == 24, "Bounded voices")
	for voice in audio.get_children():
		audio.remove_child(voice)
		voice.queue_free()
	var bgm = root.get_node("BackgroundMusic")
	check(bgm.bus == &"BGM", "Music routes to BGM")
	var bgm_bus := AudioServer.get_bus_index(&"BGM")
	var duck_bus := AudioServer.get_bus_index(&"DUCKING")
	check(bgm_bus >= 0 and duck_bus > bgm_bus, "Sidechain buses loaded in processing order")
	if bgm_bus >= 0:
		var compressor = AudioServer.get_bus_effect(bgm_bus, 0)
		check(compressor is AudioEffectCompressor and compressor.sidechain == &"DUCKING" and compressor.ratio > 1.0 and compressor.threshold < 0.0, "BGM compressor uses voice sidechain")
		check(AudioServer.is_bus_effect_enabled(bgm_bus, 0), "Ducking enabled")
	var game = load("res://scenes/game.tscn").instantiate()
	root.add_child(game)
	game._physics_process(game.entrance.TOTAL_TIME)
	check(audio.get_child_count() == 2, "Entrance opens and closes once on a large step")
	check(audio.get_child(0).stream == audio.CLIPS[&"door_open"], "Opening uses door1")
	check(audio.get_child(1).stream == audio.CLIPS[&"door_close"], "Closing uses door2")
	game.entrance.step(1.0)
	check(audio.get_child_count() == 2, "Completed entrance stays silent")
	for voice in audio.get_children():
		voice.free()
	current_scene = game
	game.set_physics_process(false)
	await physics_frame
	var gum = game.gum
	gum.state = gum.State.ATTACHED
	gum.target = game.get_node("PuzzleLightBox")
	gum.mode = gum.Mode.LOOSEN
	gum.contract()
	gum._play_contraction_sound()
	check(audio.get_child_count() == 1, "Contraction starts once")
	gum.contract()
	gum._play_contraction_sound()
	check(audio.get_child_count() == 1, "Repeated contract stays silent")
	gum.relax()
	gum.contract()
	gum._play_contraction_sound()
	check(audio.get_child_count() == 2, "Relax then contract sounds again")
	var checkpoint = game.get_node("TheaterStage/Checkpoints").get_child(0)
	game._on_checkpoint_reached(checkpoint)
	game._on_checkpoint_reached(checkpoint)
	check(audio.get_child_count() == 4, "Checkpoint SE and voice first activation only")
	check(audio.get_child(3).stream == audio.CLIPS[&"checkpoint_voice"] and audio.get_child(3).bus == &"DUCKING", "Checkpoint voice routed to ducking")
	game._die_on_spikes(game.player.global_position)
	game._die_on_spikes(game.player.global_position)
	check(audio.get_child_count() == 5, "Death once")
	check(audio.get_child(4).stream == audio.CLIPS[&"dead"] and audio.get_child(4).bus == &"DUCKING", "Death sound routed to ducking")
	game.queue_free()
	await process_frame
	check(audio.get_child_count() == 5, "Audio survives scene removal")
	for voice in audio.get_children():
		voice.free()
	await process_frame
	print("Sound effects: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(failures)
