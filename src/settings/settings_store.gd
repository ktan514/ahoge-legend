extends RefCounted

const DEFAULT_CONFIG_PATH := "user://settings.cfg"
const DEFAULT_RESOLUTION := "1280x720"
const RESOLUTIONS := {
	"1280x720": Vector2i(1280, 720),
	"1600x900": Vector2i(1600, 900),
	"1920x1080": Vector2i(1920, 1080),
}
const AUDIO_BUS_NAMES := ["Master", "BGM", "SE", "Voice"]

var _config_path: String = DEFAULT_CONFIG_PATH


func _init(config_path: String = "") -> void:
	if not config_path.is_empty():
		_config_path = config_path


func defaults() -> Dictionary:
	return {
		"audio": {
			"master_volume": 100.0,
			"bgm_volume": 100.0,
			"se_volume": 100.0,
			"voice_volume": 100.0,
		},
		"display": {
			"mode": "windowed",
			"resolution": DEFAULT_RESOLUTION,
			"vsync": true,
		},
	}


func normalize(settings: Dictionary) -> Dictionary:
	var normalized := defaults()

	var audio_variant = settings.get("audio", {})
	if audio_variant is Dictionary:
		var audio: Dictionary = audio_variant
		var normalized_audio: Dictionary = normalized["audio"]
		normalized_audio["master_volume"] = _normalize_volume(
			audio.get("master_volume", normalized_audio["master_volume"])
		)
		normalized_audio["bgm_volume"] = _normalize_volume(
			audio.get("bgm_volume", normalized_audio["bgm_volume"])
		)
		normalized_audio["se_volume"] = _normalize_volume(
			audio.get("se_volume", normalized_audio["se_volume"])
		)
		normalized_audio["voice_volume"] = _normalize_volume(
			audio.get("voice_volume", normalized_audio["voice_volume"])
		)

	var display_variant = settings.get("display", {})
	if display_variant is Dictionary:
		var display: Dictionary = display_variant
		var normalized_display: Dictionary = normalized["display"]
		var mode := str(display.get("mode", normalized_display["mode"]))
		if mode in ["windowed", "fullscreen"]:
			normalized_display["mode"] = mode
		var resolution := str(display.get("resolution", normalized_display["resolution"]))
		if RESOLUTIONS.has(resolution):
			normalized_display["resolution"] = resolution
		normalized_display["vsync"] = bool(display.get("vsync", normalized_display["vsync"]))

	return normalized


func load_settings() -> Dictionary:
	var config := ConfigFile.new()
	var error := config.load(_config_path)
	if error != OK:
		return defaults()

	var loaded := {
		"audio": {
			"master_volume": config.get_value("audio", "master_volume", 100.0),
			"bgm_volume": config.get_value("audio", "bgm_volume", 100.0),
			"se_volume": config.get_value("audio", "se_volume", 100.0),
			"voice_volume": config.get_value("audio", "voice_volume", 100.0),
		},
		"display": {
			"mode": config.get_value("display", "mode", "windowed"),
			"resolution": config.get_value("display", "resolution", DEFAULT_RESOLUTION),
			"vsync": config.get_value("display", "vsync", true),
		},
	}
	return normalize(loaded)


func save_settings(settings: Dictionary) -> Dictionary:
	var normalized := normalize(settings)
	var config := ConfigFile.new()
	var audio: Dictionary = normalized["audio"]
	var display: Dictionary = normalized["display"]

	config.set_value("audio", "master_volume", audio["master_volume"])
	config.set_value("audio", "bgm_volume", audio["bgm_volume"])
	config.set_value("audio", "se_volume", audio["se_volume"])
	config.set_value("audio", "voice_volume", audio["voice_volume"])
	config.set_value("display", "mode", display["mode"])
	config.set_value("display", "resolution", display["resolution"])
	config.set_value("display", "vsync", display["vsync"])

	var error := config.save(_config_path)
	return {
		"ok": error == OK,
		"error": error,
		"settings": normalized,
	}


func apply_settings(settings: Dictionary) -> Dictionary:
	var normalized := normalize(settings)
	var audio: Dictionary = normalized["audio"]
	_apply_audio_bus("Master", float(audio["master_volume"]))
	_apply_audio_bus("BGM", float(audio["bgm_volume"]))
	_apply_audio_bus("SE", float(audio["se_volume"]))
	_apply_audio_bus("Voice", float(audio["voice_volume"]))

	var display: Dictionary = normalized["display"]
	if DisplayServer.get_name().to_lower() != "headless":
		var vsync_mode := (
			DisplayServer.VSYNC_ENABLED
			if bool(display["vsync"])
			else DisplayServer.VSYNC_DISABLED
		)
		DisplayServer.window_set_vsync_mode(vsync_mode)

		var resolution_key := str(display["resolution"])
		var resolution: Vector2i = RESOLUTIONS.get(
			resolution_key,
			RESOLUTIONS[DEFAULT_RESOLUTION]
		)
		if str(display["mode"]) == "fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)

	return {
		"ok": true,
		"settings": normalized,
	}


func apply_and_save(settings: Dictionary) -> Dictionary:
	var applied := apply_settings(settings)
	var saved := save_settings(applied["settings"])
	if not bool(saved.get("ok", false)):
		return {
			"ok": false,
			"error": int(saved.get("error", FAILED)),
			"settings": applied["settings"],
		}
	return applied


func load_and_apply() -> Dictionary:
	return apply_settings(load_settings())


func config_path() -> String:
	return _config_path


func _normalize_volume(value) -> float:
	return clampf(float(value), 0.0, 100.0)


func _apply_audio_bus(bus_name: String, volume_percent: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		AudioServer.add_bus()
		bus_index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, bus_name)
		if bus_name != "Master":
			AudioServer.set_bus_send(bus_index, "Master")

	var linear := clampf(volume_percent / 100.0, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_index, linear <= 0.0)
	if linear > 0.0:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear))
