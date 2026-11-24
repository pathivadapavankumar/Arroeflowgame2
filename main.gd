extends Control

const Catalog := preload("res://scripts/arrowflow/level_catalog.gd")
const ProgressStore := preload("res://scripts/arrowflow/progress_store.gd")
const BoardScript := preload("res://scripts/arrowflow/puzzle_board.gd")
const AudioScript := preload("res://scripts/game_audio.gd")
const UI_FONT: Font = preload("res://assets/template/fonts/ui_regular.tres")
const UI_BOLD: Font = preload("res://assets/template/fonts/ui_bold.tres")

const PAPER := Color("#f6f5ef")
const INK := Color("#172b3a")
const MUTED := Color("#687783")
const LIME := Color("#c8ef68")
const WHITE := Color("#fffdf8")
const LINE := Color("#dce3df")
const CORAL := Color("#f17961")

var _store: ArrowflowProgressStore
var _audio: GameAudio
var _screen: Control
var _board: ArrowflowPuzzleBoard
var _progress_bar: ProgressBar
var _progress_label: Label
var _status_label: Label
var _undo_button: Button
var _hint_button: Button
var _level := 1
var _daily := false
var _daily_date := ""
var _layout: Dictionary = {}
var _arrows: Array = []
var _obstacles: Array = []
var _initial_arrows: Array = []
var _undo_stack: Array = []
var _pending_undo: Array = []
var _busy := false
var _moves := 0
var _hints_used := 0
var _undos_used := 0
var _toast_time := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	var game_theme := Theme.new()
	game_theme.default_font = UI_FONT
	game_theme.default_font_size = 20
	game_theme.set_color("font_color", "Button", INK)
	game_theme.set_color("font_hover_color", "Button", INK)
	game_theme.set_color("font_pressed_color", "Button", INK)
	game_theme.set_color("font_disabled_color", "Button", MUTED)
	theme = game_theme
	var background := ColorRect.new()
	background.name = "ArrowflowBackground"
	background.color = PAPER
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_store = ProgressStore.new()
	_store.load_data()
	_audio = AudioScript.new()
	_audio.name = "ArrowflowAudio"
	add_child(_audio)
	var audio_settings := _store.audio_settings()
	_audio.set_music_enabled(bool(audio_settings.get("music", true)))
	_audio.set_sfx_enabled(bool(audio_settings.get("sfx", true)))
	_show_home()

func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time = maxf(_toast_time - delta, 0.0)
		if _toast_time == 0.0 and is_instance_valid(_status_label) and not _busy:
			_status_label.text = _progress_copy()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _daily or _level > 0:
				if is_instance_valid(_board) and not _busy:
					_show_pause()
					get_viewport().set_input_as_handled()
		elif event.keycode == KEY_H and is_instance_valid(_board):
			_use_hint()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Z and is_instance_valid(_board):
			_undo()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R and is_instance_valid(_board):
			_restart()
			get_viewport().set_input_as_handled()

func _replace_screen() -> Control:
	if is_instance_valid(_screen):
		_screen.queue_free()
	_screen = Control.new()
	_screen.name = "ArrowflowScreen"
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_screen)
	_board = null
	_progress_bar = null
	_progress_label = null
	_status_label = null
	_hint_button = null
	_undo_button = null
	return _screen

