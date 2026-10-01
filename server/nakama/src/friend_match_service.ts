const FRIEND_ROOM_COLLECTION = "friend_room";
const FRIEND_ROOM_SYSTEM_USER_ID = "00000000-0000-0000-0000-000000000000";
const FRIEND_ROOM_CODE_CHARSET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const FRIEND_ROOM_CODE_LENGTH = 6;
const FRIEND_ROOM_EXPIRY_MILLISECONDS = 2 * 60 * 60 * 1000;
const FRIEND_ROOM_CREATE_ATTEMPTS = 32;

const FRIEND_ROOM_STATE_WAITING = "WAITING";
const FRIEND_ROOM_STATE_LOBBY = "LOBBY";
const FRIEND_ROOM_STATE_STARTING = "STARTING";
const FRIEND_ROOM_STATE_IN_MATCH = "IN_MATCH";
const FRIEND_ROOM_STATE_POST_MATCH = "POST_MATCH";

const FRIEND_RESULT_ACTION_REMATCH = "rematch";
const FRIEND_RESULT_ACTION_CHANGE_CHARACTER = "change_character";
const FRIEND_RESULT_ACTION_LEAVE = "leave";

interface FriendRoomValue {
  room_code: string;
  host_user_id: string;
  guest_user_id: string;
  host_character_id: string;
  guest_character_id: string;
  host_ready: boolean;
  guest_ready: boolean;
  state: string;
  current_match_id: string;
  match_generation: number;
  created_at_unix_ms: number;
  last_activity_at_unix_ms: number;
  expires_at_unix_ms: number;
}

interface FriendRoomRecord {
  value: FriendRoomValue;
  version: string;
}

function parseFriendRoomPayload(payload: string): any {
  if (!payload) {
    return {};
  }
  try {
    const parsed = JSON.parse(payload);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("invalid payload");
    }
    return parsed;
  } catch (_error) {
    throw new Error("invalid payload");
  }
}

function validFriendRoomCode(roomCode: string): boolean {
  if (roomCode.length !== FRIEND_ROOM_CODE_LENGTH) {
    return false;
  }
  for (let index = 0; index < roomCode.length; index += 1) {
    if (FRIEND_ROOM_CODE_CHARSET.indexOf(roomCode.charAt(index)) < 0) {
      return false;
    }
  }
  return true;
}

function parseFriendRoomCode(parsed: any): string {
  if (!parsed || typeof parsed.room_code !== "string") {
    throw new Error("invalid room_code");
  }
  const roomCode = parsed.room_code;
  if (!validFriendRoomCode(roomCode)) {
    throw new Error("invalid room_code");
  }
  return roomCode;
}

function generateFriendRoomCode(nk: nkruntime.Nakama): string {
  const bytes = new Uint8Array(nk.secureRandomBytes(FRIEND_ROOM_CODE_LENGTH));
  let result = "";
  for (let index = 0; index < FRIEND_ROOM_CODE_LENGTH; index += 1) {
    result += FRIEND_ROOM_CODE_CHARSET.charAt(
      bytes[index] % FRIEND_ROOM_CODE_CHARSET.length
    );
  }
  return result;
}

function defaultFriendRoom(
  roomCode: string,
  hostUserId: string,
  nowUnixMilliseconds: number
): FriendRoomValue {
  return {
    room_code: roomCode,
    host_user_id: hostUserId,
    guest_user_id: "",
    host_character_id: "",
    guest_character_id: "",
    host_ready: false,
    guest_ready: false,
    state: FRIEND_ROOM_STATE_WAITING,
    current_match_id: "",
    match_generation: 0,
    created_at_unix_ms: nowUnixMilliseconds,
    last_activity_at_unix_ms: nowUnixMilliseconds,
    expires_at_unix_ms:
      nowUnixMilliseconds + FRIEND_ROOM_EXPIRY_MILLISECONDS
  };
}

function normalizeFriendRoomValue(raw: any): FriendRoomValue {
  return {
    room_code: String(raw.room_code || ""),
    host_user_id: String(raw.host_user_id || ""),
    guest_user_id: String(raw.guest_user_id || ""),
    host_character_id: String(raw.host_character_id || ""),
    guest_character_id: String(raw.guest_character_id || ""),
    host_ready: raw.host_ready === true,
    guest_ready: raw.guest_ready === true,
    state: String(raw.state || FRIEND_ROOM_STATE_WAITING),
    current_match_id: String(raw.current_match_id || ""),
    match_generation: Number(raw.match_generation || 0),
    created_at_unix_ms: Number(raw.created_at_unix_ms || 0),
    last_activity_at_unix_ms: Number(raw.last_activity_at_unix_ms || 0),
    expires_at_unix_ms: Number(raw.expires_at_unix_ms || 0)
  };
}

