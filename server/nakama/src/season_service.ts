const RANKING_SEASON_COLLECTION = "ranking_season";
const SEASON_SYSTEM_USER_ID = "00000000-0000-0000-0000-000000000000";
const SEASON_JST_OFFSET_MILLISECONDS = 9 * 60 * 60 * 1000;

interface RankingSeasonMetadata {
  season_id: string;
  starts_at_unix_ms: number;
  ends_at_unix_ms: number;
}

function currentSeasonIdJst(unixMilliseconds: number): string {
  const shifted = new Date(unixMilliseconds + SEASON_JST_OFFSET_MILLISECONDS);
  const year = shifted.getUTCFullYear();
  const month = shifted.getUTCMonth() + 1;
  const monthText = month < 10 ? "0" + month : String(month);
  return String(year) + "-" + monthText;
}

function validSeasonId(seasonId: string): boolean {
  return /^\d{4}-(0[1-9]|1[0-2])$/.test(seasonId);
}

function seasonBoundsJst(seasonId: string): RankingSeasonMetadata {
  if (!validSeasonId(seasonId)) {
    throw new Error("invalid season_id");
  }

  const parts = seasonId.split("-");
  const year = Number(parts[0]);
  const month = Number(parts[1]);
  const startsAt = Date.UTC(year, month - 1, 1, 0, 0, 0, 0)
    - SEASON_JST_OFFSET_MILLISECONDS;
  const endsAt = Date.UTC(year, month, 1, 0, 0, 0, 0)
    - SEASON_JST_OFFSET_MILLISECONDS;

  return {
    season_id: seasonId,
    starts_at_unix_ms: startsAt,
    ends_at_unix_ms: endsAt
  };
}

function seasonState(
  seasonId: string,
  nowUnixMilliseconds: number
): string {
  return seasonId === currentSeasonIdJst(nowUnixMilliseconds)
    ? "CURRENT"
    : "HISTORICAL";
}

function ensureSeasonMetadata(
  nk: nkruntime.Nakama,
  seasonId: string
): RankingSeasonMetadata {
  const objects = nk.storageRead([
    {
      collection: RANKING_SEASON_COLLECTION,
      key: seasonId,
      userId: SEASON_SYSTEM_USER_ID
    }
  ]);

  if (objects && objects.length > 0) {
    const raw = objects[0].value as any;
    return {
      season_id: String(raw.season_id || seasonId),
      starts_at_unix_ms: Number(raw.starts_at_unix_ms),
      ends_at_unix_ms: Number(raw.ends_at_unix_ms)
    };
  }

  const metadata = seasonBoundsJst(seasonId);
  try {
    nk.storageWrite([
      {
        collection: RANKING_SEASON_COLLECTION,
        key: seasonId,
        userId: SEASON_SYSTEM_USER_ID,
        value: metadata,
        version: "*",
        permissionRead: 0,
        permissionWrite: 0
      }
    ]);
    return metadata;
  } catch (_error) {
    const retryObjects = nk.storageRead([
      {
        collection: RANKING_SEASON_COLLECTION,
        key: seasonId,
        userId: SEASON_SYSTEM_USER_ID
      }
    ]);
    if (retryObjects && retryObjects.length > 0) {
      const raw = retryObjects[0].value as any;
      return {
        season_id: String(raw.season_id || seasonId),
        starts_at_unix_ms: Number(raw.starts_at_unix_ms),
        ends_at_unix_ms: Number(raw.ends_at_unix_ms)
      };
    }
    throw _error;
  }
}

function resolveRequestedSeasonId(
  requestedSeasonId: string,
  nowUnixMilliseconds: number
): string {
  const current = currentSeasonIdJst(nowUnixMilliseconds);
  if (!requestedSeasonId) {
    return current;
  }
  if (!validSeasonId(requestedSeasonId)) {
    throw new Error("invalid season_id");
  }
  if (requestedSeasonId > current) {
    throw new Error("future season_id is not allowed");
  }
  return requestedSeasonId;
}

const seasonMetadataRpc: nkruntime.RpcFunction = function (
  ctx,
  _logger,
  nk,
  payload
): string {
  if (!ctx.userId) {
    throw new Error("authentication required");
  }

  let requestedSeasonId = "";
  if (payload) {
    try {
      const parsed = JSON.parse(payload);
      if (parsed && parsed.season_id !== undefined) {
        requestedSeasonId = String(parsed.season_id || "");
      }
    } catch (_error) {
      throw new Error("invalid payload");
    }
  }

  const now = Date.now();
  const seasonId = resolveRequestedSeasonId(requestedSeasonId, now);
  const metadata = ensureSeasonMetadata(nk, seasonId);

  return JSON.stringify({
    season_id: metadata.season_id,
    starts_at_unix_ms: metadata.starts_at_unix_ms,
    ends_at_unix_ms: metadata.ends_at_unix_ms,
    state: seasonState(seasonId, now),
    current_season_id: currentSeasonIdJst(now)
  });
};
