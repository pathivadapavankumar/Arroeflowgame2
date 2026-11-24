extends RefCounted
class_name ArrowflowLevelCatalog

const LEVEL_COUNT := 100
const DIRECTIONS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

static func generate(level: int, seed_override: int = -1, daily: bool = false) -> Dictionary:
	var bounded_level := clampi(level, 1, LEVEL_COUNT)
	var size := 7 if daily else 4 + int((bounded_level - 1) / 17)
	var target := 18 if daily else mini(4 + int(floor(float(bounded_level) * 0.27)), 4 * size - 4)
	var base_seed := seed_override if seed_override >= 0 else bounded_level * 104729 + 431
	var obstacle_target := 1 if daily else int(bounded_level / 38)
	var chosen_arrows: Array[Dictionary] = []
	var chosen_obstacles: Array[Vector2i] = []
	var solved := false

	for attempt in range(36):
		var rng := RandomNumberGenerator.new()
		rng.seed = base_seed + attempt * 7919
		var placed: Array[Dictionary] = []
		for slot in range(target):
			var candidates: Array[Dictionary] = []
			var linked_candidates: Array[Dictionary] = []
			for y in range(size):
				for x in range(size):
					if _position_taken(Vector2i(x, y), placed):
						continue
					for direction in range(DIRECTIONS.size()):
						var candidate := {"id": slot + 1, "x": x, "y": y, "dir": direction}
						if not is_ray_clear(candidate, placed, [], size):
							continue
						candidates.append(candidate)
						if _blocking_score(candidate, placed, size) > 0:
							linked_candidates.append(candidate)
			if candidates.is_empty():
				break
			var pool := candidates
			if not linked_candidates.is_empty() and rng.randf() < 0.82:
				pool = linked_candidates
			var picked: Dictionary = pool[rng.randi_range(0, pool.size() - 1)].duplicate(true)
			picked["id"] = slot + 1
			placed.append(picked)
		if placed.size() != target:
			continue
		var blockers := _place_obstacles(placed, size, obstacle_target, rng)
		if is_solvable(placed, blockers, size):
			chosen_arrows = placed
			chosen_obstacles = blockers
			solved = true
			break

	if not solved:
		chosen_arrows = _perimeter_fallback(size, target, base_seed)
		chosen_obstacles = []

	var solution := solve_order(chosen_arrows, chosen_obstacles, size)
	return {
		"level": bounded_level,
		"size": size,
		"arrows": chosen_arrows.duplicate(true),
		"obstacles": chosen_obstacles.duplicate(),
		"solution": solution,
		"par": chosen_arrows.size(),
		"daily": daily,
		"seed": base_seed
	}

static func daily_key() -> String:
	var date := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02d" % [int(date.year), int(date.month), int(date.day)]

static func seed_for_date(date_key: String) -> int:
	var value: int = 2166136261
	for byte_value in date_key.to_utf8_buffer():
		value = int((value ^ int(byte_value)) * 16777619) & 0x7fffffff
	return maxi(value, 1)

static func can_move(arrows: Array, obstacles: Array, size: int, arrow_id: int) -> bool:
	for arrow in arrows:
		if int(arrow.get("id", -1)) == arrow_id:
			return is_ray_clear(arrow, arrows, obstacles, size)
	return false

static func is_ray_clear(arrow: Dictionary, arrows: Array, obstacles: Array, size: int) -> bool:
	var direction_index := clampi(int(arrow.get("dir", 0)), 0, DIRECTIONS.size() - 1)
	var step: Vector2i = DIRECTIONS[direction_index]
	var position := Vector2i(int(arrow.get("x", 0)), int(arrow.get("y", 0))) + step
	while position.x >= 0 and position.x < size and position.y >= 0 and position.y < size:
		for other in arrows:
			if int(other.get("id", -1)) == int(arrow.get("id", -2)):
				continue
			if int(other.get("x", -99)) == position.x and int(other.get("y", -99)) == position.y:
				return false
		for obstacle in obstacles:
			if obstacle == position:
				return false
		position += step
	return true

static func is_solvable(arrows: Array, obstacles: Array, size: int) -> bool:
	return solve_order(arrows, obstacles, size).size() == arrows.size()

static func solve_order(arrows: Array, obstacles: Array, size: int) -> Array[int]:
	var remaining: Array[Dictionary] = []
	for arrow in arrows:
		remaining.append(arrow.duplicate(true))
	var order: Array[int] = []
	while not remaining.is_empty():
		var safe_index := -1
		for index in range(remaining.size()):
			if is_ray_clear(remaining[index], remaining, obstacles, size):
				safe_index = index
				break
		if safe_index < 0:
			return []
		order.append(int(remaining[safe_index].get("id", -1)))
		remaining.remove_at(safe_index)
	return order

static func first_safe_id(arrows: Array, obstacles: Array, size: int) -> int:
	for arrow in arrows:
		if is_ray_clear(arrow, arrows, obstacles, size):
			return int(arrow.get("id", -1))
	return -1

static func _position_taken(position: Vector2i, arrows: Array) -> bool:
	for arrow in arrows:
		if int(arrow["x"]) == position.x and int(arrow["y"]) == position.y:
			return true
	return false

static func _blocking_score(candidate: Dictionary, arrows: Array, size: int) -> int:
	var cell := Vector2i(int(candidate["x"]), int(candidate["y"]))
	var score := 0
	for arrow in arrows:
		if _cell_on_ray(cell, arrow, size):
			score += 1
	return score

static func _cell_on_ray(cell: Vector2i, arrow: Dictionary, size: int) -> bool:
	var direction_index := clampi(int(arrow.get("dir", 0)), 0, DIRECTIONS.size() - 1)
	var step: Vector2i = DIRECTIONS[direction_index]
	var position := Vector2i(int(arrow["x"]), int(arrow["y"])) + step
	while position.x >= 0 and position.x < size and position.y >= 0 and position.y < size:
		if position == cell:
			return true
		position += step
	return false

static func _place_obstacles(arrows: Array, size: int, count: int, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var candidates: Array[Vector2i] = []
	for y in range(size):
		for x in range(size):
			var cell := Vector2i(x, y)
			if _position_taken(cell, arrows):
				continue
			var intersects_ray := false
			for arrow in arrows:
				if _cell_on_ray(cell, arrow, size):
					intersects_ray = true
					break
			if not intersects_ray:
				candidates.append(cell)
	while not candidates.is_empty() and result.size() < count:
		var index := rng.randi_range(0, candidates.size() - 1)
		result.append(candidates[index])
		candidates.remove_at(index)
	return result

static func _perimeter_fallback(size: int, target: int, seed_value: int) -> Array[Dictionary]:
	var perimeter: Array[Dictionary] = []
	for x in range(size):
		perimeter.append({"id": 0, "x": x, "y": 0, "dir": 0})
	for y in range(1, size):
		perimeter.append({"id": 0, "x": size - 1, "y": y, "dir": 1})
	for x in range(size - 2, -1, -1):
		perimeter.append({"id": 0, "x": x, "y": size - 1, "dir": 2})
	for y in range(size - 2, 0, -1):
		perimeter.append({"id": 0, "x": 0, "y": y, "dir": 3})
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 991
	for index in range(perimeter.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temp: Dictionary = perimeter[index]
		perimeter[index] = perimeter[swap_index]
		perimeter[swap_index] = temp
	var result: Array[Dictionary] = []
	for index in range(mini(target, perimeter.size())):
		var arrow: Dictionary = perimeter[index].duplicate(true)
		arrow["id"] = index + 1
		result.append(arrow)
	return result
