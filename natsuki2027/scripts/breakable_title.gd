extends Label
## Preserve the authored editor label; runtime splits its ink into independent targets.
const Letter = preload("res://scripts/title_letter.gd")

func _ready() -> void:
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var color := get_theme_color("font_color")
	for index in text.length():
		var character := text.substr(index, 1)
		if character.strip_edges().is_empty() or character == "　":
			continue
		var letter := Letter.new()
		letter.name = "Letter%d" % index
		letter.configure(character, font, font_size, color)
		letter.position.x = font.get_string_size(text.substr(0, index), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		add_child(letter)
	# self_modulate affects the intact Label only; child glyphs retain their own color.
	self_modulate = Color(1, 1, 1, 0)