function readFriendRoom(
  nk: nkruntime.Nakama,
  roomCode: string
): FriendRoomRecord | null {
  const objects = nk.storageRead([
    {
      collection: FRIEND_ROOM_COLLECTION,
      key: roomCode,
      userId: FRIEND_ROOM_SYSTEM_USER_ID
    }
  ]);
  if (!objects || objects.length === 0) {
    return null;
  }
  return {
    value: normalizeFriendRoomValue(objects[0].value),
    version: objects[0].version
  };
}

function deleteFriendRoom(
  nk: nkruntime.Nakama,
  roomCode: string,
  version: string
): void {
  nk.storageDelete([
    {
      collection: FRIEND_ROOM_COLLECTION,
      key: roomCode,
      userId: FRIEND_ROOM_SYSTEM_USER_ID,
      version: version
    }
  ]);
}

function isFriendRoomExpired(
  room: FriendRoomValue,
  nowUnixMilliseconds: number
): boolean {
  return (
    room.expires_at_unix_ms > 0 &&
    nowUnixMilliseconds >= room.expires_at_unix_ms
  );
}

function requireFriendRoom(
  nk: nkruntime.Nakama,
  roomCode: string,
  nowUnixMilliseconds: number
): FriendRoomRecord {
  const record = readFriendRoom(nk, roomCode);
  if (!record) {
    throw new Error("friend room not found");
  }
  if (isFriendRoomExpired(record.value, nowUnixMilliseconds)) {
    try {
      deleteFriendRoom(nk, roomCode, record.version);
    } catch (_error) {
      // Another request may already have deleted or changed the room.
    }
    throw new Error("friend room expired");
  }
  return record;
}

function friendRoomRole(room: FriendRoomValue, userId: string): string {
  if (room.host_user_id === userId) {
    return "host";
  }
  if (room.guest_user_id === userId) {
    return "guest";
  }
  return "";
}

function requireFriendRoomMember(
  room: FriendRoomValue,
  userId: string
): string {
  const role = friendRoomRole(room, userId);
  if (!role) {
    throw new Error("friend room membership required");
  }
  return role;
}

function touchFriendRoom(
  room: FriendRoomValue,
  nowUnixMilliseconds: number
): void {
  room.last_activity_at_unix_ms = nowUnixMilliseconds;
  room.expires_at_unix_ms =
    nowUnixMilliseconds + FRIEND_ROOM_EXPIRY_MILLISECONDS;
}

function friendRoomWriteRequest(
  room: FriendRoomValue,
  version: string
): nkruntime.StorageWriteRequest {
  return {
    collection: FRIEND_ROOM_COLLECTION,
    key: room.room_code,
    userId: FRIEND_ROOM_SYSTEM_USER_ID,
    value: room as any,
    version: version,
    permissionRead: 0,
    permissionWrite: 0
  };
}

function writeFriendRoom(
  nk: nkruntime.Nakama,
  room: FriendRoomValue,
  version: string
): FriendRoomRecord {
  const acks = nk.storageWrite([friendRoomWriteRequest(room, version)]);
  if (!acks || acks.length !== 1) {
    throw new Error("friend room write failed");
  }
  return {
    value: room,
    version: acks[0].version
  };
}

function friendRoomResponse(
  room: FriendRoomValue,
  userId: string
): {[key: string]: any} {
  return {
    room_code: room.room_code,
    role: friendRoomRole(room, userId),
    state: room.state,
    host_user_id: room.host_user_id,
    guest_user_id: room.guest_user_id,
    host_character_id: room.host_character_id,
    guest_character_id: room.guest_character_id,
    host_ready: room.host_ready,
    guest_ready: room.guest_ready,
    current_match_id: room.current_match_id,
    match_generation: room.match_generation,
    expires_at_unix_ms: room.expires_at_unix_ms
  };
}

