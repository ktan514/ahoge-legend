const PLAYER_SEASON_RANK_COLLECTION = "player_season_rank";
const RANKED_MATCH_SETTLEMENT_COLLECTION = "ranked_match_settlement";
const SYSTEM_USER_ID = "00000000-0000-0000-0000-000000000000";
const ELO_INITIAL_RATING = 1500;
const ELO_K_FACTOR = 32;
const JST_OFFSET_MILLISECONDS = 9 * 60 * 60 * 1000;
const PLAYER_RATING_LEADERBOARD_PREFIX = "player_rating_";
const PLAYER_RANKING_MAX_LIMIT = 100;

interface PlayerSeasonRankValue {
  season_id: string;
  rating: number;
  wins: number;
  losses: number;
}

interface PlayerSeasonRankRecord {
  value: PlayerSeasonRankValue;
  version: string;
  exists: boolean;
}

interface EloUpdateResult {
  winnerRating: number;
  loserRating: number;
  winnerExpected: number;
  loserExpected: number;
}

function currentSeasonIdJst(unixMilliseconds: number): string {
  const shifted = new Date(unixMilliseconds + JST_OFFSET_MILLISECONDS);
  const year = shifted.getUTCFullYear();
  const month = shifted.getUTCMonth() + 1;
  const monthText = month < 10 ? "0" + month : String(month);
  return String(year) + "-" + monthText;
}

function eloExpectedScore(selfRating: number, opponentRating: number): number {
  return 1 / (1 + Math.pow(10, (opponentRating - selfRating) / 400));
}

function calculateEloUpdate(
  winnerRating: number,
  loserRating: number
): EloUpdateResult {
  const winnerExpected = eloExpectedScore(winnerRating, loserRating);
  const loserExpected = eloExpectedScore(loserRating, winnerRating);

  return {
    winnerRating: Math.round(
      winnerRating + ELO_K_FACTOR * (1 - winnerExpected)
    ),
    loserRating: Math.round(
      loserRating + ELO_K_FACTOR * (0 - loserExpected)
    ),
    winnerExpected: winnerExpected,
    loserExpected: loserExpected
  };
}

function defaultPlayerSeasonRank(seasonId: string): PlayerSeasonRankValue {
  return {
    season_id: seasonId,
    rating: ELO_INITIAL_RATING,
    wins: 0,
    losses: 0
  };
}

function readPlayerSeasonRank(
  nk: nkruntime.Nakama,
  userId: string,
  seasonId: string
): PlayerSeasonRankRecord {
  const objects = nk.storageRead([
    {
      collection: PLAYER_SEASON_RANK_COLLECTION,
      key: seasonId,
      userId: userId
    }
  ]);

  if (!objects || objects.length === 0) {
    return {
      value: defaultPlayerSeasonRank(seasonId),
      version: "*",
      exists: false
    };
  }

  const object = objects[0];
  const rawValue = object.value as any;
  return {
    value: {
      season_id: String(rawValue.season_id || seasonId),
      rating: Number(rawValue.rating === undefined ? ELO_INITIAL_RATING : rawValue.rating),
      wins: Number(rawValue.wins || 0),
      losses: Number(rawValue.losses || 0)
    },
    version: object.version,
    exists: true
  };
}

function rankTierForRating(rating: number): string {
  if (rating >= 2000) return "MASTER";
  if (rating >= 1800) return "DIAMOND";
  if (rating >= 1600) return "PLATINUM";
  if (rating >= 1400) return "GOLD";
  if (rating >= 1200) return "SILVER";
  return "BRONZE";
}

function playerRatingLeaderboardId(seasonId: string): string {
  return PLAYER_RATING_LEADERBOARD_PREFIX + seasonId;
}

function ensurePlayerRatingLeaderboard(
  nk: nkruntime.Nakama,
  seasonId: string
): string {
  const id = playerRatingLeaderboardId(seasonId);
  nk.leaderboardCreate(
    id,
    true,
    nkruntime.SortOrder.DESCENDING,
    nkruntime.Operator.SET,
    "",
    {
      season_id: seasonId,
      ranking_type: "PLAYER"
    },
    true
  );
  return id;
}

function playerUsername(
  nk: nkruntime.Nakama,
  userId: string
): string {
  try {
    const account = nk.accountGetId(userId);
    if (account && account.user && account.user.username) {
      return String(account.user.username);
    }
  } catch (_error) {
    // Ranking自体の更新をusername取得失敗で止めない。
  }
  return "";
}

