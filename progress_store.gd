extends RefCounted
class_name ArrowflowProgressStore

const SAVE_VERSION := 1
const MAX_DAILY_RECORDS := 90

var path := "user://arrowflow_progress.json"
var data: Dictionary = {}
var last_save_ok := true

func load_data() -> bool:
	data = _default_data()
	if not FileAccess.file_exists(path):
		return true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_save_ok = false
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or int(parsed.get("version", 0)) != SAVE_VERSION:
		last_save_ok = false
		return false
	data["unlocked_level"] = clampi(int(parsed.get("unlocked_level", 1)), 1, 100)
	data["levels"] = _clean_records(parsed.get("levels", {}), 100)
	data["daily"] = _clean_daily(parsed.get("daily", {}))
	var audio: Variant = parsed.get("audio", {})
	if audio is Dictionary:
		data["audio"] = {"music": bool(audio.get("music", true)), "sfx": bool(audio.get("sfx", true))}
	last_save_ok = true
	return true

func save_settings(music_enabled: bool, sfx_enabled: bool) -> bool:
	data["audio"] = {"music": music_enabled, "sfx": sfx_enabled}
	return save()

func complete_level(level: int, stars: int, score: int) -> bool:
	var bounded_level := clampi(level, 1, 100)
	var levels: Dictionary = data.get("levels", {})
	var key := str(bounded_level)
	var previous: Dictionary = levels.get(key, {})
	levels[key] = {
		"stars": maxi(int(previous.get("stars", 0)), clampi(stars, 1, 3)),
		"score": maxi(int(previous.get("score", 0)), maxi(score, 0))
	}
	data["levels"] = levels
	data["unlocked_level"] = maxi(int(data.get("unlocked_level", 1)), mini(bounded_level + 1, 100))
	return save()

func complete_daily(date_key: String, stars: int, score: int) -> bool:
	if date_key.is_empty():
		return false
	var daily: Dictionary = data.get("daily", {})
	var previous: Dictionary = daily.get(date_key, {})
	daily[date_key] = {
		"stars": maxi(int(previous.get("stars", 0)), clampi(stars, 1, 3)),
		"score": maxi(int(previous.get("score", 0)), maxi(score, 0))
	}
	var dates: Array = daily.keys()
	dates.sort()
	while dates.size() > MAX_DAILY_RECORDS:
		daily.erase(dates.pop_front())
	data["daily"] = daily
	return save()

func level_record(level: int) -> Dictionary:
	var levels: Dictionary = data.get("levels", {})
	return (levels.get(str(clampi(level, 1, 100)), {}) as Dictionary).duplicate(true)

func daily_record(date_key: String) -> Dictionary:
	var daily: Dictionary = data.get("daily", {})
	return (daily.get(date_key, {}) as Dictionary).duplicate(true)

func audio_settings() -> Dictionary:
	return (data.get("audio", {"music": true, "sfx": true}) as Dictionary).duplicate(true)

func unlocked_level() -> int:
	return clampi(int(data.get("unlocked_level", 1)), 1, 100)

func completed_count() -> int:
	return (data.get("levels", {}) as Dictionary).size()

func save() -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_save_ok = false
		return false
	file.store_string(JSON.stringify({
		"version": SAVE_VERSION,
		"unlocked_level": unlocked_level(),
		"levels": data.get("levels", {}),
		"daily": data.get("daily", {}),
		"audio": data.get("audio", {"music": true, "sfx": true})
	}))
	file.close()
	last_save_ok = true
	return true

func _default_data() -> Dictionary:
	return {"unlocked_level": 1, "levels": {}, "daily": {}, "audio": {"music": true, "sfx": true}}

func _clean_records(value: Variant, maximum_level: int) -> Dictionary:
	var cleaned: Dictionary = {}
	if not value is Dictionary:
		return cleaned
	for key in value:
		var level := int(key)
		var record: Variant = value[key]
		if level < 1 or level > maximum_level or not record is Dictionary:
			continue
		cleaned[str(level)] = {"stars": clampi(int(record.get("stars", 0)), 0, 3), "score": maxi(int(record.get("score", 0)), 0)}
	return cleaned

func _clean_daily(value: Variant) -> Dictionary:
	var cleaned: Dictionary = {}
	if not value is Dictionary:
		return cleaned
	for key in value:
		var record: Variant = value[key]
		if str(key).length() != 10 or not record is Dictionary:
			continue
		cleaned[str(key)] = {"stars": clampi(int(record.get("stars", 0)), 0, 3), "score": maxi(int(record.get("score", 0)), 0)}
	var dates: Array = cleaned.keys()
	dates.sort()
	while dates.size() > MAX_DAILY_RECORDS:
		cleaned.erase(dates.pop_front())
	return cleaned