function createFriendRoom(
  nk: nkruntime.Nakama,
  hostUserId: string,
  nowUnixMilliseconds: number
): FriendRoomRecord {
  for (
    let attempt = 0;
    attempt < FRIEND_ROOM_CREATE_ATTEMPTS;
    attempt += 1
  ) {
    const roomCode = generateFriendRoomCode(nk);
    if (readFriendRoom(nk, roomCode)) {
      continue;
    }

    const room = defaultFriendRoom(
      roomCode,
      hostUserId,
      nowUnixMilliseconds
    );
    try {
      return writeFriendRoom(nk, room, "*");
    } catch (error) {
      // create-only writeが競合した場合だけ別codeへ進む。
      if (readFriendRoom(nk, roomCode)) {
        continue;
      }
      throw error;
    }
  }
  throw new Error("friend room code allocation failed");
}

function roomCharacterForRole(
  room: FriendRoomValue,
  role: string
): string {
  return role === "host"
    ? room.host_character_id
    : room.guest_character_id;
}

function setRoomCharacterForRole(
  room: FriendRoomValue,
  role: string,
  characterId: string
): void {
  if (role === "host") {
    room.host_character_id = characterId;
    room.host_ready = false;
    return;
  }
  room.guest_character_id = characterId;
  room.guest_ready = false;
}

function roomReadyForRole(room: FriendRoomValue, role: string): boolean {
  return role === "host" ? room.host_ready : room.guest_ready;
}

function setRoomReadyForRole(
  room: FriendRoomValue,
  role: string,
  ready: boolean
): void {
  if (role === "host") {
    room.host_ready = ready;
    return;
  }
  room.guest_ready = ready;
}

function friendRoomCreateRpc(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  _payload: string
): string {
  if (!ctx.userId) {
    throw new Error("authentication required");
  }

  requireNoActiveOnlineMatchForUser(nk, ctx.userId);
  const room = createFriendRoom(nk, ctx.userId, Date.now());
  return JSON.stringify(friendRoomResponse(room.value, ctx.userId));
}

function friendRoomJoinRpc(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) {
    throw new Error("authentication required");
  }

  requireNoActiveOnlineMatchForUser(nk, ctx.userId);
  const parsed = parseFriendRoomPayload(payload);
  const roomCode = parseFriendRoomCode(parsed);
  const now = Date.now();

  for (let attempt = 0; attempt < 4; attempt += 1) {
    const record = requireFriendRoom(nk, roomCode, now);
    const room = record.value;
    const role = friendRoomRole(room, ctx.userId);

    if (role) {
      return JSON.stringify(friendRoomResponse(room, ctx.userId));
    }
    if (room.guest_user_id) {
      throw new Error("friend room is full");
    }
    if (
      room.state === FRIEND_ROOM_STATE_STARTING ||
      room.state === FRIEND_ROOM_STATE_IN_MATCH
    ) {
      throw new Error("friend room match is active");
    }

    room.guest_user_id = ctx.userId;
    room.guest_character_id = "";
    room.guest_ready = false;
    room.host_ready = false;
    room.current_match_id = "";
    room.state = FRIEND_ROOM_STATE_LOBBY;
    touchFriendRoom(room, now);

    try {
      const updated = writeFriendRoom(nk, room, record.version);
      return JSON.stringify(friendRoomResponse(updated.value, ctx.userId));
    } catch (_error) {
      // optimistic concurrency conflict: reread and retry.
    }
  }
  throw new Error("friend room join conflict");
}

function friendRoomStatusRpc(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) {
    throw new Error("authentication required");
  }

  const parsed = parseFriendRoomPayload(payload);
  const roomCode = parseFriendRoomCode(parsed);
  const record = requireFriendRoom(nk, roomCode, Date.now());
  requireFriendRoomMember(record.value, ctx.userId);
  return JSON.stringify(friendRoomResponse(record.value, ctx.userId));
}

