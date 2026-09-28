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

const RANKED_MATCHMAKER_MODE: String = "ranked"
const RANKED_MATCHMAKER_MIN_COUNT: int = 2
const RANKED_MATCHMAKER_MAX_COUNT: int = 2
const RANKED_INITIAL_RATING_RANGE: int = 100
const RANKED_RATING_RANGE_STEP: int = 100
const RANKED_MAX_RATING_RANGE: int = 500
const RANKED_RANGE_EXPAND_INTERVAL_SECONDS: int = 10
const RANKED_PROLONGED_WAIT_SECONDS: int = 60

const RANKED_CHARACTER_LONG_TEST: String = "LONG_TEST"
const RANKED_CHARACTER_SHORT_TEST: String = "SHORT_TEST"
const RANKED_SUPPORTED_CHARACTER_IDS := {
	RANKED_CHARACTER_LONG_TEST: true,
	RANKED_CHARACTER_SHORT_TEST: true,
}


static func is_supported_ranked_character_id(character_id: String) -> bool:
	return bool(RANKED_SUPPORTED_CHARACTER_IDS.get(character_id, false))
