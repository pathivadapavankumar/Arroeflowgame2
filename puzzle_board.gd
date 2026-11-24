extends Control
class_name ArrowflowPuzzleBoard

signal arrow_tapped(arrow_id: int)
signal exit_finished(arrow_id: int)

const DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const ARROW_COLORS: Array[Color] = [Color("#c8ef68"), Color("#67c9e9"), Color("#ff9b82"), Color("#ffd36d")]
const INK := Color("#183247")
const MUTED := Color("#81909a")
const GRID := Color("#e5e9e1")
const BOARD := Color("#fffdf7")
const OBSTACLE := Color("#334957")
const EXIT_SECONDS := 0.25

var grid_size := 4
var arrows: Array = []
var obstacles: Array = []
var hint_id := -1
var _blocked_id := -1
var _blocked_time := 0.0
var _exit_arrow: Dictionary = {}
var _exit_elapsed := 0.0
var _pulse := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_process(true)

func configure(size: int, arrow_data: Array, obstacle_data: Array) -> void:
	grid_size = maxi(size, 3)
	arrows = arrow_data.duplicate(true)
	obstacles = obstacle_data.duplicate()
	hint_id = -1
	_blocked_id = -1
	_exit_arrow.clear()
	_exit_elapsed = 0.0
	queue_redraw()

func show_hint(arrow_id: int) -> void:
	hint_id = arrow_id
	_pulse = 0.0
	queue_redraw()

func clear_hint() -> void:
	hint_id = -1
	queue_redraw()

func flash_blocked(arrow_id: int) -> void:
	_blocked_id = arrow_id
	_blocked_time = 0.34
	queue_redraw()

func animate_exit(arrow_id: int) -> void:
	for arrow in arrows:
		if int(arrow.get("id", -1)) == arrow_id:
			_exit_arrow = arrow.duplicate(true)
			_exit_elapsed = 0.0
			_blocked_id = -1
			queue_redraw()
			return

func _process(delta: float) -> void:
	var needs_redraw := false
	if _blocked_time > 0.0:
		_blocked_time = maxf(_blocked_time - delta, 0.0)
		if _blocked_time == 0.0:
			_blocked_id = -1
		needs_redraw = true
	if hint_id >= 0:
		_pulse += delta
		needs_redraw = true
	if not _exit_arrow.is_empty():
		_exit_elapsed += delta
		needs_redraw = true
		if _exit_elapsed >= EXIT_SECONDS:
			var finished_id := int(_exit_arrow.get("id", -1))
			_exit_arrow.clear()
			exit_finished.emit(finished_id)
	if needs_redraw:
		queue_redraw()

