extends Area2D
## Scene tile collectible; gum can reel it to the player's hand.
const ScorePopup = preload("res://scripts/score_popup.gd")
const CollectionEffect = preload("res://scripts/one_up_collect_effect.gd")
const IdleEffect = preload("res://scripts/one_up_idle_effect.gd")
signal collected
var is_collected := false
var being_pulled := false:
	set(value):
		being_pulled = value
		_update_idle_visibility()
var collection_allowed: Callable
var idle_effect: Sprite2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	idle_effect = IdleEffect.new()
	idle_effect.name = "IdleEffect"
	add_child(idle_effect)
	_update_idle_visibility()

func _update_idle_visibility() -> void:
	if is_instance_valid(idle_effect):
		idle_effect.visible = not being_pulled and not is_collected

func collect() -> void:
	if collection_allowed.is_valid() and not collection_allowed.call():
		return
	if is_collected:
		return
	is_collected = true
	ScorePopup.spawn_text(self, "1UP")
	_update_idle_visibility()
	SoundEffects.play(&"item")
	SoundEffects.play(&"one_up_voice")
	var effect := CollectionEffect.new()
	# Keep residue outside the scene tile so deleting the item does not delete it.
	var host := get_parent()
	if host is TileMapLayer:
		host = host.get_parent()
	host.add_child(effect)
	effect.global_position = global_position
	hide()
	collected.emit()
	queue_free()

func _on_body_entered(body: Node2D) -> void:
	if not being_pulled and body.is_in_group("player"):
		collect()