function friendRoomCharacterRpc(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) {
    throw new Error("authentication required");
  }

  const parsed = parseFriendRoomPayload(payload);
  const roomCode = parseFriendRoomCode(parsed);
  if (typeof parsed.character_id !== "string") {
    throw new Error("invalid character_id");
  }
  const characterId = parsed.character_id;
  if (!isSupportedCharacterId(characterId)) {
    throw new Error("unsupported character_id");
  }

  const now = Date.now();
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const record = requireFriendRoom(nk, roomCode, now);
    const room = record.value;
    const role = requireFriendRoomMember(room, ctx.userId);
    if (
      room.state === FRIEND_ROOM_STATE_STARTING ||
      room.state === FRIEND_ROOM_STATE_IN_MATCH
    ) {
      throw new Error("friend room match is active");
    }
    if (room.state === FRIEND_ROOM_STATE_POST_MATCH) {
      throw new Error("friend result action required");
    }

    setRoomCharacterForRole(room, role, characterId);
    room.state = room.guest_user_id
      ? FRIEND_ROOM_STATE_LOBBY
      : FRIEND_ROOM_STATE_WAITING;
    touchFriendRoom(room, now);

    try {
      const updated = writeFriendRoom(nk, room, record.version);
      return JSON.stringify(friendRoomResponse(updated.value, ctx.userId));
    } catch (_error) {
      // optimistic concurrency conflict: reread and retry.
    }
  }
  throw new Error("friend room character update conflict");
}

function finalizeStartedFriendMatch(
  nk: nkruntime.Nakama,
  roomCode: string,
  startVersion: string,
  matchId: string,
  matchGeneration: number,
  nowUnixMilliseconds: number
): FriendRoomRecord {
  let expectedVersion = startVersion;
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const record = requireFriendRoom(nk, roomCode, nowUnixMilliseconds);
    const room = record.value;
    if (
      room.state !== FRIEND_ROOM_STATE_STARTING ||
      room.match_generation !== matchGeneration
    ) {
      throw new Error("friend room start state changed");
    }

    room.state = FRIEND_ROOM_STATE_IN_MATCH;
    room.current_match_id = matchId;
    touchFriendRoom(room, nowUnixMilliseconds);
    try {
      return writeFriendRoom(
        nk,
        room,
        attempt === 0 ? expectedVersion : record.version
      );
    } catch (_error) {
      expectedVersion = record.version;
    }
  }
  throw new Error("friend room match publish failed");
}

function rollbackFriendRoomStart(
  nk: nkruntime.Nakama,
  roomCode: string,
  matchGeneration: number
): void {
  for (let attempt = 0; attempt < 3; attempt += 1) {
    const record = readFriendRoom(nk, roomCode);
    if (!record) {
      return;
    }
    const room = record.value;
    if (
      room.state !== FRIEND_ROOM_STATE_STARTING ||
      room.match_generation !== matchGeneration
    ) {
      return;
    }
    room.state = FRIEND_ROOM_STATE_LOBBY;
    room.host_ready = false;
    room.guest_ready = false;
    room.current_match_id = "";
    touchFriendRoom(room, Date.now());
    try {
      writeFriendRoom(nk, room, record.version);
      return;
    } catch (_error) {
      // retry.
    }
  }
}

function friendRoomReadyRpc(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) {
    throw new Error("authentication required");
  }

  const parsed = parseFriendRoomPayload(payload);
  const roomCode = parseFriendRoomCode(parsed);
  if (typeof parsed.ready !== "boolean") {
    throw new Error("invalid ready");
  }
  const requestedReady = parsed.ready;
  if (requestedReady) {
    requireNoActiveOnlineMatchForUser(nk, ctx.userId);
  }
  const now = Date.now();

  for (let attempt = 0; attempt < 4; attempt += 1) {
    const record = requireFriendRoom(nk, roomCode, now);
    const room = record.value;
    const role = requireFriendRoomMember(room, ctx.userId);

    if (
      room.state === FRIEND_ROOM_STATE_STARTING ||
      room.state === FRIEND_ROOM_STATE_IN_MATCH
    ) {
      throw new Error("friend room match is active");
    }
    if (room.state === FRIEND_ROOM_STATE_POST_MATCH) {
      throw new Error("friend result action required");
    }
    if (!room.guest_user_id) {
      throw new Error("friend room is waiting for guest");
    }
    if (
      !isSupportedCharacterId(room.host_character_id) ||
      !isSupportedCharacterId(room.guest_character_id)
    ) {
      throw new Error("both players must select character");
    }

    const wasReady = roomReadyForRole(room, role);
    if (wasReady === requestedReady) {
      return JSON.stringify(friendRoomResponse(room, ctx.userId));
    }

    setRoomReadyForRole(room, role, requestedReady);
    const shouldStart =
      requestedReady &&
      room.host_ready &&
      room.guest_ready;

    if (shouldStart) {
      room.state = FRIEND_ROOM_STATE_STARTING;
      room.match_generation += 1;
    } else {
      room.state = FRIEND_ROOM_STATE_LOBBY;
    }
    touchFriendRoom(room, now);

    let updated: FriendRoomRecord;
    try {
      updated = writeFriendRoom(nk, room, record.version);
    } catch (_error) {
      continue;
    }

    if (!shouldStart) {
      return JSON.stringify(friendRoomResponse(updated.value, ctx.userId));
    }

    const matchGeneration = updated.value.match_generation;
    let matchId = "";
    try {
      matchId = nk.matchCreate("ahoge_ranked", {
        matchMode: "friend",
        expectedUserIds: [
          updated.value.host_user_id,
          updated.value.guest_user_id
        ],
        characterIds: {
          [updated.value.host_user_id]: updated.value.host_character_id,
          [updated.value.guest_user_id]: updated.value.guest_character_id
        },
        friendRoomCode: roomCode,
        friendMatchGeneration: matchGeneration
      });
    } catch (error) {
      rollbackFriendRoomStart(nk, roomCode, matchGeneration);
      throw error;
    }

    const started = finalizeStartedFriendMatch(
      nk,
      roomCode,
      updated.version,
      matchId,
      matchGeneration,
      now
    );
    return JSON.stringify(friendRoomResponse(started.value, ctx.userId));
  }

  throw new Error("friend room ready conflict");
}