function syncPlayerRankingRecord(
  nk: nkruntime.Nakama,
  userId: string,
  seasonId: string
): void {
  const record = readPlayerSeasonRank(nk, userId, seasonId);
  const leaderboardId = ensurePlayerRatingLeaderboard(nk, seasonId);
  nk.leaderboardRecordWrite(
    leaderboardId,
    userId,
    playerUsername(nk, userId),
    record.value.rating,
    0,
    {
      season_id: seasonId,
      wins: record.value.wins,
      losses: record.value.losses,
      rank_tier: rankTierForRating(record.value.rating)
    }
  );
}

function syncRankedMatchLeaderboardProjection(
  nk: nkruntime.Nakama,
  winnerUserId: string,
  loserUserId: string,
  seasonId: string
): boolean {
  try {
    syncPlayerRankingRecord(nk, winnerUserId, seasonId);
    syncPlayerRankingRecord(nk, loserUserId, seasonId);
    return true;
  } catch (_error) {
    return false;
  }
}

function rankedMatchSettlementExists(
  nk: nkruntime.Nakama,
  matchId: string
): boolean {
  const objects = nk.storageRead([
    {
      collection: RANKED_MATCH_SETTLEMENT_COLLECTION,
      key: matchId,
      userId: SYSTEM_USER_ID
    }
  ]);
  return !!objects && objects.length > 0;
}

function shouldUpdateRatingForFinishCause(finishCause: string): boolean {
  return (
    finishCause === MATCH_FINISH_CAUSE_BO3 ||
    finishCause === MATCH_FINISH_CAUSE_DISCONNECT_TIMEOUT
  );
}

function settleRankedMatchRating(
  nk: nkruntime.Nakama,
  logger: nkruntime.Logger,
  matchId: string,
  matchMode: string,
  winnerUserId: string,
  loserUserId: string,
  characterIdByUser: {[key: string]: string},
  finishCause: string,
  unixMilliseconds: number
): boolean {
  if (matchMode !== "ranked") {
    return true;
  }
  if (!shouldUpdateRatingForFinishCause(finishCause)) {
    return true;
  }
  if (!matchId || !winnerUserId || !loserUserId || winnerUserId === loserUserId) {
    logger.error("ahoge rating settlement rejected invalid match result.");
    return false;
  }

  const seasonId = currentSeasonIdJst(unixMilliseconds);

  const winnerCharacterId = String(characterIdByUser[winnerUserId] || "");
  const loserCharacterId = String(characterIdByUser[loserUserId] || "");
  if (!winnerCharacterId || !loserCharacterId) {
    logger.error("ahoge ranking settlement rejected missing character IDs.");
    return false;
  }

  if (rankedMatchSettlementExists(nk, matchId)) {
    return (
      syncRankedMatchLeaderboardProjection(
        nk,
        winnerUserId,
        loserUserId,
        seasonId
      ) &&
      syncAhogeLegendProjection(
        nk,
        winnerCharacterId,
        loserCharacterId,
        seasonId
      )
    );
  }
  const winnerRecord = readPlayerSeasonRank(nk, winnerUserId, seasonId);
  const loserRecord = readPlayerSeasonRank(nk, loserUserId, seasonId);
  const elo = calculateEloUpdate(
    winnerRecord.value.rating,
    loserRecord.value.rating
  );

  const winnerValue: PlayerSeasonRankValue = {
    season_id: seasonId,
    rating: elo.winnerRating,
    wins: winnerRecord.value.wins + 1,
    losses: winnerRecord.value.losses
  };
  const loserValue: PlayerSeasonRankValue = {
    season_id: seasonId,
    rating: elo.loserRating,
    wins: loserRecord.value.wins,
    losses: loserRecord.value.losses + 1
  };

  const ahogeWrites = buildAhogeSeasonRankWrites(
    nk,
    winnerCharacterId,
    loserCharacterId,
    seasonId
  );

  const writes: nkruntime.StorageWriteRequest[] = [
    {
      collection: PLAYER_SEASON_RANK_COLLECTION,
      key: seasonId,
      userId: winnerUserId,
      value: winnerValue,
      version: winnerRecord.version,
      permissionRead: 1,
      permissionWrite: 0
    },
    {
      collection: PLAYER_SEASON_RANK_COLLECTION,
      key: seasonId,
      userId: loserUserId,
      value: loserValue,
      version: loserRecord.version,
      permissionRead: 1,
      permissionWrite: 0
    },
    ...ahogeWrites,
    {
      collection: RANKED_MATCH_SETTLEMENT_COLLECTION,
      key: matchId,
      userId: SYSTEM_USER_ID,
      value: {
        match_id: matchId,
        season_id: seasonId,
        winner_user_id: winnerUserId,
        loser_user_id: loserUserId,
        winner_character_id: winnerCharacterId,
        loser_character_id: loserCharacterId,
        finish_cause: finishCause,
        settled_at_unix_ms: unixMilliseconds
      },
      version: "*",
      permissionRead: 0,
      permissionWrite: 0
    }
  ];

  try {
    nk.storageWrite(writes);

    if (!syncRankedMatchLeaderboardProjection(
      nk,
      winnerUserId,
      loserUserId,
      seasonId
    )) {
      logger.warn(
        "ahoge player ranking projection will retry. match_id=%s season=%s",
        matchId,
        seasonId
      );
      return false;
    }

    if (!syncAhogeLegendProjection(
      nk,
      winnerCharacterId,
      loserCharacterId,
      seasonId
    )) {
      logger.warn(
        "ahoge legend ranking projection will retry. match_id=%s season=%s",
        matchId,
        seasonId
      );
      return false;
    }

    logger.info(
      "ahoge ranked rating settled. match_id=%s season=%s winner=%s loser=%s winner_rating=%d loser_rating=%d",
      matchId,
      seasonId,
      winnerUserId,
      loserUserId,
      elo.winnerRating,
      elo.loserRating
    );
    return true;
  } catch (error) {
    // 同一matchの並行settlementで他方が先に成功した場合は完了扱い。
    if (rankedMatchSettlementExists(nk, matchId)) {
      return (
        syncRankedMatchLeaderboardProjection(
          nk,
          winnerUserId,
          loserUserId,
          seasonId
        ) &&
        syncAhogeLegendProjection(
          nk,
          winnerCharacterId,
          loserCharacterId,
          seasonId
        )
      );
    }
    logger.warn(
      "ahoge ranked rating settlement will retry. match_id=%s error=%s",
      matchId,
      String(error)
    );
    return false;
  }
}

