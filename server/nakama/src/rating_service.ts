const PLAYER_SEASON_RANK_COLLECTION = "player_season_rank";
const RANKED_MATCH_SETTLEMENT_COLLECTION = "ranked_match_settlement";
const SYSTEM_USER_ID = "00000000-0000-0000-0000-000000000000";
const ELO_INITIAL_RATING = 1500;
const ELO_K_FACTOR = 32;
const JST_OFFSET_MILLISECONDS = 9 * 60 * 60 * 1000;

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

  if (rankedMatchSettlementExists(nk, matchId)) {
    return true;
  }

  const seasonId = currentSeasonIdJst(unixMilliseconds);
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
    {
      collection: RANKED_MATCH_SETTLEMENT_COLLECTION,
      key: matchId,
      userId: SYSTEM_USER_ID,
      value: {
        match_id: matchId,
        season_id: seasonId,
        winner_user_id: winnerUserId,
        loser_user_id: loserUserId,
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
      return true;
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
