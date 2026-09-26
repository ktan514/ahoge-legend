extends RefCounted

const SCHEME: String = "http"
const HOST: String = "127.0.0.1"
const PORT: int = 7350
const SERVER_KEY: String = "defaultkey"
const DEVICE_ID_PATH: String = "user://ahoge_device_id.txt"

const CLIENT_TIMEOUT_SECONDS: int = 3
# NakamaLogger.LOG_LEVEL.ERROR。DEBUGはAuthorization Bearerをrequest logへ含めるため使用しない。
const CLIENT_LOG_LEVEL: int = 1
