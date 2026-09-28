extends RefCounted

const DEFAULT_PATH: String = "user://active_online_match.json"
const MODE_RANKED: String = "ranked"
const MODE_FRIEND: String = "friend"

var _path: String


func _init(path_value: String = DEFAULT_PATH) -> void:
	_path = path_value


func save(match_id: String, match_mode: String, user_id: String) -> bool:
	if match_id.is_empty() or user_id.is_empty():
		return false
	if match_mode not in [MODE_RANKED, MODE_FRIEND]:
		return false

	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(JSON.stringify({
		"match_id": match_id,
		"match_mode": match_mode,
		"user_id": user_id,
	}))
	file.flush()
	return true


func load_for_user(user_id: String) -> Dictionary:
	if user_id.is_empty() or not FileAccess.file_exists(_path):
		return {}

	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return {}

	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {}

	var match_id := str(parsed.get("match_id", ""))
	var match_mode := str(parsed.get("match_mode", ""))
	var saved_user_id := str(parsed.get("user_id", ""))
	if match_id.is_empty() or saved_user_id != user_id:
		return {}
	if match_mode not in [MODE_RANKED, MODE_FRIEND]:
		return {}

	return {
		"match_id": match_id,
		"match_mode": match_mode,
		"user_id": saved_user_id,
	}


func clear() -> bool:
	if not FileAccess.file_exists(_path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(_path)) == OK
