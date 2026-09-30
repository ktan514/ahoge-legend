const AHOGE_SEASON_RANK_COLLECTION = "ahoge_season_rank";
const AHOGE_PLAYER_CHARACTER_INFLUENCE_COLLECTION = "ahoge_player_character_influence";
const AHOGE_OPPONENT_PAIR_COLLECTION = "ahoge_opponent_pair";
const AHOGE_LEGEND_LEADERBOARD_PREFIX = "ahoge_legend_";
const AHOGE_LEGEND_MAX_LIMIT = 100;
const AHOGE_STORAGE_SYSTEM_USER_ID = "00000000-0000-0000-0000-000000000000";

const CHARACTER_RANK_OWNER_IDS: {[key: string]: string} = {
  LONG_TEST: "10000000-0000-0000-0000-000000000001",
  SHORT_TEST: "10000000-0000-0000-0000-000000000002"
};

interface AhogeSeasonRankValue {
  season_id: string;
  character_id: string;
  ahoge_rating: number;
  total_match_wins: number;
  total_ranked_matches: number;
}

interface AhogeSeasonRankRecord {
  value: AhogeSeasonRankValue;
  version: string;
  exists: boolean;
}

interface AhogePlayerCharacterInfluenceValue {
  season_id: string;
  character_id: string;
  absolute_influence_used: number;
}

interface AhogePlayerCharacterInfluenceRecord {
  value: AhogePlayerCharacterInfluenceValue;
  version: string;
}

interface AhogeOpponentPairValue {
  season_id: string;
  first_user_id: string;
  second_user_id: string;
  ranked_match_count: number;
}

interface AhogeOpponentPairRecord {
  value: AhogeOpponentPairValue;
  version: string;
}

interface AhogeRatingSettlementResult {
  writes: nkruntime.StorageWriteRequest[];
  mirror_match: boolean;
  first_rating_before: number;
  first_rating_after: number;
  second_rating_before: number;
  second_rating_after: number;
  first_expected: number;
  second_expected: number;
  first_delta: number;
  second_delta: number;
  raw_delta: number;
  trusted_delta: number;
  trust_multiplier: number;
  pair_match_count_before: number;
  total_activity_count: number;
  first_influence_used_before: number;
  first_influence_used_after: number;
  second_influence_used_before: number;
  second_influence_used_after: number;
  weight: number;
  k_factor: number;
}

function characterRankingOwnerId(characterId: string): string {
  return CHARACTER_RANK_OWNER_IDS[characterId] || "";
}

function ahogeSeasonStorageKey(
  seasonId: string,
  characterId: string
): string {
  return seasonId + ":" + characterId;
}

function influenceStorageKey(
  seasonId: string,
  characterId: string
): string {
  return seasonId + ":" + characterId;
}

function pairStorageKey(
  seasonId: string,
  firstUserId: string,
  secondUserId: string
): string {
  const ids = [firstUserId, secondUserId].sort();
  return seasonId + ":" + ids[0] + ":" + ids[1];
}

function defaultAhogeSeasonRank(
  seasonId: string,
  characterId: string
): AhogeSeasonRankValue {
  return {
    season_id: seasonId,
    character_id: characterId,
    ahoge_rating: AHOGE_BASE_RATING,
    total_match_wins: 0,
    total_ranked_matches: 0
  };
}

function readAhogeSeasonRank(
  nk: nkruntime.Nakama,
  characterId: string,
  seasonId: string
): AhogeSeasonRankRecord {
  const ownerId = characterRankingOwnerId(characterId);
  if (!ownerId) {
    throw new Error("unsupported character ranking owner: " + characterId);
  }

  const objects = nk.storageRead([
    {
      collection: AHOGE_SEASON_RANK_COLLECTION,
      key: ahogeSeasonStorageKey(seasonId, characterId),
      userId: AHOGE_STORAGE_SYSTEM_USER_ID
    }
  ]);

  if (!objects || objects.length === 0) {
    return {
      value: defaultAhogeSeasonRank(seasonId, characterId),
      version: "*",
      exists: false
    };
  }

  const object = objects[0];
  const raw = object.value as any;
  return {
    value: {
      season_id: String(raw.season_id || seasonId),
      character_id: String(raw.character_id || characterId),
      ahoge_rating: Number(
        raw.ahoge_rating === undefined
          ? AHOGE_BASE_RATING
          : raw.ahoge_rating
      ),
      total_match_wins: Number(raw.total_match_wins || 0),
      total_ranked_matches: Number(raw.total_ranked_matches || 0)
    },
    version: object.version,
    exists: true
  };
}