const currentRatingRpc: nkruntime.RpcFunction = function (
  ctx,
  _logger,
  nk,
  _payload
): string {
  if (!ctx.userId) {
    throw new Error("authentication required");
  }

  const seasonId = currentSeasonIdJst(Date.now());
  const record = readPlayerSeasonRank(nk, ctx.userId, seasonId);
  return JSON.stringify(record.value);
};


const playerRankingRpc: nkruntime.RpcFunction = function (
  ctx,
  _logger,
  nk,
  payload
): string {
  if (!ctx.userId) {
    throw new Error("authentication required");
  }

  let requestedLimit = 20;
  if (payload) {
    try {
      const parsed = JSON.parse(payload);
      if (parsed && typeof parsed.limit === "number") {
        requestedLimit = Math.floor(parsed.limit);
      }
    } catch (_error) {
      throw new Error("invalid payload");
    }
  }
  const limit = Math.max(1, Math.min(PLAYER_RANKING_MAX_LIMIT, requestedLimit));

  const seasonId = currentSeasonIdJst(Date.now());
  const leaderboardId = ensurePlayerRatingLeaderboard(nk, seasonId);
  const result = nk.leaderboardRecordsList(
    leaderboardId,
    [],
    limit,
    "",
    0
  );

  const rawRecords = result.records || [];
  const ownerIds = rawRecords.map(function (record): string {
    return String(record.ownerId);
  });

  const storageObjects = ownerIds.length > 0
    ? nk.storageRead(ownerIds.map(function (userId): nkruntime.StorageReadRequest {
        return {
          collection: PLAYER_SEASON_RANK_COLLECTION,
          key: seasonId,
          userId: userId
        };
      }))
    : [];
  const rankValueByUser: {[key: string]: PlayerSeasonRankValue} = {};
  storageObjects.forEach(function (object): void {
    const raw = object.value as any;
    rankValueByUser[object.userId] = {
      season_id: String(raw.season_id || seasonId),
      rating: Number(raw.rating === undefined ? ELO_INITIAL_RATING : raw.rating),
      wins: Number(raw.wins || 0),
      losses: Number(raw.losses || 0)
    };
  });

  let previousRating: number | null = null;
  let previousDisplayRank = 0;
  const records = rawRecords.map(function (record, index): any {
    const userId = String(record.ownerId);
    const rating = Number(record.score);
    let displayRank = index + 1;
    if (previousRating !== null && rating === previousRating) {
      displayRank = previousDisplayRank;
    }
    previousRating = rating;
    previousDisplayRank = displayRank;

    const value = rankValueByUser[userId] || defaultPlayerSeasonRank(seasonId);
    return {
      display_rank: displayRank,
      player_id: userId,
      player_name: String(record.username || ""),
      rating: rating,
      rank_tier: rankTierForRating(rating),
      wins: value.wins,
      losses: value.losses
    };
  });

  return JSON.stringify({
    season_id: seasonId,
    records: records,
    rank_count: result.rankCount || rawRecords.length
  });
};
