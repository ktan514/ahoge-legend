extends RefCounted

const SCHEME: String = "http"
const HOST: String = "127.0.0.1"
const PORT: int = 7350
const SERVER_KEY: String = "defaultkey"
const DEVICE_ID_PATH: String = "user://ahoge_device_id.txt"

const CLIENT_TIMEOUT_SECONDS: int = 3
# NakamaLogger.LOG_LEVEL.ERROR。DEBUGはAuthorization Bearerをrequest logへ含めるため使用しない。
const CLIENT_LOG_LEVEL: int = 1

const SOCKET_CONNECT_TIMEOUT_SECONDS: int = 3
const SOCKET_APPEAR_ONLINE: bool = false
const RECONNECT_GRACE_SECONDS: int = 15
const RECONNECT_RETRY_SECONDS: float = 0.5
const MATCH_RECOVERY_TIMEOUT_SECONDS: int = 10
const MATCH_RECOVERY_RETRY_LIMIT: int = 2

const ACTIVE_MATCH_RPC_GET: String = "ahoge_active_match_get"
const ACTIVE_MATCH_RPC_ACK: String = "ahoge_active_match_ack"
const MATCH_MODE_RANKED: String = "ranked"
const MATCH_MODE_FRIEND: String = "friend"
const ACTIVE_MATCH_STATE_ACTIVE: String = "ACTIVE"
const ACTIVE_MATCH_STATE_RESULT_PENDING: String = "RESULT_PENDING"

const RANKED_MATCHMAKER_MODE: String = "ranked"
const RANKED_MATCHMAKER_MIN_COUNT: int = 2
const RANKED_MATCHMAKER_MAX_COUNT: int = 2
const RANKED_INITIAL_RATING_RANGE: int = 100
const RANKED_RATING_RANGE_STEP: int = 100
const RANKED_MAX_RATING_RANGE: int = 500
const RANKED_RANGE_EXPAND_INTERVAL_SECONDS: int = 10
const RANKED_PROLONGED_WAIT_SECONDS: int = 60

const FRIEND_ROOM_CODE_LENGTH: int = 6
const FRIEND_ROOM_CODE_CHARSET: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const FRIEND_ROOM_RPC_CREATE: String = "ahoge_friend_room_create"
const FRIEND_ROOM_RPC_JOIN: String = "ahoge_friend_room_join"
const FRIEND_ROOM_RPC_STATUS: String = "ahoge_friend_room_status"
const FRIEND_ROOM_RPC_CHARACTER: String = "ahoge_friend_room_character"
const FRIEND_ROOM_RPC_READY: String = "ahoge_friend_room_ready"
const FRIEND_ROOM_RPC_LEAVE: String = "ahoge_friend_room_leave"

const RANKED_CHARACTER_LONG_TEST: String = "LONG_TEST"
const RANKED_CHARACTER_SHORT_TEST: String = "SHORT_TEST"
const RANKED_SUPPORTED_CHARACTER_IDS := {
	RANKED_CHARACTER_LONG_TEST: true,
	RANKED_CHARACTER_SHORT_TEST: true,
}


static func is_supported_online_character_id(character_id: String) -> bool:
	return bool(RANKED_SUPPORTED_CHARACTER_IDS.get(character_id, false))


static func is_supported_ranked_character_id(character_id: String) -> bool:
	return is_supported_online_character_id(character_id)