function readAhogePlayerCharacterInfluence(
  nk: nkruntime.Nakama,
  userId: string,
  characterId: string,
  seasonId: string
): AhogePlayerCharacterInfluenceRecord {
  const objects = nk.storageRead([
    {
      collection: AHOGE_PLAYER_CHARACTER_INFLUENCE_COLLECTION,
      key: influenceStorageKey(seasonId, characterId),
      userId: userId
    }
  ]);
  if (!objects || objects.length === 0) {
    return {
      value: {
        season_id: seasonId,
        character_id: characterId,
        absolute_influence_used: 0
      },
      version: "*"
    };
  }
  const raw = objects[0].value as any;
  return {
    value: {
      season_id: String(raw.season_id || seasonId),
      character_id: String(raw.character_id || characterId),
      absolute_influence_used: Math.max(
        0,
        Number(raw.absolute_influence_used || 0)
      )
    },
    version: objects[0].version
  };
}

function readAhogeOpponentPair(
  nk: nkruntime.Nakama,
  firstUserId: string,
  secondUserId: string,
  seasonId: string
): AhogeOpponentPairRecord {
  const ids = [firstUserId, secondUserId].sort();
  const objects = nk.storageRead([
    {
      collection: AHOGE_OPPONENT_PAIR_COLLECTION,
      key: pairStorageKey(seasonId, firstUserId, secondUserId),
      userId: AHOGE_STORAGE_SYSTEM_USER_ID
    }
  ]);
  if (!objects || objects.length === 0) {
    return {
      value: {
        season_id: seasonId,
        first_user_id: ids[0],
        second_user_id: ids[1],
        ranked_match_count: 0
      },
      version: "*"
    };
  }
  const raw = objects[0].value as any;
  return {
    value: {
      season_id: String(raw.season_id || seasonId),
      first_user_id: String(raw.first_user_id || ids[0]),
      second_user_id: String(raw.second_user_id || ids[1]),
      ranked_match_count: Math.max(0, Number(raw.ranked_match_count || 0))
    },
    version: objects[0].version
  };
}

function ahogeEffectiveRating(
  playerRating: number,
  ahogeRating: number
): number {
  return (
    playerRating +
    AHOGE_RATING_WEIGHT * (ahogeRating - AHOGE_BASE_RATING)
  );
}

function ahogeExpectedScore(
  selfEffective: number,
  opponentEffective: number
): number {
  return 1 / (1 + Math.pow(10, (opponentEffective - selfEffective) / 400));
}

function clampAhogeDeltaByInfluenceBudget(
  delta: number,
  firstInfluenceUsed: number,
  secondInfluenceUsed: number
): number {
  const requestedMagnitude = Math.abs(delta);
  if (requestedMagnitude === 0) {
    return 0;
  }
  const firstRemaining = Math.max(
    0,
    AHOGE_PLAYER_CHARACTER_ABSOLUTE_INFLUENCE_CAP - firstInfluenceUsed
  );
  const secondRemaining = Math.max(
    0,
    AHOGE_PLAYER_CHARACTER_ABSOLUTE_INFLUENCE_CAP - secondInfluenceUsed
  );
  const allowedMagnitude = Math.min(
    requestedMagnitude,
    firstRemaining,
    secondRemaining
  );
  if (allowedMagnitude <= 0) {
    return 0;
  }
  return delta > 0 ? allowedMagnitude : -allowedMagnitude;
}