func _show_home() -> void:
	var screen := _replace_screen()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.add_theme_constant_override("margin_left", 18)
	center.add_theme_constant_override("margin_right", 18)
	screen.add_child(center)
	var panel := _panel(center, _card_minimum(Vector2(500, 640)), WHITE)
	var body := _panel_body(panel, 34)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 15)
	body.add_child(content)

	var mark_row := HBoxContainer.new()
	mark_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mark_row.add_theme_constant_override("separation", 7)
	content.add_child(mark_row)
	for mark in ["↑", "→", "↓", "←"]:
		var chip := Label.new()
		chip.text = mark
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.custom_minimum_size = Vector2(38, 38)
		chip.add_theme_color_override("font_color", INK)
		chip.add_theme_font_override("font", UI_BOLD)
		chip.add_theme_font_size_override("font_size", 21)
		var tile := StyleBoxFlat.new()
		tile.bg_color = [LIME, Color("#a9e2f2"), Color("#ffd9c9"), Color("#ffe7a3")][mark_row.get_child_count()]
		tile.set_corner_radius_all(12)
		chip.add_theme_stylebox_override("normal", tile)
		mark_row.add_child(chip)

	var title := _label(content, "ARROWFLOW", 42, INK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle := _label(content, "Clear a path. Find your flow.", 18, MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var instructions := _label(content, "Tap an arrow to send it out. Clear lanes move; blocked lanes stay put.", 16, MUTED)
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.custom_minimum_size = Vector2(0, 46)

	var play := _button("PLAY LEVEL %d" % _store.unlocked_level(), Callable(self, "_play_current"), true)
	play.custom_minimum_size.y = 60
	content.add_child(play)
	var daily_label := "DAILY PUZZLE" if _store.daily_record(Catalog.daily_key()).is_empty() else "DAILY PUZZLE  ·  CLEARED"
	var daily := _button(daily_label, Callable(self, "_play_daily"), false)
	daily.custom_minimum_size.y = 54
	content.add_child(daily)
	var levels := _button("CHOOSE A LEVEL", Callable(self, "_show_level_select"), false)
	levels.custom_minimum_size.y = 50
	content.add_child(levels)

	var stats := _label(content, "%d / 100 levels cleared   ·   %d total stars" % [_store.completed_count(), _total_stars()], 14, MUTED)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var audio_row := HBoxContainer.new()
	audio_row.alignment = BoxContainer.ALIGNMENT_CENTER
	audio_row.add_theme_constant_override("separation", 12)
	content.add_child(audio_row)
	_add_audio_button(audio_row, true)
	_add_audio_button(audio_row, false)

func _show_level_select() -> void:
	var screen := _replace_screen()
	var margin := _margins(screen, 22)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	layout.add_child(header)
	var back := _button("‹  HOME", Callable(self, "_show_home"), false)
	back.custom_minimum_size = Vector2(118, 50)
	header.add_child(back)
	var title := _label(header, "CHOOSE A LEVEL", 28, INK, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var unlocked := _label(header, "UNLOCKED  %d / 100" % _store.unlocked_level(), 14, MUTED, true)
	unlocked.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(unlocked)
	var note := _label(layout, "Complete a puzzle to unlock the next one. Your stars stay on this device.", 15, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var grid := GridContainer.new()
	var tile_size := 60.0 if size.x < 660.0 else 92.0
	grid.columns = clampi(int((size.x - 44.0 + 10.0) / (tile_size + 10.0)), 3, 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for number in range(1, Catalog.LEVEL_COUNT + 1):
		var record := _store.level_record(number)
		var locked := number > _store.unlocked_level()
		var text := "%02d" % number
		if not record.is_empty():
			text += "\n" + "★".repeat(int(record.get("stars", 0)))
		var button := _button(text, Callable(self, "_start_level").bind(number, false), number == _store.unlocked_level() and not locked)
		button.custom_minimum_size = Vector2(tile_size, 58 if size.x < 660.0 else 68)
		button.disabled = locked
		if locked:
			button.text = "🔒\n%02d" % number
		elif not record.is_empty():
			button.add_theme_color_override("font_color", Color("#517c2e"))
		grid.add_child(button)

func _play_current() -> void:
	_start_level(_store.unlocked_level(), false)

func _play_daily() -> void:
	_start_level(1, true)

func _start_level(level: int, daily: bool = false) -> void:
	_level = clampi(level, 1, Catalog.LEVEL_COUNT)
	_daily = daily
	_daily_date = Catalog.daily_key() if daily else ""
	var seed_value := Catalog.seed_for_date(_daily_date) if daily else -1
	_layout = Catalog.generate(_level, seed_value, daily)
	_arrows = (_layout.get("arrows", []) as Array).duplicate(true)
	_initial_arrows = _arrows.duplicate(true)
	_obstacles = (_layout.get("obstacles", []) as Array).duplicate()
	_undo_stack.clear()
	_pending_undo.clear()
	_moves = 0
	_hints_used = 0
	_undos_used = 0
	_busy = false
	_show_puzzle()

func _show_puzzle() -> void:
	var screen := _replace_screen()
	var margin := _margins(screen, 22)
	var vertical := VBoxContainer.new()
	vertical.add_theme_constant_override("separation", 12)
	margin.add_child(vertical)

	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _panel_style(WHITE, LINE, 18))
	vertical.add_child(header)
	var header_margin := _panel_body(header, 12)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	header_margin.add_child(row)
	var back := _button("‹", Callable(self, "_show_level_select"), false)
	back.custom_minimum_size = Vector2(52, 48)
	row.add_child(back)
	var heading_stack := VBoxContainer.new()
	heading_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_stack.add_theme_constant_override("separation", 2)
	row.add_child(heading_stack)
	var header_title := _label(heading_stack, "DAILY PUZZLE" if _daily else "LEVEL %d  /  100" % _level, 18, INK, true)
	header_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var header_subtitle := _label(heading_stack, _daily_date if _daily else "Tap an arrow to clear its lane", 13, MUTED)
	header_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pause := _button("Ⅱ", Callable(self, "_show_pause"), false)
	pause.custom_minimum_size = Vector2(52, 48)
	row.add_child(pause)

	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 10)
	vertical.add_child(progress_row)
	_progress_label = _label(progress_row, _progress_copy(), 14, MUTED, true)
	_progress_label.custom_minimum_size.x = 96
	progress_row.add_child(_progress_label)
	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0
	_progress_bar.max_value = maxi(_initial_arrows.size(), 1)
	_progress_bar.value = _moves
	_progress_bar.show_percentage = false
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.custom_minimum_size.y = 14
	_progress_bar.add_theme_stylebox_override("background", _progress_style(Color("#e7ece6")))
	_progress_bar.add_theme_stylebox_override("fill", _progress_style(LIME))
	progress_row.add_child(_progress_bar)

	var board_center := CenterContainer.new()
	board_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vertical.add_child(board_center)
	_board = BoardScript.new()
	_board.name = "PuzzleBoard"
	var board_side := maxf(220.0, minf(280.0, get_viewport_rect().size.x - 44.0))
	_board.custom_minimum_size = Vector2(board_side, board_side)
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.arrow_tapped.connect(_on_arrow_tapped)
	_board.exit_finished.connect(_on_arrow_exit_finished)
	board_center.add_child(_board)
	_board.configure(int(_layout.get("size", 4)), _arrows, _obstacles)

	var status_panel := PanelContainer.new()
	status_panel.add_theme_stylebox_override("panel", _panel_style(Color("#fff9e8"), Color("#f0e6c6"), 14))
	vertical.add_child(status_panel)
	var status_body := _panel_body(status_panel, 8)
	_status_label = _label(status_body, _progress_copy(), 14, MUTED)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	vertical.add_child(actions)
	_hint_button = _button("HINT  H", Callable(self, "_use_hint"), false)
	_hint_button.custom_minimum_size.y = 56
	_hint_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_hint_button)
	_undo_button = _button("UNDO  Z", Callable(self, "_undo"), false)
	_undo_button.custom_minimum_size.y = 56
	_undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_undo_button.disabled = _undo_stack.is_empty()
	actions.add_child(_undo_button)
	var restart := _button("RESTART  R", Callable(self, "_restart"), false)
	restart.custom_minimum_size.y = 56
	restart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(restart)
	_sync_puzzle_ui()

func _show_pause() -> void:
	if _busy or not is_instance_valid(_board):
		return
	var screen := _replace_screen()
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.12, 0.17, 0.42)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var panel := _panel(center, _card_minimum(Vector2(420, 410)), WHITE)
	var body := _panel_body(panel, 30)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	body.add_child(content)
	var title := _label(content, "PAUSED", 32, INK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var copy := _label(content, "Take a breath. Your puzzle is waiting.", 15, MUTED)
	copy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(_button("RESUME", Callable(self, "_show_puzzle"), true))
	content.add_child(_button("RESTART PUZZLE", Callable(self, "_restart"), false))
	content.add_child(_button("RETURN HOME", Callable(self, "_show_home"), false))
	var audio_row := HBoxContainer.new()
	audio_row.alignment = BoxContainer.ALIGNMENT_CENTER
	audio_row.add_theme_constant_override("separation", 10)
	content.add_child(audio_row)
	_add_audio_button(audio_row, true)
	_add_audio_button(audio_row, false)

func _show_victory(stars: int, score: int) -> void:
	var screen := _replace_screen()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var panel := _panel(center, _card_minimum(Vector2(500, 520)), WHITE)
	var body := _panel_body(panel, 34)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	body.add_child(content)
	var seal := _label(content, "✦", 56, Color("#f2b943"), true)
	seal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := _label(content, "PUZZLE CLEARED!", 30, INK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var description := _label(content, "DAILY CHALLENGE  ·  %s" % _daily_date if _daily else "LEVEL %d COMPLETE" % _level, 14, MUTED, true)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var stars_line := _label(content, "★".repeat(stars) + "☆".repeat(3 - stars), 38, Color("#f2b943"), true)
	stars_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var score_line := _label(content, "SCORE  %d" % score, 23, INK, true)
	score_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var note_text := "Best stored on this device." if _daily else "Next level unlocked. Your progress is saved locally."
	var note := _label(content, note_text, 15, MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not _daily and _level < Catalog.LEVEL_COUNT:
		content.add_child(_button("NEXT LEVEL  →", Callable(self, "_start_level").bind(_level + 1, false), true))
	else:
		content.add_child(_button("BACK TO LEVELS", Callable(self, "_show_level_select"), true))
	content.add_child(_button("HOME", Callable(self, "_show_home"), false))

	panel.pivot_offset = panel.custom_minimum_size * 0.5
	panel.scale = Vector2(0.94, 0.94)
	panel.modulate.a = 0.0
	var reveal := create_tween().set_parallel(true)
	reveal.tween_property(panel, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	reveal.tween_property(panel, "modulate:a", 1.0, 0.22)
	seal.pivot_offset = Vector2(28.0, 28.0)
	seal.scale = Vector2(0.65, 0.65)
	var sparkle := create_tween()
	sparkle.tween_interval(0.08)
	sparkle.tween_property(seal, "scale", Vector2(1.12, 1.12), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	sparkle.tween_property(seal, "scale", Vector2.ONE, 0.12)

func _on_arrow_tapped(arrow_id: int) -> void:
	if _busy:
		return
	if not Catalog.can_move(_arrows, _obstacles, int(_layout.get("size", 4)), arrow_id):
		_board.flash_blocked(arrow_id)
		_show_toast("This lane is blocked—try another arrow.")
		_audio.play_impact(0.28, 0, true)
		return
	_board.clear_hint()
	_pending_undo = _arrows.duplicate(true)
	_busy = true
	_audio.play_release()
	_board.animate_exit(arrow_id)
	_sync_puzzle_ui()

func _on_arrow_exit_finished(arrow_id: int) -> void:
	if not _busy:
		return
	_undo_stack.append(_pending_undo.duplicate(true))
	_pending_undo.clear()
	for index in range(_arrows.size()):
		if int(_arrows[index].get("id", -1)) == arrow_id:
			_arrows.remove_at(index)
			break
	_moves += 1
	_busy = false
	_board.configure(int(_layout.get("size", 4)), _arrows, _obstacles)
	_sync_puzzle_ui()
	if _arrows.is_empty():
		_complete_puzzle()
	else:
		_show_toast("Nice clear. Find the next open lane.")
		_audio.play_ui_click()

func _use_hint() -> void:
	if _busy or not is_instance_valid(_board):
		return
	var hint := Catalog.first_safe_id(_arrows, _obstacles, int(_layout.get("size", 4)))
	if hint < 0:
		_show_toast("No open lane found. Restart to try the puzzle again.")
		return
	_hints_used += 1
	_board.show_hint(hint)
	_show_toast("Try the glowing arrow—it has a clear lane.")
	_audio.play_ui_click()
	_sync_puzzle_ui()

func _undo() -> void:
	if _busy or _undo_stack.is_empty():
		return
	_arrows = (_undo_stack.pop_back() as Array).duplicate(true)
	_undos_used += 1
	_moves = maxi(_moves - 1, 0)
	_board.configure(int(_layout.get("size", 4)), _arrows, _obstacles)
	_show_toast("Last move undone.")
	_audio.play_ui_click()
	_sync_puzzle_ui()

func _restart() -> void:
	if _daily:
		_start_level(1, true)
	else:
		_start_level(_level, false)
	_audio.play_restart()

func _complete_puzzle() -> void:
	_busy = false
	var stars := 3 if _hints_used == 0 and _undos_used == 0 else (2 if _hints_used + _undos_used <= 3 else 1)
	var score := maxi(100, _initial_arrows.size() * 100 + stars * 150 - _hints_used * 40 - _undos_used * 25)
	if _daily:
		_store.complete_daily(_daily_date, stars, score)
	else:
		_store.complete_level(_level, stars, score)
	_audio.play_ui_open()
	_show_victory(stars, score)

func _sync_puzzle_ui() -> void:
	if is_instance_valid(_progress_label):
		_progress_label.text = _progress_copy()
	if is_instance_valid(_progress_bar):
		_progress_bar.max_value = maxi(_initial_arrows.size(), 1)
		_progress_bar.value = _moves
	if is_instance_valid(_undo_button):
		_undo_button.disabled = _busy or _undo_stack.is_empty()
	if is_instance_valid(_hint_button):
		_hint_button.disabled = _busy or _arrows.is_empty()

func _progress_copy() -> String:
	return "%d / %d" % [_moves, _initial_arrows.size()]

func _show_toast(message: String) -> void:
	if not is_instance_valid(_status_label):
		return
	_status_label.text = message
	_toast_time = 2.2

func _total_stars() -> int:
	var levels: Dictionary = _store.data.get("levels", {})
	var total := 0
	for record in levels.values():
		if record is Dictionary:
			total += int(record.get("stars", 0))
	return total

func _toggle_music(button: Button) -> void:
	var enabled := not _audio.music_enabled
	_audio.set_music_enabled(enabled)
	_store.save_settings(_audio.music_enabled, _audio.sfx_enabled)
	button.text = "MUSIC  ON" if enabled else "MUSIC  OFF"
	_audio.play_ui_click()

func _toggle_sfx(button: Button) -> void:
	var enabled := not _audio.sfx_enabled
	_audio.set_sfx_enabled(enabled)
	_store.save_settings(_audio.music_enabled, _audio.sfx_enabled)
	button.text = "SFX  ON" if enabled else "SFX  OFF"
	if enabled:
		_audio.play_ui_click()

func _add_audio_button(parent: Node, is_music: bool) -> Button:
	var enabled := _audio.music_enabled if is_music else _audio.sfx_enabled
	var button := _button(("MUSIC  ON" if enabled else "MUSIC  OFF") if is_music else ("SFX  ON" if enabled else "SFX  OFF"), Callable(), false)
	button.custom_minimum_size = Vector2(138, 44)
	parent.add_child(button)
	if is_music:
		button.pressed.connect(_toggle_music.bind(button))
	else:
		button.pressed.connect(_toggle_sfx.bind(button))
	return button

func _margins(parent: Control, margin: int) -> MarginContainer:
	var node := MarginContainer.new()
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.add_theme_constant_override("margin_left", margin)
	node.add_theme_constant_override("margin_right", margin)
	node.add_theme_constant_override("margin_top", margin)
	node.add_theme_constant_override("margin_bottom", margin)
	parent.add_child(node)
	return node

func _panel(parent: Node, minimum: Vector2, fill: Color) -> PanelContainer:
	var node := PanelContainer.new()
	node.custom_minimum_size = minimum
	node.add_theme_stylebox_override("panel", _panel_style(fill, LINE, 26))
	parent.add_child(node)
	return node

func _card_minimum(maximum: Vector2) -> Vector2:
	var viewport_size := get_viewport_rect().size
	return Vector2(maxf(260.0, minf(maximum.x, viewport_size.x - 36.0)), maxf(260.0, minf(maximum.y, viewport_size.y - 36.0)))

func _panel_body(panel: PanelContainer, margin: int) -> MarginContainer:
	var node := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		node.add_theme_constant_override("margin_" + side, margin)
	panel.add_child(node)
	return node

func _panel_style(fill: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0.12, 0.20, 0.25, 0.09)
	style.shadow_size = 9
	style.shadow_offset = Vector2(0, 4)
	return style

func _progress_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(8)
	return style

func _label(parent: Node, text: String, font_size: int, color: Color, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_override("font", UI_BOLD if bold else UI_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _button(text: String, callback: Callable, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(100, 46)
	button.add_theme_font_override("font", UI_BOLD)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", INK if primary else INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", MUTED)
	var normal := _panel_style(LIME if primary else WHITE, Color("#b6d66d") if primary else LINE, 16)
	var hover := _panel_style(Color("#d8f59a") if primary else Color("#f1f5ed"), Color("#9fc94e") if primary else Color("#c3d0cb"), 16)
	var pressed := _panel_style(Color("#b7e354") if primary else Color("#e9eee7"), Color("#9fc94e") if primary else Color("#c3d0cb"), 16)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("disabled", _panel_style(Color("#edf0eb"), LINE, 16))
	if callback.is_valid():
		button.pressed.connect(callback)
	return button
