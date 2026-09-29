const ACTIVE_ONLINE_MATCH_COLLECTION = "active_online_match";
const ACTIVE_ONLINE_MATCH_KEY = "current";
const ACTIVE_ONLINE_MATCH_STATE_ACTIVE = "ACTIVE";
const ACTIVE_ONLINE_MATCH_STATE_RESULT_PENDING = "RESULT_PENDING";

interface ActiveOnlineMatchValue {
  match_id: string;
  match_mode: string;
  state: string;
  created_at_unix_ms: number;
  updated_at_unix_ms: number;
  result_snapshot: any;
}

interface ActiveOnlineMatchRecord {
  value: ActiveOnlineMatchValue;
  version: string;
}

function normalizeActiveOnlineMatchValue(raw: any): ActiveOnlineMatchValue {
  return {
    match_id: String(raw.match_id || ""),
    match_mode: String(raw.match_mode || ""),
    state: String(raw.state || ""),
    created_at_unix_ms: Number(raw.created_at_unix_ms || 0),
    updated_at_unix_ms: Number(raw.updated_at_unix_ms || 0),
    result_snapshot:
      raw.result_snapshot && typeof raw.result_snapshot === "object"
        ? raw.result_snapshot
        : {}
  };
}

function readActiveOnlineMatch(
  nk: nkruntime.Nakama,
  userId: string
): ActiveOnlineMatchRecord | null {
  const objects = nk.storageRead([
    {
      collection: ACTIVE_ONLINE_MATCH_COLLECTION,
      key: ACTIVE_ONLINE_MATCH_KEY,
      userId: userId
    }
  ]);
  if (!objects || objects.length === 0) {
    return null;
  }
  return {
    value: normalizeActiveOnlineMatchValue(objects[0].value),
    version: objects[0].version
  };
}

function deleteActiveOnlineMatch(
  nk: nkruntime.Nakama,
  userId: string,
  version: string
): void {
  nk.storageDelete([
    {
      collection: ACTIVE_ONLINE_MATCH_COLLECTION,
      key: ACTIVE_ONLINE_MATCH_KEY,
      userId: userId,
      version: version
    }
  ]);
}

function validActiveOnlineMatch(value: ActiveOnlineMatchValue): boolean {
  return (
    !!value.match_id &&
    (value.match_mode === "ranked" || value.match_mode === "friend") &&
    (
      value.state === ACTIVE_ONLINE_MATCH_STATE_ACTIVE ||
      value.state === ACTIVE_ONLINE_MATCH_STATE_RESULT_PENDING
    )
  );
}

function resolveActiveOnlineMatchForUser(
  nk: nkruntime.Nakama,
  userId: string
): ActiveOnlineMatchRecord | null {
  const record = readActiveOnlineMatch(nk, userId);
  if (!record) {
    return null;
  }

  if (!validActiveOnlineMatch(record.value)) {
    try {
      deleteActiveOnlineMatch(nk, userId, record.version);
    } catch (_error) {
      // A concurrent request may already have replaced or deleted it.
    }
    return null;
  }

  if (record.value.state === ACTIVE_ONLINE_MATCH_STATE_ACTIVE) {
    let runningMatch: nkruntime.Match | null = null;
    try {
      runningMatch = nk.matchGet(record.value.match_id);
    } catch (_error) {
      runningMatch = null;
    }
    if (!runningMatch) {
      try {
        deleteActiveOnlineMatch(nk, userId, record.version);
      } catch (_error) {
        // A concurrent request may already have replaced or deleted it.
      }
      return null;
    }
  }

  return record;
}

function requireNoActiveOnlineMatchForUser(
  nk: nkruntime.Nakama,
  userId: string
): void {
  if (resolveActiveOnlineMatchForUser(nk, userId)) {
    throw new Error("unresolved online match exists");
  }
}