function buildAhogeSeasonRankSettlement(
  nk: nkruntime.Nakama,
  firstUserId: string,
  secondUserId: string,
  firstCharacterId: string,
  secondCharacterId: string,
  seasonId: string,
  firstPlayerRatingSnapshot: number,
  secondPlayerRatingSnapshot: number,
  firstAhogeRatingSnapshot: number,
  secondAhogeRatingSnapshot: number,
  firstAhogeMatchCountSnapshot: number,
  secondAhogeMatchCountSnapshot: number,
  firstActualScore: number,
  totalAcceptedCombatInputCount: number
): AhogeRatingSettlementResult {
  const firstOwnerId = characterRankingOwnerId(firstCharacterId);
  const secondOwnerId = characterRankingOwnerId(secondCharacterId);
  if (!firstOwnerId || !secondOwnerId) {
    throw new Error("unsupported character for AHOGE LEGEND ranking");
  }
  if (firstActualScore !== 0 && firstActualScore !== 0.5 && firstActualScore !== 1) {
    throw new Error("invalid AHOGE actual score");
  }

  const firstEffective = ahogeEffectiveRating(
    firstPlayerRatingSnapshot,
    firstAhogeRatingSnapshot
  );
  const secondEffective = ahogeEffectiveRating(
    secondPlayerRatingSnapshot,
    secondAhogeRatingSnapshot
  );
  const firstExpected = ahogeExpectedScore(firstEffective, secondEffective);
  const secondExpected = 1 - firstExpected;
  const kFactor = ahogeKForMatchCounts(
    firstAhogeMatchCountSnapshot,
    secondAhogeMatchCountSnapshot
  );

  const pairRecord = readAhogeOpponentPair(
    nk,
    firstUserId,
    secondUserId,
    seasonId
  );
  const pairWeight = ahogeSamePairWeight(
    pairRecord.value.ranked_match_count
  );
  const activityWeight =
    totalAcceptedCombatInputCount > 0 ? 1.0 : AHOGE_NO_ACTIVITY_WEIGHT;
  const trustMultiplier = pairWeight * activityWeight;
  const pairWrite: nkruntime.StorageWriteRequest = {
    collection: AHOGE_OPPONENT_PAIR_COLLECTION,
    key: pairStorageKey(seasonId, firstUserId, secondUserId),
    userId: AHOGE_STORAGE_SYSTEM_USER_ID,
    value: {
      season_id: seasonId,
      first_user_id: pairRecord.value.first_user_id,
      second_user_id: pairRecord.value.second_user_id,
      ranked_match_count: pairRecord.value.ranked_match_count + 1
    },
    version: pairRecord.version,
    permissionRead: 0,
    permissionWrite: 0
  };

  if (firstCharacterId === secondCharacterId) {
    const record = readAhogeSeasonRank(nk, firstCharacterId, seasonId);
    const winIncrement = firstActualScore === 0.5 ? 0 : 1;
    return {
      writes: [
        {
          collection: AHOGE_SEASON_RANK_COLLECTION,
          key: ahogeSeasonStorageKey(seasonId, firstCharacterId),
          userId: AHOGE_STORAGE_SYSTEM_USER_ID,
          value: {
            season_id: seasonId,
            character_id: firstCharacterId,
            ahoge_rating: record.value.ahoge_rating,
            total_match_wins: record.value.total_match_wins + winIncrement,
            total_ranked_matches: record.value.total_ranked_matches + 2
          },
          version: record.version,
          permissionRead: 1,
          permissionWrite: 0
        },
        pairWrite
      ],
      mirror_match: true,
      first_rating_before: record.value.ahoge_rating,
      first_rating_after: record.value.ahoge_rating,
      second_rating_before: record.value.ahoge_rating,
      second_rating_after: record.value.ahoge_rating,
      first_expected: firstExpected,
      second_expected: secondExpected,
      first_delta: 0,
      second_delta: 0,
      raw_delta: 0,
      trusted_delta: 0,
      trust_multiplier: trustMultiplier,
      pair_match_count_before: pairRecord.value.ranked_match_count,
      total_activity_count: totalAcceptedCombatInputCount,
      first_influence_used_before: 0,
      first_influence_used_after: 0,
      second_influence_used_before: 0,
      second_influence_used_after: 0,
      weight: AHOGE_RATING_WEIGHT,
      k_factor: kFactor
    };
  }

  const firstRecord = readAhogeSeasonRank(nk, firstCharacterId, seasonId);
  const secondRecord = readAhogeSeasonRank(nk, secondCharacterId, seasonId);
  const firstInfluence = readAhogePlayerCharacterInfluence(
    nk,
    firstUserId,
    firstCharacterId,
    seasonId
  );
  const secondInfluence = readAhogePlayerCharacterInfluence(
    nk,
    secondUserId,
    secondCharacterId,
    seasonId
  );

  const rawDelta = Math.round(kFactor * (firstActualScore - firstExpected));
  const trustedDelta = Math.round(rawDelta * trustMultiplier);
  const firstDelta = clampAhogeDeltaByInfluenceBudget(
    trustedDelta,
    firstInfluence.value.absolute_influence_used,
    secondInfluence.value.absolute_influence_used
  );
  const secondDelta = -firstDelta;
  const deltaMagnitude = Math.abs(firstDelta);
  const firstAfter = firstRecord.value.ahoge_rating + firstDelta;
  const secondAfter = secondRecord.value.ahoge_rating + secondDelta;
  const firstWinIncrement = firstActualScore === 1 ? 1 : 0;
  const secondWinIncrement = firstActualScore === 0 ? 1 : 0;
  const firstInfluenceAfter =
    firstInfluence.value.absolute_influence_used + deltaMagnitude;
  const secondInfluenceAfter =
    secondInfluence.value.absolute_influence_used + deltaMagnitude;

  return {
    writes: [
      {
        collection: AHOGE_SEASON_RANK_COLLECTION,
        key: ahogeSeasonStorageKey(seasonId, firstCharacterId),
        userId: AHOGE_STORAGE_SYSTEM_USER_ID,
        value: {
          season_id: seasonId,
          character_id: firstCharacterId,
          ahoge_rating: firstAfter,
          total_match_wins:
            firstRecord.value.total_match_wins + firstWinIncrement,
          total_ranked_matches:
            firstRecord.value.total_ranked_matches + 1
        },
        version: firstRecord.version,
        permissionRead: 1,
        permissionWrite: 0
      },
      {
        collection: AHOGE_SEASON_RANK_COLLECTION,
        key: ahogeSeasonStorageKey(seasonId, secondCharacterId),
        userId: AHOGE_STORAGE_SYSTEM_USER_ID,
        value: {
          season_id: seasonId,
          character_id: secondCharacterId,
          ahoge_rating: secondAfter,
          total_match_wins:
            secondRecord.value.total_match_wins + secondWinIncrement,
          total_ranked_matches:
            secondRecord.value.total_ranked_matches + 1
        },
        version: secondRecord.version,
        permissionRead: 1,
        permissionWrite: 0
      },
      {
        collection: AHOGE_PLAYER_CHARACTER_INFLUENCE_COLLECTION,
        key: influenceStorageKey(seasonId, firstCharacterId),
        userId: firstUserId,
        value: {
          season_id: seasonId,
          character_id: firstCharacterId,
          absolute_influence_used: firstInfluenceAfter
        },
        version: firstInfluence.version,
        permissionRead: 0,
        permissionWrite: 0
      },
      {
        collection: AHOGE_PLAYER_CHARACTER_INFLUENCE_COLLECTION,
        key: influenceStorageKey(seasonId, secondCharacterId),
        userId: secondUserId,
        value: {
          season_id: seasonId,
          character_id: secondCharacterId,
          absolute_influence_used: secondInfluenceAfter
        },
        version: secondInfluence.version,
        permissionRead: 0,
        permissionWrite: 0
      },
      pairWrite
    ],
    mirror_match: false,
    first_rating_before: firstRecord.value.ahoge_rating,
    first_rating_after: firstAfter,
    second_rating_before: secondRecord.value.ahoge_rating,
    second_rating_after: secondAfter,
    first_expected: firstExpected,
    second_expected: secondExpected,
    first_delta: firstDelta,
    second_delta: secondDelta,
    raw_delta: rawDelta,
    trusted_delta: trustedDelta,
    trust_multiplier: trustMultiplier,
    pair_match_count_before: pairRecord.value.ranked_match_count,
    total_activity_count: totalAcceptedCombatInputCount,
    first_influence_used_before:
      firstInfluence.value.absolute_influence_used,
    first_influence_used_after: firstInfluenceAfter,
    second_influence_used_before:
      secondInfluence.value.absolute_influence_used,
    second_influence_used_after: secondInfluenceAfter,
    weight: AHOGE_RATING_WEIGHT,
    k_factor: kFactor
  };
}

