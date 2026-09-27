extends RefCounted

const DEFAULT_PATH: String = "user://ahoge_device_id.txt"

var _path: String


func _init(path_value: String = DEFAULT_PATH) -> void:
	_path = path_value


func load_or_create() -> String:
	var existing := load_existing()
	if not existing.is_empty():
		return existing

	var generated := _generate()
	if generated.is_empty():
		return ""

	if not _save(generated):
		return ""

	return generated


func load_existing() -> String:
	if not FileAccess.file_exists(_path):
		return ""

	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return ""

	return file.get_as_text().strip_edges()


func _generate() -> String:
	var crypto := Crypto.new()
	var random_bytes := crypto.generate_random_bytes(32)
	return random_bytes.hex_encode()


func _save(device_id: String) -> bool:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		return false

	file.store_string(device_id)
	file.flush()
	return true
