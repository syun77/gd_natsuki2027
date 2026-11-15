extends Control
## Frozen end-of-run summary. Only mouse events reach the buttons.
signal title_requested
var data: Dictionary
var replay_failure := ""
var reveal_tween: Tween
const INK := Color("344e50")

func _ready() -> void:
	name = "ClearResults"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.06, 0.12, 0.12, 0.75)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 640
	var style := StyleBoxFlat.new()
	style.bg_color = Color("fff4df")
	style.border_color = Color("d98379")
	style.set_border_width_all(4)
	style.set_corner_radius_all(12)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var heading := _label(column, data.caption, 36)
	heading.add_theme_color_override("font_color", Color("568c7e"))
	_label(column, ("CLEAR TIME  " if data.cleared else "TIME  ") + format_time(data.elapsed), 24)
	if data.cleared and not data.debug:
		_label(column, "BEST TIME  " + format_time(data.best) + ("  NEW BEST" if data.new_best else ""), 24)
	column.add_child(HSeparator.new())
	_item_row(column, "res://assets/items/music_note.png", data.notes, 10)
	_item_row(column, "res://assets/items/star.png", data.stars, 30)
	if data.cleared:
		_label(column, "クリアボーナス   +%s点" % number(data.bonus), 26)
		_label(column, "タイムボーナス  %d秒 × 10   +%s点" % [data.remaining_seconds, number(data.time_bonus)], 26)
	column.add_child(HSeparator.new())
	_label(column, "TOTAL SCORE  %s点" % number(data.score), 36)
	if not replay_failure.is_empty():
		var error := _label(column, replay_failure, 18)
		error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var title_button := _button(column, "タイトルへ", func(): title_requested.emit())
	title_button.disabled = true
	reveal_tween = create_tween()
	for item: Control in column.get_children():
		item.modulate.a = 0.0
		if item is HSeparator:
			reveal_tween.tween_property(item, "modulate:a", 1.0, 0.0)
		else:
			reveal_tween.tween_callback(_play_reveal_sound)
			reveal_tween.tween_property(item, "modulate:a", 1.0, 0.15)
			reveal_tween.tween_interval(0.12)
	reveal_tween.tween_callback(func(): title_button.disabled = false)

func _play_reveal_sound() -> void:
	var voice := SoundEffects.play(&"score_item")
	voice.process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if not event is InputEventMouse:
		get_viewport().set_input_as_handled()

func _label(host: Node, caption: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = caption
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", INK)
	label.add_theme_font_size_override("font_size", font_size)
	host.add_child(label)
	return label

func _item_row(host: Node, texture_path: String, count: int, points: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	host.add_child(row)
	var icon := TextureRect.new()
	icon.texture = load(texture_path)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(40, 40)
	row.add_child(icon)
	var label := _label(row, "× %s" % number(count), 26)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_label(row, "%s点" % number(count * points), 26)

func _button(host: Node, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 52
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	host.add_child(button)
	return button

static func format_time(seconds: float) -> String:
	var ticks := int(floor(seconds * 100.0))
	return "%02d:%02d.%02d" % [ticks / 6000, (ticks / 100) % 60, ticks % 100]

static func number(value: int) -> String:
	var digits := str(value)
	var result := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			result += ","
		result += digits[i]
	return result
