extends SceneTree

const Catalog := preload("res://scripts/arrowflow/level_catalog.gd")
const ProgressStore := preload("res://scripts/arrowflow/progress_store.gd")

var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	var previous_count := 0
	var previous_size := 0
	for level in range(1, Catalog.LEVEL_COUNT + 1):
		var puzzle := Catalog.generate(level)
		var arrows: Array = puzzle.get("arrows", [])
		var obstacles: Array = puzzle.get("obstacles", [])
		var grid_size := int(puzzle.get("size", 0))
		check(grid_size >= 4 and grid_size <= 9, "Level %d has a bounded square grid" % level)
		check(not arrows.is_empty(), "Level %d contains arrows" % level)
		check(Catalog.is_solvable(arrows, obstacles, grid_size), "Level %d has a complete valid removal order" % level)
		check(Catalog.generate(level) == puzzle, "Level %d generation is deterministic" % level)
		var occupied: Dictionary = {}
		for arrow in arrows:
			var key := "%d,%d" % [int(arrow["x"]), int(arrow["y"])]
			check(not occupied.has(key), "Level %d has no overlapping arrow cells" % level)
			occupied[key] = true
			check(int(arrow["x"]) >= 0 and int(arrow["x"]) < grid_size and int(arrow["y"]) >= 0 and int(arrow["y"]) < grid_size, "Level %d arrow is within board bounds" % level)
			check(int(arrow["dir"]) >= 0 and int(arrow["dir"]) < 4, "Level %d arrow uses one of four directions" % level)
		for obstacle in obstacles:
			check(not occupied.has("%d,%d" % [obstacle.x, obstacle.y]), "Level %d obstacle does not overlap an arrow" % level)
		check(arrows.size() >= previous_count, "Level %d maintains nondecreasing arrow count" % level)
		check(grid_size >= previous_size, "Level %d maintains nondecreasing board size" % level)
		previous_count = arrows.size()
		previous_size = grid_size

	var trapped := [
		{"id": 1, "x": 0, "y": 1, "dir": 1},
		{"id": 2, "x": 2, "y": 1, "dir": 3}
	]
	check(not Catalog.can_move(trapped, [], 3, 1), "An arrow blocked by another arrow is rejected")
	check(not Catalog.can_move(trapped, [], 3, 2), "Mutually blocked arrows are both rejected")
	check(not Catalog.is_solvable(trapped, [], 3), "A mutually blocked layout is detected as unsolvable")
	var obstacle_arrow := [{"id": 1, "x": 0, "y": 1, "dir": 1}]
	check(not Catalog.can_move(obstacle_arrow, [Vector2i(2, 1)], 4, 1), "A fixed obstacle blocks the arrow path")
	check(Catalog.can_move(obstacle_arrow, [], 4, 1), "An unobstructed arrow can leave the board")
	var daily_date := "2026-11-24"
	var daily_seed := Catalog.seed_for_date(daily_date)
	check(daily_seed == Catalog.seed_for_date(daily_date), "Daily seed is stable for the same UTC date")
	var daily_a := Catalog.generate(1, daily_seed, true)
	var daily_b := Catalog.generate(1, daily_seed, true)
	check(daily_a == daily_b and bool(daily_a.get("daily", false)), "Daily puzzle layout is deterministic and marked daily")
	check(Catalog.is_solvable(daily_a.arrows, daily_a.obstacles, int(daily_a.size)), "Daily puzzle is solvable")

	var save_path := "user://arrowflow_test_progress.json"
	var absolute_path := ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
	var store := ProgressStore.new()
	store.path = save_path
	check(store.load_data(), "A first-run save initializes without an existing file")
	check(store.unlocked_level() == 1, "A new save starts with the first level unlocked")
	check(store.complete_level(5, 3, 2400), "Completing a level writes progression")
	check(store.unlocked_level() == 6, "Winning unlocks the next level")
	check(store.complete_level(5, 1, 1000), "A replayed completion remains writable")
	var persisted := ProgressStore.new()
	persisted.path = save_path
	check(persisted.load_data(), "Saved progress reloads cleanly")
	check(persisted.unlocked_level() == 6, "Unlocked progression persists across reloads")
	check(int(persisted.level_record(5).get("stars", 0)) == 3, "Best star reward is retained on replay")
	check(int(persisted.level_record(5).get("score", 0)) == 2400, "Best score is retained on replay")
	check(persisted.complete_daily(daily_date, 2, 1800), "Daily completion is stored")
	var daily_persisted := ProgressStore.new()
	daily_persisted.path = save_path
	check(daily_persisted.load_data(), "Daily completion reloads from local storage")
	check(int(daily_persisted.daily_record(daily_date).get("stars", 0)) == 2, "Daily stars are keyed by date")
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)

	print("Arrowflow assertions: ", assertions)
	if failures.is_empty():
		print("PASS: 100 deterministic solvable levels, blocking, obstacles, daily puzzles, rewards and local progression.")
	else:
		print("FAIL: ", failures)
	quit(0 if failures.is_empty() else 1)