func _draw() -> void:
	if grid_size < 1:
		return
	var side := minf(size.x, size.y)
	if side < 20.0:
		return
	var origin := (size - Vector2(side, side)) * 0.5
	var board_rect := Rect2(origin, Vector2(side, side))
	var board_style := StyleBoxFlat.new()
	board_style.bg_color = BOARD
	board_style.border_color = Color("#dce3dc")
	board_style.set_border_width_all(maxf(1.0, side * 0.003))
	board_style.set_corner_radius_all(clampi(int(side * 0.045), 14, 30))
	draw_style_box(board_style, board_rect)
	var padding := side * 0.075
	var inner_origin := origin + Vector2(padding, padding)
	var inner_side := side - padding * 2.0
	var cell := inner_side / float(grid_size)
	var inner_rect := Rect2(inner_origin, Vector2(inner_side, inner_side))

	for index in range(1, grid_size):
		var offset := cell * float(index)
		draw_line(Vector2(inner_origin.x + offset, inner_origin.y), Vector2(inner_origin.x + offset, inner_origin.y + inner_side), GRID, maxf(1.0, cell * 0.014), true)
		draw_line(Vector2(inner_origin.x, inner_origin.y + offset), Vector2(inner_origin.x + inner_side, inner_origin.y + offset), GRID, maxf(1.0, cell * 0.014), true)

	if hint_id >= 0:
		for arrow in arrows:
			if int(arrow.get("id", -1)) == hint_id:
				_draw_hint_lane(arrow, inner_origin, inner_rect, cell)
				break

	for obstacle in obstacles:
		if obstacle is Vector2i:
			_draw_obstacle(obstacle, inner_origin, cell)
		elif obstacle is Vector2:
			_draw_obstacle(Vector2i(int(obstacle.x), int(obstacle.y)), inner_origin, cell)

	for arrow in arrows:
		var arrow_id := int(arrow.get("id", -1))
		if arrow_id == int(_exit_arrow.get("id", -2)) and not _exit_arrow.is_empty():
			continue
		var center := inner_origin + Vector2((float(arrow.get("x", 0)) + 0.5) * cell, (float(arrow.get("y", 0)) + 0.5) * cell)
		var is_hint := arrow_id == hint_id
		var scale_factor := 1.0
		if is_hint:
			scale_factor = 1.0 + 0.035 * (0.5 + 0.5 * sin(_pulse * 7.0))
		_draw_arrow(arrow, center, cell, is_hint, arrow_id == _blocked_id, scale_factor)

	if not _exit_arrow.is_empty():
		var direction_index := clampi(int(_exit_arrow.get("dir", 0)), 0, DIRECTIONS.size() - 1)
		var direction := Vector2(DIRECTIONS[direction_index])
		var start := inner_origin + Vector2((float(_exit_arrow.get("x", 0)) + 0.5) * cell, (float(_exit_arrow.get("y", 0)) + 0.5) * cell)
		var distance := _exit_distance(_exit_arrow, direction, inner_origin, inner_rect, cell)
		var ratio := clampf(_exit_elapsed / EXIT_SECONDS, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - ratio, 3.0)
		_draw_arrow(_exit_arrow, start + direction * distance * eased, cell, true, false, 1.0 - ratio * 0.12)

func _draw_hint_lane(arrow: Dictionary, inner_origin: Vector2, inner_rect: Rect2, cell: float) -> void:
	var direction_index := clampi(int(arrow.get("dir", 0)), 0, DIRECTIONS.size() - 1)
	var direction := Vector2(DIRECTIONS[direction_index])
	var start := inner_origin + Vector2((float(arrow.get("x", 0)) + 0.5) * cell, (float(arrow.get("y", 0)) + 0.5) * cell) + direction * cell * 0.28
	var edge := start
	if direction.x > 0.0:
		edge.x = inner_rect.end.x + cell * 0.15
	elif direction.x < 0.0:
		edge.x = inner_rect.position.x - cell * 0.15
	elif direction.y > 0.0:
		edge.y = inner_rect.end.y + cell * 0.15
	else:
		edge.y = inner_rect.position.y - cell * 0.15
	var glow := Color("#a9df45")
	glow.a = 0.34 + 0.10 * (0.5 + 0.5 * sin(_pulse * 7.0))
	draw_line(start, edge, glow, maxf(3.0, cell * 0.055), true)
	var travel := edge - start
	var steps := maxi(int(travel.length() / maxf(cell * 0.24, 1.0)), 1)
	for index in range(steps):
		var dot := start + travel * (float(index) / float(steps))
		draw_circle(dot, maxf(1.5, cell * 0.018), Color("#608a33"))

func _draw_obstacle(cell_position: Vector2i, inner_origin: Vector2, cell: float) -> void:
	var center := inner_origin + Vector2((float(cell_position.x) + 0.5) * cell, (float(cell_position.y) + 0.5) * cell)
	var radius := cell * 0.22
	var points := PackedVector2Array([
		center + Vector2(0.0, -radius), center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius), center + Vector2(-radius, 0.0)
	])
	draw_colored_polygon(points, OBSTACLE)
	draw_line(center + Vector2(-radius * 0.42, -radius * 0.42), center + Vector2(radius * 0.42, radius * 0.42), Color("#b9c5c5"), maxf(2.0, cell * 0.045), true)
	draw_line(center + Vector2(radius * 0.42, -radius * 0.42), center + Vector2(-radius * 0.42, radius * 0.42), Color("#b9c5c5"), maxf(2.0, cell * 0.045), true)

