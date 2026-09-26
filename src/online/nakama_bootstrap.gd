extends Node

# Fresh checkoutではGodotのglobal class cacheがまだ存在しないため、
# 公式SDKのclass_name依存を明示的な依存順でpreloadする。
# SDK本体はvendorしたv3.4.0から変更しない。
const _NakamaExceptionScript := preload("res://addons/com.heroiclabs.nakama/utils/NakamaException.gd")
const _NakamaAsyncResultScript := preload("res://addons/com.heroiclabs.nakama/utils/NakamaAsyncResult.gd")
const _NakamaLoggerScript := preload("res://addons/com.heroiclabs.nakama/utils/NakamaLogger.gd")
const _NakamaSerializerScript := preload("res://addons/com.heroiclabs.nakama/utils/NakamaSerializer.gd")
const _NakamaSessionScript := preload("res://addons/com.heroiclabs.nakama/api/NakamaSession.gd")
const _NakamaRTAPIScript := preload("res://addons/com.heroiclabs.nakama/api/NakamaRTAPI.gd")
const _NakamaRTMessageScript := preload("res://addons/com.heroiclabs.nakama/api/NakamaRTMessage.gd")
const _NakamaAPIScript := preload("res://addons/com.heroiclabs.nakama/api/NakamaAPI.gd")
const _NakamaStorageObjectIdScript := preload("res://addons/com.heroiclabs.nakama/api/NakamaStorageObjectId.gd")
const _NakamaWriteStorageObjectScript := preload("res://addons/com.heroiclabs.nakama/api/NakamaWriteStorageObject.gd")
const _NakamaHTTPAdapterScript := preload("res://addons/com.heroiclabs.nakama/client/NakamaHTTPAdapter.gd")
const _NakamaClientScript := preload("res://addons/com.heroiclabs.nakama/client/NakamaClient.gd")
const _NakamaSocketAdapterScript := preload("res://addons/com.heroiclabs.nakama/socket/NakamaSocketAdapter.gd")
const _NakamaSocketScript := preload("res://addons/com.heroiclabs.nakama/socket/NakamaSocket.gd")
const _NakamaMultiplayerPeerScript := preload("res://addons/com.heroiclabs.nakama/utils/NakamaMultiplayerPeer.gd")
const _NakamaMultiplayerBridgeScript := preload("res://addons/com.heroiclabs.nakama/utils/NakamaMultiplayerBridge.gd")
const _OfficialNakamaScript := preload("res://addons/com.heroiclabs.nakama/Nakama.gd")

var _implementation: Node = null


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
	return _ensure_implementation().create_client(
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
	return _ensure_implementation().create_socket(host, port, scheme)


func create_socket_from(client):
	return _ensure_implementation().create_socket_from(client)


func _ensure_implementation() -> Node:
	if _implementation == null:
		_implementation = _OfficialNakamaScript.new()
		_implementation.name = "OfficialNakama"
		add_child(_implementation)
	return _implementation
