extends CanvasLayer
## Pause the world while keeping menu input and focus navigation alive.
signal retry_requested
signal back_requested
signal resumed
signal checkpoint_selected(path: NodePath)
var is_open := false
var buttons: Array[Button] = []
var checkpoint_buttons: Array[Button] = []
var checkpoint_provider := Callable()
var main_column: VBoxContainer
var checkpoint_column: VBoxContainer
var checkpoint_list: VBoxContainer
var checkpoint_back: Button
var checkpoint_action: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	hide()
	var shade := ColorRect.new()
	shade.color = Color(0.06, 0.12, 0.12, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 440
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f5eedc")
	style.border_color = Color("84aaa0")
	style.set_border_width_all(4)
	style.set_corner_radius_all(16)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 28
	style.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	var title := Label.new()
	title.text = "メニュー"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("344e50"))
	column.add_child(title)
	main_column = VBoxContainer.new()
	main_column.add_theme_constant_override("separation", 18)
	column.add_child(main_column)
	for text in ["リトライ", "タイトルに戻る", "キャンセル"]:
		var button := Button.new()
		button.text = text
		button.custom_minimum_size.y = 64
		main_column.add_child(button)
		buttons.append(button)
	buttons[0].pressed.connect(func(): retry_requested.emit())
	buttons[1].pressed.connect(func(): back_requested.emit())
	buttons[2].pressed.connect(close)
	_set_focus_neighbors(buttons)
	_setup_checkpoint_panel(column)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if is_open:
			close()
		else:
			open()

func open() -> void:
	if is_open:
		return
	is_open = true
	_show_main()
	show()
	get_tree().paused = true
	buttons[0].grab_focus()

func close() -> void:
	if not is_open:
		return
	is_open = false
	hide()
	get_tree().paused = false
	for button in buttons:
		button.release_focus()
	for button in checkpoint_buttons:
		button.release_focus()
	checkpoint_back.release_focus()
	resumed.emit()

func _exit_tree() -> void:
	if is_open:
		get_tree().paused = false

func add_replay_action(action: Callable) -> void:
	var button := Button.new()
	button.text = "リプレイ再生"
	button.custom_minimum_size.y = 64
	main_column.add_child(button)
	button.pressed.connect(action)
	buttons.append(button)
	ReplayStore.availability_changed.connect(_update_replay_button.bind(button))
	visibility_changed.connect(_update_replay_button.bind(button))
	_update_replay_button(button)
	_set_focus_neighbors(buttons)

func _update_replay_button(button: Button) -> void:
	button.disabled = not ReplayStore.available()
	button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL

func _set_focus_neighbors(items: Array[Button]) -> void:
	for index in items.size():
		items[index].focus_neighbor_top = items[index].get_path_to(items[posmod(index - 1, items.size())])
		items[index].focus_neighbor_bottom = items[index].get_path_to(items[(index + 1) % items.size()])

func add_checkpoint_action(provider: Callable) -> void:
	checkpoint_provider = provider
	checkpoint_action = Button.new()
	checkpoint_action.text = "チェックポイント移動（デバッグ）"
	checkpoint_action.custom_minimum_size.y = 64
	main_column.add_child(checkpoint_action)
	buttons.append(checkpoint_action)
	checkpoint_action.pressed.connect(_show_checkpoints)
	_set_focus_neighbors(buttons)

func _setup_checkpoint_panel(column: VBoxContainer) -> void:
	checkpoint_column = VBoxContainer.new()
	checkpoint_column.add_theme_constant_override("separation", 18)
	column.add_child(checkpoint_column)
	var heading := Label.new()
	heading.text = "チェックポイント移動（デバッグ）\nスタートから近い順"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_color_override("font_color", Color("344e50"))
	checkpoint_column.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 250
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	checkpoint_column.add_child(scroll)
	checkpoint_list = VBoxContainer.new()
	checkpoint_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	checkpoint_list.add_theme_constant_override("separation", 8)
	scroll.add_child(checkpoint_list)
	checkpoint_back = Button.new()
	checkpoint_back.text = "戻る"
	checkpoint_back.custom_minimum_size.y = 64
	checkpoint_column.add_child(checkpoint_back)
	checkpoint_back.pressed.connect(func():
		_show_main()
		checkpoint_action.grab_focus()
	)
	checkpoint_column.hide()

func _show_main() -> void:
	main_column.show()
	checkpoint_column.hide()

func _show_checkpoints() -> void:
	checkpoint_buttons.clear()
	for child in checkpoint_list.get_children():
		checkpoint_list.remove_child(child)
		child.queue_free()
	var entries: Array = checkpoint_provider.call()
	for entry: Dictionary in entries:
		var button := Button.new()
		button.text = "チェックポイント %d" % entry.number
		button.custom_minimum_size.y = 56
		button.pressed.connect(func(): checkpoint_selected.emit(entry.path))
		checkpoint_list.add_child(button)
		checkpoint_buttons.append(button)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "チェックポイントがありません"
		empty.add_theme_color_override("font_color", Color("344e50"))
		checkpoint_list.add_child(empty)
	main_column.hide()
	checkpoint_column.show()
	var navigation: Array[Button] = checkpoint_buttons.duplicate()
	navigation.append(checkpoint_back)
	_set_focus_neighbors(navigation)
	navigation[0].grab_focus()
