const PLAYER_SEASON_RANK_COLLECTION = "player_season_rank";
const RANKED_MATCH_SETTLEMENT_COLLECTION = "ranked_match_settlement";
const SYSTEM_USER_ID = "00000000-0000-0000-0000-000000000000";
const ELO_INITIAL_RATING = 1500;
const ELO_K_FACTOR = 32;
const PLAYER_RATING_LEADERBOARD_PREFIX = "player_rating_";
const PLAYER_RANKING_MAX_LIMIT = 100;

interface PlayerSeasonRankValue {
  season_id: string;
  rating: number;
  wins: number;
  losses: number;
  draws: number;
}

interface PlayerSeasonRankRecord {
  value: PlayerSeasonRankValue;
  version: string;
  exists: boolean;
}

interface EloOutcomeResult {
  firstExpected: number;
  secondExpected: number;
  firstDelta: number;
  secondDelta: number;
}

interface RankedMatchSettlementRecord {
  value: any;
  version: string;
}

function eloExpectedScore(selfRating: number, opponentRating: number): number {
  return 1 / (1 + Math.pow(10, (opponentRating - selfRating) / 400));
}

function calculateEloOutcome(
  firstRating: number,
  secondRating: number,
  firstActualScore: number
): EloOutcomeResult {
  if (
    firstActualScore !== 0 &&
    firstActualScore !== 0.5 &&
    firstActualScore !== 1
  ) {
    throw new Error("invalid Elo actual score");
  }
  const firstExpected = eloExpectedScore(firstRating, secondRating);
  const secondExpected = eloExpectedScore(secondRating, firstRating);
  const firstDelta = roundSymmetricRatingDelta(
    ELO_K_FACTOR * (firstActualScore - firstExpected)
  );
  return {
    firstExpected: firstExpected,
    secondExpected: secondExpected,
    firstDelta: firstDelta,
    secondDelta: -firstDelta
  };
}

function defaultPlayerSeasonRank(seasonId: string): PlayerSeasonRankValue {
  return {
    season_id: seasonId,
    rating: ELO_INITIAL_RATING,
    wins: 0,
    losses: 0,
    draws: 0
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
      rating: Number(
        rawValue.rating === undefined ? ELO_INITIAL_RATING : rawValue.rating
      ),
      wins: Number(rawValue.wins || 0),
      losses: Number(rawValue.losses || 0),
      draws: Number(rawValue.draws || 0)
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
      draws: record.value.draws,
      rank_tier: rankTierForRating(record.value.rating)
    }
  );
}

function syncRankedMatchLeaderboardProjection(
  nk: nkruntime.Nakama,
  userIds: string[],
  seasonId: string
): boolean {
  try {
    userIds.forEach(function (userId): void {
      syncPlayerRankingRecord(nk, userId, seasonId);
    });
    return true;
  } catch (_error) {
    return false;
  }
}

function readRankedMatchSettlement(
  nk: nkruntime.Nakama,
  matchId: string
): RankedMatchSettlementRecord | null {
  const objects = nk.storageRead([
    {
      collection: RANKED_MATCH_SETTLEMENT_COLLECTION,
      key: matchId,
      userId: SYSTEM_USER_ID
    }
  ]);
  if (!objects || objects.length === 0) {
    return null;
  }
  return {
    value: objects[0].value as any,
    version: objects[0].version
  };
}

function shouldUpdateRatingForFinishCause(finishCause: string): boolean {
  return (
    finishCause === MATCH_FINISH_CAUSE_BO3 ||
    finishCause === MATCH_FINISH_CAUSE_BO3_DRAW
  );
}