function friendRoomResultActionRpc(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) {
    throw new Error("authentication required");
  }

  const parsed = parseFriendRoomPayload(payload);
  const roomCode = parseFriendRoomCode(parsed);
  if (typeof parsed.action !== "string") {
    throw new Error("invalid result action");
  }
  const action = parsed.action;
  if (
    action !== FRIEND_RESULT_ACTION_REMATCH &&
    action !== FRIEND_RESULT_ACTION_CHANGE_CHARACTER &&
    action !== FRIEND_RESULT_ACTION_LEAVE
  ) {
    throw new Error("invalid result action");
  }

  const now = Date.now();
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const record = requireFriendRoom(nk, roomCode, now);
    const room = record.value;
    if (room.host_user_id !== ctx.userId) {
      throw new Error("friend result action is host only");
    }
    if (room.state !== FRIEND_ROOM_STATE_POST_MATCH) {
      throw new Error("friend room is not waiting for result action");
    }

    if (action === FRIEND_RESULT_ACTION_LEAVE) {
      try {
        deleteFriendRoom(nk, roomCode, record.version);
        return JSON.stringify({
          room_code: roomCode,
          action: action,
          closed: true
        });
      } catch (_error) {
        continue;
      }
    }

    if (action === FRIEND_RESULT_ACTION_CHANGE_CHARACTER) {
      room.state = FRIEND_ROOM_STATE_WAITING;
      room.current_match_id = "";
      room.host_character_id = "";
      room.host_ready = false;
      room.guest_user_id = "";
      room.guest_character_id = "";
      room.guest_ready = false;
      touchFriendRoom(room, now);
      try {
        const updated = writeFriendRoom(nk, room, record.version);
        const response = friendRoomResponse(updated.value, ctx.userId);
        response.action = action;
        return JSON.stringify(response);
      } catch (_error) {
        continue;
      }
    }

    if (
      !room.guest_user_id ||
      !isSupportedCharacterId(room.host_character_id) ||
      !isSupportedCharacterId(room.guest_character_id)
    ) {
      throw new Error("friend rematch participants are incomplete");
    }

    requireNoActiveOnlineMatchForUser(nk, room.host_user_id);
    requireNoActiveOnlineMatchForUser(nk, room.guest_user_id);

    room.state = FRIEND_ROOM_STATE_STARTING;
    room.current_match_id = "";
    room.host_ready = false;
    room.guest_ready = false;
    room.match_generation += 1;
    touchFriendRoom(room, now);

    let updated: FriendRoomRecord;
    try {
      updated = writeFriendRoom(nk, room, record.version);
    } catch (_error) {
      continue;
    }

    const matchGeneration = updated.value.match_generation;
    let matchId = "";
    try {
      matchId = nk.matchCreate("ahoge_ranked", {
        matchMode: "friend",
        expectedUserIds: [
          updated.value.host_user_id,
          updated.value.guest_user_id
        ],
        characterIds: {
          [updated.value.host_user_id]: updated.value.host_character_id,
          [updated.value.guest_user_id]: updated.value.guest_character_id
        },
        friendRoomCode: roomCode,
        friendMatchGeneration: matchGeneration
      });
    } catch (error) {
      for (let rollbackAttempt = 0; rollbackAttempt < 3; rollbackAttempt += 1) {
        const rollbackRecord = readFriendRoom(nk, roomCode);
        if (!rollbackRecord) {
          break;
        }
        const rollbackRoom = rollbackRecord.value;
        if (
          rollbackRoom.state !== FRIEND_ROOM_STATE_STARTING ||
          rollbackRoom.match_generation !== matchGeneration
        ) {
          break;
        }
        rollbackRoom.state = FRIEND_ROOM_STATE_POST_MATCH;
        rollbackRoom.current_match_id = "";
        rollbackRoom.host_ready = false;
        rollbackRoom.guest_ready = false;
        touchFriendRoom(rollbackRoom, Date.now());
        try {
          writeFriendRoom(nk, rollbackRoom, rollbackRecord.version);
          break;
        } catch (_rollbackError) {
          // retry.
        }
      }
      throw error;
    }

    const started = finalizeStartedFriendMatch(
      nk,
      roomCode,
      updated.version,
      matchId,
      matchGeneration,
      now
    );
    const response = friendRoomResponse(started.value, ctx.userId);
    response.action = action;
    return JSON.stringify(response);
  }

  throw new Error("friend result action conflict");
}


