extends Node

const OnlineConfigScript := preload("res://src/config/online_config.gd")
const DeviceIdentityStoreScript := preload("res://src/online/device_identity_store.gd")

signal authentication_succeeded(user_id: String, username: String)
signal authentication_failed(step: String, message: String)

var client = null
var session = null
var account = null
var _identity_store = null


func _ready() -> void:
	_identity_store = DeviceIdentityStoreScript.new(OnlineConfigScript.DEVICE_ID_PATH)


func create_local_client():
	client = Nakama.create_client(
		OnlineConfigScript.SERVER_KEY,
		OnlineConfigScript.HOST,
		OnlineConfigScript.PORT,
		OnlineConfigScript.SCHEME,
		OnlineConfigScript.CLIENT_TIMEOUT_SECONDS,
		OnlineConfigScript.CLIENT_LOG_LEVEL
	)
	return client


func get_or_create_device_id() -> String:
	if _identity_store == null:
		_identity_store = DeviceIdentityStoreScript.new(OnlineConfigScript.DEVICE_ID_PATH)
	return _identity_store.load_or_create()


func authenticate_local_device() -> Dictionary:
	if client == null:
		create_local_client()

	var device_id := get_or_create_device_id()
	if device_id.is_empty():
		return _fail("device_id", "Device IDを生成または保存できませんでした。")

	var auth_result = await client.authenticate_device_async(device_id, null, true)
	if auth_result == null or auth_result.is_exception():
		return _fail_from_result("authenticate_device", auth_result)

	session = auth_result

	var account_result = await client.get_account_async(session)
	if account_result == null or account_result.is_exception():
		session = null
		return _fail_from_result("get_account", account_result)

	account = account_result

	var user_id := str(session.user_id)
	var username := str(session.username)
	print("Nakama local authentication succeeded: user_id=%s username=%s" % [user_id, username])
	authentication_succeeded.emit(user_id, username)

	return {
		"ok": true,
		"user_id": user_id,
		"username": username,
		"created": bool(session.created),
		"account_user_id": str(account.user.id),
	}


func is_authenticated() -> bool:
	return session != null and session.valid and not session.expired


func clear_session() -> void:
	session = null
	account = null


func _fail_from_result(step: String, result) -> Dictionary:
	var message := "Unknown Nakama error"
	if result != null and result.has_method("get_exception"):
		var exception = result.get_exception()
		if exception != null:
			message = str(exception.message)
	return _fail(step, message)


func _fail(step: String, message: String) -> Dictionary:
	printerr("Nakama local authentication failed: step=%s message=%s" % [step, message])
	authentication_failed.emit(step, message)
	return {
		"ok": false,
		"step": step,
		"message": message,
	}