function settleRankedMatchRating(
  nk: nkruntime.Nakama,
  logger: nkruntime.Logger,
  matchId: string,
  matchMode: string,
  participantUserIds: string[],
  matchWinnerUserId: string,
  characterIdByUser: {[key: string]: string},
  ratingSnapshotSeasonId: string,
  playerRatingSnapshotByUser: {[key: string]: number},
  ahogeRatingSnapshotByCharacter: {[key: string]: number},
  ahogeMatchCountSnapshotByCharacter: {[key: string]: number},
  acceptedCombatInputCountByUser: {[key: string]: number},
  finishCause: string,
  matchStartedAtUnixMilliseconds: number,
  matchFinishedAtUnixMilliseconds: number
): boolean {
  if (matchMode !== "ranked") {
    return true;
  }
  if (!shouldUpdateRatingForFinishCause(finishCause)) {
    return true;
  }
  if (!matchId || participantUserIds.length !== 2) {
    logger.error("ranked rating settlement rejected invalid participants.");
    return false;
  }

  const firstUserId = String(participantUserIds[0] || "");
  const secondUserId = String(participantUserIds[1] || "");
  if (!firstUserId || !secondUserId || firstUserId === secondUserId) {
    logger.error("ranked rating settlement rejected invalid user IDs.");
    return false;
  }

  const isDraw = finishCause === MATCH_FINISH_CAUSE_BO3_DRAW;
  if (
    !isDraw &&
    matchWinnerUserId !== firstUserId &&
    matchWinnerUserId !== secondUserId
  ) {
    logger.error("ranked rating settlement rejected invalid winner.");
    return false;
  }

  const firstCharacterId = String(characterIdByUser[firstUserId] || "");
  const secondCharacterId = String(characterIdByUser[secondUserId] || "");
  if (!firstCharacterId || !secondCharacterId) {
    logger.error("ahoge ranking settlement rejected missing character IDs.");
    return false;
  }

  const existingSettlement = readRankedMatchSettlement(nk, matchId);
  if (existingSettlement) {
    const value = existingSettlement.value;
    const existingSeasonId = String(value.season_id || "");
    const existingParticipants = value.participant_user_ids;
    const existingCharacters = value.character_id_by_user;
    if (
      !existingSeasonId ||
      !Array.isArray(existingParticipants) ||
      !existingCharacters ||
      typeof existingCharacters !== "object"
    ) {
      logger.error("ranked settlement exists with invalid projection data. match_id=%s", matchId);
      return false;
    }
    const projectionUsers = existingParticipants.map(function (userId: any): string {
      return String(userId);
    });
    const projectionCharacters = projectionUsers.map(function (userId): string {
      return String((existingCharacters as any)[userId] || "");
    });
    return (
      syncRankedMatchLeaderboardProjection(
        nk,
        projectionUsers,
        existingSeasonId
      ) &&
      syncAhogeLegendProjection(
        nk,
        projectionCharacters,
        existingSeasonId
      )
    );
  }

  const seasonId = resolveRankedSettlementSeasonId(
    matchStartedAtUnixMilliseconds,
    matchFinishedAtUnixMilliseconds
  );
  ensureSeasonMetadata(nk, seasonId);

  const snapshotSeasonId =
    ratingSnapshotSeasonId ||
    currentSeasonIdJst(matchStartedAtUnixMilliseconds);
  const firstSnapshotPlayerRating =
    playerRatingSnapshotByUser[firstUserId] === undefined
      ? readPlayerSeasonRank(nk, firstUserId, snapshotSeasonId).value.rating
      : playerRatingSnapshotByUser[firstUserId];
  const secondSnapshotPlayerRating =
    playerRatingSnapshotByUser[secondUserId] === undefined
      ? readPlayerSeasonRank(nk, secondUserId, snapshotSeasonId).value.rating
      : playerRatingSnapshotByUser[secondUserId];
  const firstSnapshotAhogeRating =
    ahogeRatingSnapshotByCharacter[firstCharacterId] === undefined
      ? readAhogeSeasonRank(nk, firstCharacterId, snapshotSeasonId).value.ahoge_rating
      : ahogeRatingSnapshotByCharacter[firstCharacterId];
  const secondSnapshotAhogeRating =
    ahogeRatingSnapshotByCharacter[secondCharacterId] === undefined
      ? readAhogeSeasonRank(nk, secondCharacterId, snapshotSeasonId).value.ahoge_rating
      : ahogeRatingSnapshotByCharacter[secondCharacterId];
  const firstSnapshotAhogeMatchCount =
    ahogeMatchCountSnapshotByCharacter[firstCharacterId] === undefined
      ? readAhogeSeasonRank(nk, firstCharacterId, snapshotSeasonId).value.total_ranked_matches
      : ahogeMatchCountSnapshotByCharacter[firstCharacterId];
  const secondSnapshotAhogeMatchCount =
    ahogeMatchCountSnapshotByCharacter[secondCharacterId] === undefined
      ? readAhogeSeasonRank(nk, secondCharacterId, snapshotSeasonId).value.total_ranked_matches
      : ahogeMatchCountSnapshotByCharacter[secondCharacterId];

  const firstActualScore = isDraw
    ? 0.5
    : matchWinnerUserId === firstUserId
      ? 1
      : 0;
  const elo = calculateEloOutcome(
    firstSnapshotPlayerRating,
    secondSnapshotPlayerRating,
    firstActualScore
  );

  const firstRecord = readPlayerSeasonRank(nk, firstUserId, seasonId);
  const secondRecord = readPlayerSeasonRank(nk, secondUserId, seasonId);
  const firstValue: PlayerSeasonRankValue = {
    season_id: seasonId,
    rating: firstRecord.value.rating + elo.firstDelta,
    wins:
      firstRecord.value.wins +
      (!isDraw && matchWinnerUserId === firstUserId ? 1 : 0),
    losses:
      firstRecord.value.losses +
      (!isDraw && matchWinnerUserId === secondUserId ? 1 : 0),
    draws: firstRecord.value.draws + (isDraw ? 1 : 0)
  };
  const secondValue: PlayerSeasonRankValue = {
    season_id: seasonId,
    rating: secondRecord.value.rating + elo.secondDelta,
    wins:
      secondRecord.value.wins +
      (!isDraw && matchWinnerUserId === secondUserId ? 1 : 0),
    losses:
      secondRecord.value.losses +
      (!isDraw && matchWinnerUserId === firstUserId ? 1 : 0),
    draws: secondRecord.value.draws + (isDraw ? 1 : 0)
  };

  const totalAcceptedCombatInputCount =
    Math.max(0, Number(acceptedCombatInputCountByUser[firstUserId] || 0)) +
    Math.max(0, Number(acceptedCombatInputCountByUser[secondUserId] || 0));
  const ahogeSettlement = buildAhogeSeasonRankSettlement(
    nk,
    firstUserId,
    secondUserId,
    firstCharacterId,
    secondCharacterId,
    seasonId,
    firstSnapshotPlayerRating,
    secondSnapshotPlayerRating,
    firstSnapshotAhogeRating,
    secondSnapshotAhogeRating,
    firstSnapshotAhogeMatchCount,
    secondSnapshotAhogeMatchCount,
    firstActualScore,
    totalAcceptedCombatInputCount
  );

  const winnerUserId = isDraw ? "" : matchWinnerUserId;
  const loserUserId = isDraw
    ? ""
    : matchWinnerUserId === firstUserId
      ? secondUserId
      : firstUserId;

  const writes: nkruntime.StorageWriteRequest[] = [
    {
      collection: PLAYER_SEASON_RANK_COLLECTION,
      key: seasonId,
      userId: firstUserId,
      value: firstValue,
      version: firstRecord.version,
      permissionRead: 1,
      permissionWrite: 0
    },
    {
      collection: PLAYER_SEASON_RANK_COLLECTION,
      key: seasonId,
      userId: secondUserId,
      value: secondValue,
      version: secondRecord.version,
      permissionRead: 1,
      permissionWrite: 0
    },
    ...ahogeSettlement.writes,
    {
      collection: RANKED_MATCH_SETTLEMENT_COLLECTION,
      key: matchId,
      userId: SYSTEM_USER_ID,
      value: {
        match_id: matchId,
        season_id: seasonId,
        rating_snapshot_season_id: snapshotSeasonId,
        outcome: isDraw ? "DRAW" : "WIN",
        participant_user_ids: [firstUserId, secondUserId],
        winner_user_id: winnerUserId,
        loser_user_id: loserUserId,
        character_id_by_user: characterIdByUser,
        finish_cause: finishCause,
        player_rating_calculation_snapshot_by_user: {
          [firstUserId]: firstSnapshotPlayerRating,
          [secondUserId]: secondSnapshotPlayerRating
        },
        player_rating_before_by_user: {
          [firstUserId]: firstRecord.value.rating,
          [secondUserId]: secondRecord.value.rating
        },
        player_rating_after_by_user: {
          [firstUserId]: firstValue.rating,
          [secondUserId]: secondValue.rating
        },
        player_rating_delta_by_user: {
          [firstUserId]: elo.firstDelta,
          [secondUserId]: elo.secondDelta
        },
        player_expected_by_user: {
          [firstUserId]: elo.firstExpected,
          [secondUserId]: elo.secondExpected
        },
        ahoge_rating_calculation_snapshot_by_character: {
          [firstCharacterId]: firstSnapshotAhogeRating,
          [secondCharacterId]: secondSnapshotAhogeRating
        },
        ahoge_rating_before_by_user: {
          [firstUserId]: ahogeSettlement.first_rating_before,
          [secondUserId]: ahogeSettlement.second_rating_before
        },
        ahoge_rating_after_by_user: {
          [firstUserId]: ahogeSettlement.first_rating_after,
          [secondUserId]: ahogeSettlement.second_rating_after
        },
        ahoge_rating_delta_by_user: {
          [firstUserId]: ahogeSettlement.first_delta,
          [secondUserId]: ahogeSettlement.second_delta
        },
        ahoge_raw_delta_by_user: {
          [firstUserId]: ahogeSettlement.raw_delta,
          [secondUserId]: -ahogeSettlement.raw_delta
        },
        ahoge_trusted_delta_by_user: {
          [firstUserId]: ahogeSettlement.trusted_delta,
          [secondUserId]: -ahogeSettlement.trusted_delta
        },
        ahoge_influence_used_before_by_user: {
          [firstUserId]: ahogeSettlement.first_influence_used_before,
          [secondUserId]: ahogeSettlement.second_influence_used_before
        },
        ahoge_influence_used_after_by_user: {
          [firstUserId]: ahogeSettlement.first_influence_used_after,
          [secondUserId]: ahogeSettlement.second_influence_used_after
        },
        ahoge_expected_by_user: {
          [firstUserId]: ahogeSettlement.first_expected,
          [secondUserId]: ahogeSettlement.second_expected
        },
        ahoge_mirror_match: ahogeSettlement.mirror_match,
        ahoge_trust_multiplier: ahogeSettlement.trust_multiplier,
        ahoge_pair_match_count_before:
          ahogeSettlement.pair_match_count_before,
        ahoge_total_activity_count: ahogeSettlement.total_activity_count,
        ahoge_weight: ahogeSettlement.weight,
        ahoge_k: ahogeSettlement.k_factor,
        match_started_at_unix_ms: matchStartedAtUnixMilliseconds,
        match_finished_at_unix_ms: matchFinishedAtUnixMilliseconds,
        settled_at_unix_ms: Date.now()
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
      [firstUserId, secondUserId],
      seasonId
    )) {
      logger.warn(
        "player ranking projection will retry. match_id=%s season=%s",
        matchId,
        seasonId
      );
      return false;
    }

    if (!syncAhogeLegendProjection(
      nk,
      [firstCharacterId, secondCharacterId],
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
      "ranked rating settled. match_id=%s season=%s outcome=%s p1_rating=%d p2_rating=%d p1_ahoge=%d p2_ahoge=%d",
      matchId,
      seasonId,
      isDraw ? "DRAW" : "WIN",
      firstValue.rating,
      secondValue.rating,
      ahogeSettlement.first_rating_after,
      ahogeSettlement.second_rating_after
    );
    return true;
  } catch (error) {
    const concurrentSettlement = readRankedMatchSettlement(nk, matchId);
    if (concurrentSettlement) {
      const value = concurrentSettlement.value;
      const settledSeasonId = String(value.season_id || "");
      const settledParticipants = value.participant_user_ids;
      const settledCharacters = value.character_id_by_user;
      if (
        settledSeasonId &&
        Array.isArray(settledParticipants) &&
        settledCharacters &&
        typeof settledCharacters === "object"
      ) {
        const projectionUsers = settledParticipants.map(function (userId: any): string {
          return String(userId);
        });
        const projectionCharacters = projectionUsers.map(function (userId): string {
          return String((settledCharacters as any)[userId] || "");
        });
        return (
          syncRankedMatchLeaderboardProjection(
            nk,
            projectionUsers,
            settledSeasonId
          ) &&
          syncAhogeLegendProjection(
            nk,
            projectionCharacters,
            settledSeasonId
          )
        );
      }
    }
    logger.warn(
      "ranked rating settlement will retry. match_id=%s error=%s",
      matchId,
      String(error)
    );
    return false;
  }
}

const rankedMatchSettlementRpc: nkruntime.RpcFunction = function (
  ctx,
  _logger,
  nk,
  payload
): string {
  if (!ctx.userId) {
    throw new Error("authentication required");
  }

  let matchId = "";
  if (payload) {
    try {
      const parsed = JSON.parse(payload);
      matchId = String(parsed.match_id || "");
    } catch (_error) {
      throw new Error("invalid payload");
    }
  }
  if (!matchId) {
    throw new Error("match_id required");
  }

  const record = readRankedMatchSettlement(nk, matchId);
  if (!record) {
    return JSON.stringify({found: false});
  }

  const value = record.value;
  const userId = String(ctx.userId);
  const participants = Array.isArray(value.participant_user_ids)
    ? value.participant_user_ids.map(function (id: any): string {
        return String(id);
      })
    : [
        String(value.winner_user_id || ""),
        String(value.loser_user_id || "")
      ];
  if (participants.indexOf(userId) < 0) {
    throw new Error("settlement participant required");
  }

  const characterMap =
    value.character_id_by_user &&
    typeof value.character_id_by_user === "object"
      ? value.character_id_by_user
      : {};
  const playerBefore = value.player_rating_before_by_user || {};
  const playerAfter = value.player_rating_after_by_user || {};
  const playerDelta = value.player_rating_delta_by_user || {};
  const playerExpected = value.player_expected_by_user || {};
  const ahogeBefore = value.ahoge_rating_before_by_user || {};
  const ahogeAfter = value.ahoge_rating_after_by_user || {};
  const ahogeDelta = value.ahoge_rating_delta_by_user || {};
  const ahogeRawDelta = value.ahoge_raw_delta_by_user || {};
  const ahogeTrustedDelta = value.ahoge_trusted_delta_by_user || {};
  const ahogeInfluenceBefore =
    value.ahoge_influence_used_before_by_user || {};
  const ahogeInfluenceAfter =
    value.ahoge_influence_used_after_by_user || {};
  const ahogeExpected = value.ahoge_expected_by_user || {};

  const playerRatingAvailable =
    playerBefore[userId] !== undefined && playerAfter[userId] !== undefined;
  const ahogeRatingAvailable =
    ahogeBefore[userId] !== undefined && ahogeAfter[userId] !== undefined;
  const isDraw = String(value.outcome || "") === "DRAW";
  const winnerUserId = String(value.winner_user_id || "");

  return JSON.stringify({
    found: true,
    player_rating_available: playerRatingAvailable,
    ahoge_rating_available: ahogeRatingAvailable,
    match_id: matchId,
    season_id: String(value.season_id || ""),
    rating_snapshot_season_id: String(value.rating_snapshot_season_id || ""),
    user_id: userId,
    character_id: String((characterMap as any)[userId] || ""),
    is_winner: !isDraw && winnerUserId === userId,
    is_draw: isDraw,
    player_rating_before: Number(playerBefore[userId] || 0),
    player_rating_after: Number(playerAfter[userId] || 0),
    player_rating_delta: Number(playerDelta[userId] || 0),
    player_expected: Number(playerExpected[userId] || 0),
    ahoge_rating_before: Number(
      ahogeBefore[userId] === undefined
        ? AHOGE_BASE_RATING
        : ahogeBefore[userId]
    ),
    ahoge_rating_after: Number(
      ahogeAfter[userId] === undefined
        ? AHOGE_BASE_RATING
        : ahogeAfter[userId]
    ),
    ahoge_rating_delta: Number(ahogeDelta[userId] || 0),
    ahoge_raw_delta: Number(ahogeRawDelta[userId] || 0),
    ahoge_trusted_delta: Number(ahogeTrustedDelta[userId] || 0),
    ahoge_influence_used_before: Number(
      ahogeInfluenceBefore[userId] || 0
    ),
    ahoge_influence_used_after: Number(
      ahogeInfluenceAfter[userId] || 0
    ),
    ahoge_expected: Number(ahogeExpected[userId] || 0),
    ahoge_mirror_match: Boolean(value.ahoge_mirror_match),
    ahoge_trust_multiplier: Number(value.ahoge_trust_multiplier || 0),
    ahoge_pair_match_count_before: Number(
      value.ahoge_pair_match_count_before || 0
    ),
    ahoge_total_activity_count: Number(
      value.ahoge_total_activity_count || 0
    ),
    ahoge_weight: Number(value.ahoge_weight || 0),
    ahoge_k: Number(value.ahoge_k || 0)
  });
};

const currentRatingRpc: nkruntime.RpcFunction = function (
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
      requestedSeasonId = parseOptionalSeasonId(parsed);
    } catch (_error) {
      throw new Error("invalid payload");
    }
  }

  const now = Date.now();
  const seasonId = resolveRequestedSeasonId(requestedSeasonId, now);
  ensureSeasonMetadata(nk, seasonId);
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
  let requestedSeasonId = "";
  if (payload) {
    try {
      const parsed = JSON.parse(payload);
      if (parsed && typeof parsed.limit === "number") {
        requestedLimit = Math.floor(parsed.limit);
      }
      requestedSeasonId = parseOptionalSeasonId(parsed);
    } catch (_error) {
      throw new Error("invalid payload");
    }
  }
  const limit = Math.max(1, Math.min(PLAYER_RANKING_MAX_LIMIT, requestedLimit));

  const now = Date.now();
  const seasonId = resolveRequestedSeasonId(requestedSeasonId, now);
  ensureSeasonMetadata(nk, seasonId);
  const visibility = seasonRankingVisibility(seasonId, now);
  if (!visibility.ranking_public) {
    return JSON.stringify({
      season_id: seasonId,
      records: [],
      rank_count: 0,
      ranking_public: false,
      ranking_hidden_until_unix_ms:
        visibility.ranking_hidden_until_unix_ms
    });
  }

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
      rating: Number(
        raw.rating === undefined ? ELO_INITIAL_RATING : raw.rating
      ),
      wins: Number(raw.wins || 0),
      losses: Number(raw.losses || 0),
      draws: Number(raw.draws || 0)
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
      losses: value.losses,
      draws: value.draws
    };
  });

  return JSON.stringify({
    season_id: seasonId,
    records: records,
    rank_count: result.rankCount || rawRecords.length,
    ranking_public: true,
    ranking_hidden_until_unix_ms: 0
  });
};