function friendRoomLeaveRpc(
  ctx: nkruntime.Context,
  _logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  payload: string
): string {
  if (!ctx.userId) {
    throw new Error("authentication required");
  }

  const parsed = parseFriendRoomPayload(payload);
  const roomCode = parseFriendRoomCode(parsed);
  const now = Date.now();

  for (let attempt = 0; attempt < 4; attempt += 1) {
    const record = requireFriendRoom(nk, roomCode, now);
    const room = record.value;
    const role = requireFriendRoomMember(room, ctx.userId);

    if (
      room.state === FRIEND_ROOM_STATE_STARTING ||
      room.state === FRIEND_ROOM_STATE_IN_MATCH
    ) {
      throw new Error("active friend match must be resolved first");
    }
    if (room.state === FRIEND_ROOM_STATE_POST_MATCH) {
      throw new Error("friend result action required");
    }

    if (role === "host") {
      try {
        deleteFriendRoom(nk, roomCode, record.version);
        return JSON.stringify({
          room_code: roomCode,
          closed: true
        });
      } catch (_error) {
        continue;
      }
    }

    room.guest_user_id = "";
    room.guest_character_id = "";
    room.guest_ready = false;
    room.host_ready = false;
    room.current_match_id = "";
    room.state = FRIEND_ROOM_STATE_WAITING;
    touchFriendRoom(room, now);
    try {
      const updated = writeFriendRoom(nk, room, record.version);
      return JSON.stringify({
        room_code: roomCode,
        closed: false,
        state: updated.value.state
      });
    } catch (_error) {
      // optimistic concurrency conflict: reread and retry.
    }
  }

  throw new Error("friend room leave conflict");
}

function markFriendRoomMatchFinished(
  nk: nkruntime.Nakama,
  roomCode: string,
  matchId: string,
  matchGeneration: number
): boolean {
  if (!roomCode || !matchId || matchGeneration <= 0) {
    return true;
  }

  for (let attempt = 0; attempt < 4; attempt += 1) {
    const record = readFriendRoom(nk, roomCode);
    if (!record) {
      return true;
    }
    const room = record.value;

    if (room.match_generation !== matchGeneration) {
      return true;
    }
    if (
      room.state !== FRIEND_ROOM_STATE_IN_MATCH &&
      room.state !== FRIEND_ROOM_STATE_STARTING
    ) {
      return true;
    }
    if (room.current_match_id && room.current_match_id !== matchId) {
      return true;
    }

    // Result選択はHostだけが行うため、POST_MATCH中は対戦参加者とCharacterを保持する。
    room.state = FRIEND_ROOM_STATE_POST_MATCH;
    room.current_match_id = matchId;
    room.host_ready = false;
    room.guest_ready = false;
    touchFriendRoom(room, Date.now());

    try {
      writeFriendRoom(nk, room, record.version);
      return true;
    } catch (_error) {
      // optimistic concurrency conflict: reread and retry.
    }
  }
  return false;
}