func _draw_arrow(arrow: Dictionary, center: Vector2, cell: float, highlighted: bool, blocked: bool, scale_factor: float) -> void:
	var direction_index := clampi(int(arrow.get("dir", 0)), 0, DIRECTIONS.size() - 1)
	var direction := Vector2(DIRECTIONS[direction_index])
	var rotation := direction.angle()
	var arrow_color: Color = ARROW_COLORS[posmod(int(arrow.get("id", 1)) - 1, ARROW_COLORS.size())]
	var body_width := cell * 0.70 * scale_factor
	var body_height := cell * 0.34 * scale_factor
	var body := StyleBoxFlat.new()
	body.bg_color = arrow_color
	body.border_color = arrow_color.darkened(0.20)
	body.set_border_width_all(maxf(1.0, cell * 0.018))
	body.set_corner_radius_all(maxi(7, int(body_height * 0.46)))
	draw_set_transform(center, rotation, Vector2.ONE)
	draw_style_box(body, Rect2(-body_width * 0.34, -body_height * 0.5, body_width, body_height))
	var shaft_color := INK
	var shaft_width := maxf(2.2, cell * 0.055)
	draw_line(Vector2(-body_width * 0.20, 0.0), Vector2(body_width * 0.20, 0.0), shaft_color, shaft_width, true)
	draw_line(Vector2(body_width * 0.20, 0.0), Vector2(body_width * 0.03, -body_height * 0.30), shaft_color, shaft_width, true)
	draw_line(Vector2(body_width * 0.20, 0.0), Vector2(body_width * 0.03, body_height * 0.30), shaft_color, shaft_width, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if highlighted:
		var halo := Color("#a4d746")
		halo.a = 0.42
		draw_arc(center, cell * (0.43 + 0.02 * sin(_pulse * 7.0)), 0.0, TAU, 28, halo, maxf(2.0, cell * 0.025), true)
	if blocked:
		draw_arc(center, cell * 0.44, 0.0, TAU, 28, Color("#ef6e5e"), maxf(3.0, cell * 0.04), true)

func _exit_distance(arrow: Dictionary, direction: Vector2, inner_origin: Vector2, inner_rect: Rect2, cell: float) -> float:
	var center := inner_origin + Vector2((float(arrow.get("x", 0)) + 0.5) * cell, (float(arrow.get("y", 0)) + 0.5) * cell)
	if direction.x > 0.0:
		return inner_rect.end.x - center.x + cell * 0.40
	if direction.x < 0.0:
		return center.x - inner_rect.position.x + cell * 0.40
	if direction.y > 0.0:
		return inner_rect.end.y - center.y + cell * 0.40
	return center.y - inner_rect.position.y + cell * 0.40

func _gui_input(event: InputEvent) -> void:
	var point := Vector2.ZERO
	var pressed := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		point = event.position
		pressed = event.pressed
	elif event is InputEventScreenTouch:
		point = event.position
		pressed = event.pressed
	if not pressed:
		return
	var cell_position := _cell_at(point)
	if cell_position.x < 0:
		return
	for arrow in arrows:
		if int(arrow.get("x", -1)) == cell_position.x and int(arrow.get("y", -1)) == cell_position.y:
			arrow_tapped.emit(int(arrow.get("id", -1)))
			accept_event()
			return

func _cell_at(point: Vector2) -> Vector2i:
	var side := minf(size.x, size.y)
	var origin := (size - Vector2(side, side)) * 0.5
	var padding := side * 0.075
	var inner_origin := origin + Vector2(padding, padding)
	var inner_side := side - padding * 2.0
	var inner_rect := Rect2(inner_origin, Vector2(inner_side, inner_side))
	if not inner_rect.has_point(point):
		return Vector2i(-1, -1)
	var cell := inner_side / float(grid_size)
	return Vector2i(clampi(int((point.x - inner_origin.x) / cell), 0, grid_size - 1), clampi(int((point.y - inner_origin.y) / cell), 0, grid_size - 1))
