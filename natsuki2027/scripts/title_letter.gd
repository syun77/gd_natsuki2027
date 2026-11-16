extends StaticBody2D
## Gum-only target: text shatters cosmetically without blocking movement or wrapping.
var destroyed := false
var glyph: Label
var glyph_size := Vector2.ZERO
var ink := Color.WHITE

func configure(character: String, font: Font, font_size: int, color: Color) -> void:
	collision_layer = 16
	collision_mask = 0
	ink = color
	glyph_size = Vector2(font.get_string_size(character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, font.get_height(font_size))
	glyph = Label.new()
	glyph.text = character
	glyph.add_theme_font_override("font", font)
	glyph.add_theme_font_size_override("font_size", font_size)
	glyph.add_theme_color_override("font_color", color)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glyph)
	var shape := RectangleShape2D.new()
	shape.size = glyph_size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = glyph_size / 2
	add_child(collider)

func break_from_gum() -> bool:
	if destroyed:
		return false
	destroyed = true
	collision_layer = 0
	glyph.hide()
	_spawn_debris()
	queue_free()
	return true

func _spawn_debris() -> void:
	var debris := CPUParticles2D.new()
	debris.name = "TitleLetterDebris"
	debris.add_to_group("title_letter_debris")
	debris.emitting = false
	debris.one_shot = true
	debris.explosiveness = 1.0
	debris.amount = 16
	debris.lifetime = 0.45
	debris.direction = Vector2.UP
	debris.spread = 100.0
	debris.gravity = Vector2(0, 450)
	debris.initial_velocity_min = 60.0
	debris.initial_velocity_max = 150.0
	debris.scale_amount_min = 2.0
	debris.scale_amount_max = 5.0
	var gradient := Gradient.new()
	gradient.set_color(0, ink)
	gradient.set_color(1, Color(ink, 0.0))
	debris.color_ramp = gradient
	debris.z_index = 7
	get_parent().add_child(debris)
	debris.global_position = to_global(glyph_size / 2)
	debris.finished.connect(debris.queue_free)
	debris.emitting = true
