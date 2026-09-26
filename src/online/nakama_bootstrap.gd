extends Node

# Fresh checkoutではGodotのglobal class cacheがまだ存在しないため、
# 公式SDKのclass_name依存を依存順に実行時load()して登録する。
# SDK本体はvendorしたv3.4.0から変更しない。
const _DEPENDENCY_PATHS := [
	"res://addons/com.heroiclabs.nakama/utils/NakamaException.gd",
	"res://addons/com.heroiclabs.nakama/utils/NakamaAsyncResult.gd",
	"res://addons/com.heroiclabs.nakama/utils/NakamaLogger.gd",
	"res://addons/com.heroiclabs.nakama/utils/NakamaSerializer.gd",
	"res://addons/com.heroiclabs.nakama/api/NakamaSession.gd",
	"res://addons/com.heroiclabs.nakama/api/NakamaRTAPI.gd",
	"res://addons/com.heroiclabs.nakama/api/NakamaRTMessage.gd",
	"res://addons/com.heroiclabs.nakama/api/NakamaAPI.gd",
	"res://addons/com.heroiclabs.nakama/api/NakamaStorageObjectId.gd",
	"res://addons/com.heroiclabs.nakama/api/NakamaWriteStorageObject.gd",
	"res://addons/com.heroiclabs.nakama/client/NakamaHTTPAdapter.gd",
	"res://addons/com.heroiclabs.nakama/client/NakamaClient.gd",
	"res://addons/com.heroiclabs.nakama/socket/NakamaSocketAdapter.gd",
	"res://addons/com.heroiclabs.nakama/socket/NakamaSocket.gd",
	"res://addons/com.heroiclabs.nakama/utils/NakamaMultiplayerPeer.gd",
	"res://addons/com.heroiclabs.nakama/utils/NakamaMultiplayerBridge.gd",
]

const _OFFICIAL_NAKAMA_PATH := "res://addons/com.heroiclabs.nakama/Nakama.gd"

var _dependency_scripts: Array = []
var _official_script = null
var _implementation: Node = null
var _load_error: String = ""


func _ready() -> void:
	_ensure_implementation()


func create_client(
	server_key: String,
	host: String = "127.0.0.1",
	port: int = 7350,
	scheme: String = "http",
	timeout: int = 3,
	log_level: int = 0
):
	var implementation := _ensure_implementation()
	if implementation == null:
		push_error("Nakama SDK bootstrap failed: %s" % _load_error)
		return null
	return implementation.create_client(
		server_key,
		host,
		port,
		scheme,
		timeout,
		log_level
	)


func create_socket(
	host: String = "127.0.0.1",
	port: int = 7350,
	scheme: String = "ws"
):
	var implementation := _ensure_implementation()
	if implementation == null:
		push_error("Nakama SDK bootstrap failed: %s" % _load_error)
		return null
	return implementation.create_socket(host, port, scheme)


func create_socket_from(client):
	var implementation := _ensure_implementation()
	if implementation == null:
		push_error("Nakama SDK bootstrap failed: %s" % _load_error)
		return null
	return implementation.create_socket_from(client)


func is_ready() -> bool:
	return _ensure_implementation() != null


func load_error() -> String:
	return _load_error


func _ensure_implementation() -> Node:
	if _implementation != null:
		return _implementation
	if not _load_error.is_empty():
		return null

	for path in _DEPENDENCY_PATHS:
		var script = load(path)
		if script == null:
			_load_error = "SDK dependencyをloadできません: %s" % path
			push_error(_load_error)
			return null
		_dependency_scripts.append(script)

	_official_script = load(_OFFICIAL_NAKAMA_PATH)
	if _official_script == null:
		_load_error = "公式Nakama.gdをloadできません。"
		push_error(_load_error)
		return null

	var implementation = _official_script.new()
	if not implementation is Node:
		_load_error = "公式Nakama.gdをNodeとして生成できません。"
		push_error(_load_error)
		return null

	_implementation = implementation
	_implementation.name = "OfficialNakama"
	add_child(_implementation)
	return _implementation