function createActiveOnlineMatchForUsers(
  nk: nkruntime.Nakama,
  userIds: string[],
  matchId: string,
  matchMode: string,
  nowUnixMilliseconds: number
): void {
  if (!matchId || (matchMode !== "ranked" && matchMode !== "friend")) {
    throw new Error("invalid active online match");
  }

  userIds.forEach(function (userId): void {
    requireNoActiveOnlineMatchForUser(nk, userId);
  });

  const writes: nkruntime.StorageWriteRequest[] = userIds.map(
    function (userId): nkruntime.StorageWriteRequest {
      const value: ActiveOnlineMatchValue = {
        match_id: matchId,
        match_mode: matchMode,
        state: ACTIVE_ONLINE_MATCH_STATE_ACTIVE,
        created_at_unix_ms: nowUnixMilliseconds,
        updated_at_unix_ms: nowUnixMilliseconds,
        result_snapshot: {}
      };
      return {
        collection: ACTIVE_ONLINE_MATCH_COLLECTION,
        key: ACTIVE_ONLINE_MATCH_KEY,
        userId: userId,
        value: value as any,
        version: "*",
        permissionRead: 0,
        permissionWrite: 0
      };
    }
  );

  nk.storageWrite(writes);
}

function markActiveOnlineMatchResult(
  nk: nkruntime.Nakama,
  userIds: string[],
  matchId: string,
  matchMode: string,
  resultSnapshot: any,
  nowUnixMilliseconds: number
): boolean {
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const writes: nkruntime.StorageWriteRequest[] = [];
    let conflict = false;

    userIds.forEach(function (userId): void {
      const record = readActiveOnlineMatch(nk, userId);
      if (record && record.value.match_id !== matchId) {
        conflict = true;
        return;
      }

      const createdAt =
        record && record.value.created_at_unix_ms > 0
          ? record.value.created_at_unix_ms
          : nowUnixMilliseconds;
      const value: ActiveOnlineMatchValue = {
        match_id: matchId,
        match_mode: matchMode,
        state: ACTIVE_ONLINE_MATCH_STATE_RESULT_PENDING,
        created_at_unix_ms: createdAt,
        updated_at_unix_ms: nowUnixMilliseconds,
        result_snapshot: resultSnapshot
      };

      writes.push({
        collection: ACTIVE_ONLINE_MATCH_COLLECTION,
        key: ACTIVE_ONLINE_MATCH_KEY,
        userId: userId,
        value: value as any,
        version: record ? record.version : "*",
        permissionRead: 0,
        permissionWrite: 0
      });
    });

    if (conflict) {
      return false;
    }

    try {
      nk.storageWrite(writes);
      return true;
    } catch (_error) {
      // Optimistic concurrency conflict: reread and retry.
    }
  }
  return false;
}

function activeOnlineMatchResponse(
  record: ActiveOnlineMatchRecord | null
): {[key: string]: any} {
  if (!record) {
    return {
      active: false
    };
  }
  return {
    active: true,
    match_id: record.value.match_id,
    match_mode: record.value.match_mode,
    state: record.value.state,
    created_at_unix_ms: record.value.created_at_unix_ms,
    updated_at_unix_ms: record.value.updated_at_unix_ms,
    result_snapshot: record.value.result_snapshot
  };
}

const activeOnlineMatchGetRpc: nkruntime.RpcFunction = function (
  ctx,
  _logger,
  nk,
  _payload
): string {
  if (!ctx.userId) {
    throw new Error("authentication required");
  }

  return JSON.stringify(
    activeOnlineMatchResponse(
      resolveActiveOnlineMatchForUser(nk, ctx.userId)
    )
  );
};

const activeOnlineMatchAckRpc: nkruntime.RpcFunction = function (
  ctx,
  _logger,
  nk,
  payload
): string {
  if (!ctx.userId) {
    throw new Error("authentication required");
  }

  let expectedMatchId = "";
  if (payload) {
    try {
      const parsed = JSON.parse(payload);
      if (parsed && typeof parsed.match_id === "string") {
        expectedMatchId = parsed.match_id;
      }
    } catch (_error) {
      throw new Error("invalid payload");
    }
  }

  const record = readActiveOnlineMatch(nk, ctx.userId);
  if (!record) {
    return JSON.stringify({
      cleared: false
    });
  }

  if (expectedMatchId && record.value.match_id !== expectedMatchId) {
    throw new Error("active match changed");
  }
  if (record.value.state !== ACTIVE_ONLINE_MATCH_STATE_RESULT_PENDING) {
    throw new Error("active match result is not pending");
  }

  deleteActiveOnlineMatch(nk, ctx.userId, record.version);
  return JSON.stringify({
    cleared: true,
    match_id: record.value.match_id
  });
};