function ahogeLegendLeaderboardId(seasonId: string): string {
  return AHOGE_LEGEND_LEADERBOARD_PREFIX + seasonId;
}

function ensureAhogeLegendLeaderboard(
  nk: nkruntime.Nakama,
  seasonId: string
): string {
  const id = ahogeLegendLeaderboardId(seasonId);
  nk.leaderboardCreate(
    id,
    true,
    nkruntime.SortOrder.DESCENDING,
    nkruntime.Operator.SET,
    "",
    {
      season_id: seasonId,
      ranking_type: "AHOGE_LEGEND"
    },
    true
  );
  return id;
}

function syncAhogeRankingRecord(
  nk: nkruntime.Nakama,
  characterId: string,
  seasonId: string
): void {
  const record = readAhogeSeasonRank(nk, characterId, seasonId);
  const ownerId = characterRankingOwnerId(characterId);
  const leaderboardId = ensureAhogeLegendLeaderboard(nk, seasonId);

  nk.leaderboardRecordWrite(
    leaderboardId,
    ownerId,
    "",
    record.value.ahoge_rating,
    0,
    {
      season_id: seasonId,
      character_id: characterId,
      total_match_wins: record.value.total_match_wins,
      total_ranked_matches: record.value.total_ranked_matches
    }
  );
}

