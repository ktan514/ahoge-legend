const RANKING_SEASON_COLLECTION = "ranking_season";
const SEASON_SYSTEM_USER_ID = "00000000-0000-0000-0000-000000000000";
const SEASON_JST_OFFSET_MILLISECONDS = 9 * 60 * 60 * 1000;
const SEASON_RANKING_HIDE_BEFORE_END_MILLISECONDS = 60 * 60 * 1000;
const SEASON_FINALIZATION_GRACE_MILLISECONDS = 10 * 60 * 1000;

interface RankingSeasonMetadata {
  season_id: string;
  starts_at_unix_ms: number;
  ends_at_unix_ms: number;
}

interface RankingSeasonVisibility {
  ranking_public: boolean;
  ranking_hidden_until_unix_ms: number;
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

function parseOptionalSeasonId(parsed: any): string {
  if (!parsed || parsed.season_id === undefined) {
    return "";
  }
  if (
    typeof parsed.season_id !== "string" ||
    !validSeasonId(parsed.season_id)
  ) {
    throw new Error("invalid season_id");
  }
  return parsed.season_id;
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
  referenceUnixMilliseconds: number
): string {
  return seasonId === currentSeasonIdJst(referenceUnixMilliseconds)
    ? "CURRENT"
    : "HISTORICAL";
}

function seasonRankingVisibility(
  seasonId: string,
  referenceUnixMilliseconds: number
): RankingSeasonVisibility {
  const bounds = seasonBoundsJst(seasonId);
  const hiddenFrom =
    bounds.ends_at_unix_ms - SEASON_RANKING_HIDE_BEFORE_END_MILLISECONDS;
  const hiddenUntil =
    bounds.ends_at_unix_ms + SEASON_FINALIZATION_GRACE_MILLISECONDS;
  const hidden =
    referenceUnixMilliseconds >= hiddenFrom &&
    referenceUnixMilliseconds < hiddenUntil;

  return {
    ranking_public: !hidden,
    ranking_hidden_until_unix_ms: hidden ? hiddenUntil : 0
  };
}

function resolveRankedSettlementSeasonId(
  matchStartedAtUnixMilliseconds: number,
  matchFinishedAtUnixMilliseconds: number
): string {
  if (
    !isFinite(matchStartedAtUnixMilliseconds) ||
    !isFinite(matchFinishedAtUnixMilliseconds) ||
    matchStartedAtUnixMilliseconds < 0 ||
    matchFinishedAtUnixMilliseconds < matchStartedAtUnixMilliseconds
  ) {
    throw new Error("invalid ranked settlement time");
  }

  const startSeasonId = currentSeasonIdJst(matchStartedAtUnixMilliseconds);
  const startBounds = seasonBoundsJst(startSeasonId);
  const finalizationDeadline =
    startBounds.ends_at_unix_ms + SEASON_FINALIZATION_GRACE_MILLISECONDS;

  if (
    matchStartedAtUnixMilliseconds < startBounds.ends_at_unix_ms &&
    matchFinishedAtUnixMilliseconds <= finalizationDeadline
  ) {
    return startSeasonId;
  }

  return currentSeasonIdJst(matchFinishedAtUnixMilliseconds);
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
  let requestedAtUnixMilliseconds: number | null = null;
  if (payload) {
    try {
      const parsed = JSON.parse(payload);
      requestedSeasonId = parseOptionalSeasonId(parsed);
      if (parsed && parsed.at_unix_ms !== undefined) {
        const value = Number(parsed.at_unix_ms);
        if (!isFinite(value) || Math.floor(value) !== value || value < 0) {
          throw new Error("invalid at_unix_ms");
        }
        requestedAtUnixMilliseconds = value;
      }
    } catch (error) {
      if (String(error).indexOf("invalid at_unix_ms") >= 0) {
        throw error;
      }
      throw new Error("invalid payload");
    }
  }

  if (requestedSeasonId && requestedAtUnixMilliseconds !== null) {
    throw new Error("season_id and at_unix_ms are mutually exclusive");
  }

  const now = Date.now();
  if (
    requestedAtUnixMilliseconds !== null &&
    requestedAtUnixMilliseconds > now
  ) {
    throw new Error("future at_unix_ms is not allowed");
  }

  const referenceTime =
    requestedAtUnixMilliseconds !== null
      ? requestedAtUnixMilliseconds
      : now;
  const seasonId = requestedAtUnixMilliseconds !== null
    ? currentSeasonIdJst(requestedAtUnixMilliseconds)
    : resolveRequestedSeasonId(requestedSeasonId, now);
  const metadata = ensureSeasonMetadata(nk, seasonId);
  const visibility = seasonRankingVisibility(seasonId, referenceTime);

  return JSON.stringify({
    season_id: metadata.season_id,
    starts_at_unix_ms: metadata.starts_at_unix_ms,
    ends_at_unix_ms: metadata.ends_at_unix_ms,
    state: seasonState(seasonId, now),
    current_season_id: currentSeasonIdJst(now),
    ranking_public: visibility.ranking_public,
    ranking_hidden_until_unix_ms: visibility.ranking_hidden_until_unix_ms
  });
};