function syncExistingAhogeLegendProjection(
  nk: nkruntime.Nakama,
  seasonId: string
): void {
  Object.keys(CHARACTER_RANK_OWNER_IDS).forEach(function (characterId): void {
    const record = readAhogeSeasonRank(nk, characterId, seasonId);
    if (record.exists) {
      syncAhogeRankingRecord(nk, characterId, seasonId);
    }
  });
}

function syncAhogeLegendProjection(
  nk: nkruntime.Nakama,
  characterIds: string[],
  seasonId: string
): boolean {
  try {
    const synced: {[key: string]: boolean} = {};
    characterIds.forEach(function (characterId): void {
      if (!synced[characterId]) {
        syncAhogeRankingRecord(nk, characterId, seasonId);
        synced[characterId] = true;
      }
    });
    return true;
  } catch (_error) {
    return false;
  }
}

const ahogeCharacterRatingRpc: nkruntime.RpcFunction = function (
  ctx,
  _logger,
  nk,
  payload
): string {
  if (!ctx.userId) {
    throw new Error("authentication required");
  }

  let characterId = "";
  let requestedSeasonId = "";
  if (payload) {
    try {
      const parsed = JSON.parse(payload);
      characterId = String(parsed.character_id || "");
      requestedSeasonId = parseOptionalSeasonId(parsed);
    } catch (_error) {
      throw new Error("invalid payload");
    }
  }
  if (!characterRankingOwnerId(characterId)) {
    throw new Error("unsupported character_id");
  }

  const now = Date.now();
  const seasonId = resolveRequestedSeasonId(requestedSeasonId, now);
  ensureSeasonMetadata(nk, seasonId);
  const visibility = seasonRankingVisibility(seasonId, now);
  if (!visibility.ranking_public) {
    return JSON.stringify({
      season_id: seasonId,
      character_id: characterId,
      ranking_public: false,
      ranking_hidden_until_unix_ms:
        visibility.ranking_hidden_until_unix_ms
    });
  }

  const value = readAhogeSeasonRank(nk, characterId, seasonId).value;
  return JSON.stringify({
    season_id: value.season_id,
    character_id: value.character_id,
    ahoge_rating: value.ahoge_rating,
    total_match_wins: value.total_match_wins,
    total_ranked_matches: value.total_ranked_matches,
    ranking_public: true,
    ranking_hidden_until_unix_ms: 0
  });
};

const ahogeLegendRankingRpc: nkruntime.RpcFunction = function (
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
  const limit = Math.max(1, Math.min(AHOGE_LEGEND_MAX_LIMIT, requestedLimit));

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

  syncExistingAhogeLegendProjection(nk, seasonId);
  const leaderboardId = ensureAhogeLegendLeaderboard(nk, seasonId);
  const result = nk.leaderboardRecordsList(
    leaderboardId,
    [],
    limit,
    "",
    0
  );

  const rawRecords = result.records || [];
  let previousRating: number | null = null;
  let previousDisplayRank = 0;

  const records = rawRecords.map(function (record, index): any {
    const rating = Number(record.score);
    let displayRank = index + 1;
    if (previousRating !== null && rating === previousRating) {
      displayRank = previousDisplayRank;
    }
    previousRating = rating;
    previousDisplayRank = displayRank;

    let metadata: any = {};
    if (record.metadata) {
      try {
        metadata = typeof record.metadata === "string"
          ? JSON.parse(record.metadata)
          : record.metadata;
      } catch (_error) {
        metadata = {};
      }
    }

    const characterId = String(metadata.character_id || "");
    const canonical = readAhogeSeasonRank(nk, characterId, seasonId);

    return {
      display_rank: displayRank,
      character_id: characterId,
      ahoge_rating: canonical.value.ahoge_rating,
      total_match_wins: canonical.value.total_match_wins,
      total_ranked_matches: canonical.value.total_ranked_matches,
      legendary: displayRank === 1
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
