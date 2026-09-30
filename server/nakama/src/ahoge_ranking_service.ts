const AHOGE_SEASON_RANK_COLLECTION = "ahoge_season_rank";
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

interface AhogeRatingSettlementResult {
  writes: nkruntime.StorageWriteRequest[];
  mirror_match: boolean;
  winner_rating_before: number;
  winner_rating_after: number;
  loser_rating_before: number;
  loser_rating_after: number;
  winner_expected: number;
  loser_expected: number;
  winner_delta: number;
  loser_delta: number;
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

function buildAhogeSeasonRankSettlement(
  nk: nkruntime.Nakama,
  winnerCharacterId: string,
  loserCharacterId: string,
  seasonId: string,
  winnerPlayerRatingBefore: number,
  loserPlayerRatingBefore: number,
  winnerAhogeRatingBefore: number,
  loserAhogeRatingBefore: number,
  winnerAhogeMatchCountBefore: number,
  loserAhogeMatchCountBefore: number
): AhogeRatingSettlementResult {
  const winnerOwnerId = characterRankingOwnerId(winnerCharacterId);
  const loserOwnerId = characterRankingOwnerId(loserCharacterId);
  if (!winnerOwnerId || !loserOwnerId) {
    throw new Error("unsupported character for AHOGE LEGEND ranking");
  }

  if (winnerCharacterId === loserCharacterId) {
    const record = readAhogeSeasonRank(nk, winnerCharacterId, seasonId);
    const expected = ahogeExpectedScore(
      ahogeEffectiveRating(
        winnerPlayerRatingBefore,
        winnerAhogeRatingBefore
      ),
      ahogeEffectiveRating(
        loserPlayerRatingBefore,
        loserAhogeRatingBefore
      )
    );
    return {
      writes: [
        {
          collection: AHOGE_SEASON_RANK_COLLECTION,
          key: ahogeSeasonStorageKey(seasonId, winnerCharacterId),
          userId: AHOGE_STORAGE_SYSTEM_USER_ID,
          value: {
            season_id: seasonId,
            character_id: winnerCharacterId,
            ahoge_rating: record.value.ahoge_rating,
            total_match_wins: record.value.total_match_wins + 1,
            total_ranked_matches: record.value.total_ranked_matches + 2
          },
          version: record.version,
          permissionRead: 1,
          permissionWrite: 0
        }
      ],
      mirror_match: true,
      winner_rating_before: winnerAhogeRatingBefore,
      winner_rating_after: winnerAhogeRatingBefore,
      loser_rating_before: loserAhogeRatingBefore,
      loser_rating_after: loserAhogeRatingBefore,
      winner_expected: expected,
      loser_expected: 1 - expected,
      winner_delta: 0,
      loser_delta: 0,
      weight: AHOGE_RATING_WEIGHT,
      k_factor: ahogeKForMatchCounts(
        winnerAhogeMatchCountBefore,
        loserAhogeMatchCountBefore
      )
    };
  }

  const winnerRecord = readAhogeSeasonRank(nk, winnerCharacterId, seasonId);
  const loserRecord = readAhogeSeasonRank(nk, loserCharacterId, seasonId);
  const winnerEffective = ahogeEffectiveRating(
    winnerPlayerRatingBefore,
    winnerAhogeRatingBefore
  );
  const loserEffective = ahogeEffectiveRating(
    loserPlayerRatingBefore,
    loserAhogeRatingBefore
  );
  const winnerExpected = ahogeExpectedScore(winnerEffective, loserEffective);
  const kFactor = ahogeKForMatchCounts(
    winnerAhogeMatchCountBefore,
    loserAhogeMatchCountBefore
  );
  const delta = Math.round(kFactor * (1 - winnerExpected));
  const winnerSettlementAfter = winnerAhogeRatingBefore + delta;
  const loserSettlementAfter = loserAhogeRatingBefore - delta;
  // 別matchのsettlementが対戦中に同characterへ反映されても失わないよう、
  // storage正本にはsettlement時点のcurrent値へ今回deltaだけを加減する。
  const winnerStorageAfter = winnerRecord.value.ahoge_rating + delta;
  const loserStorageAfter = loserRecord.value.ahoge_rating - delta;

  return {
    writes: [
      {
        collection: AHOGE_SEASON_RANK_COLLECTION,
        key: ahogeSeasonStorageKey(seasonId, winnerCharacterId),
        userId: AHOGE_STORAGE_SYSTEM_USER_ID,
        value: {
          season_id: seasonId,
          character_id: winnerCharacterId,
          ahoge_rating: winnerStorageAfter,
          total_match_wins: winnerRecord.value.total_match_wins + 1,
          total_ranked_matches: winnerRecord.value.total_ranked_matches + 1
        },
        version: winnerRecord.version,
        permissionRead: 1,
        permissionWrite: 0
      },
      {
        collection: AHOGE_SEASON_RANK_COLLECTION,
        key: ahogeSeasonStorageKey(seasonId, loserCharacterId),
        userId: AHOGE_STORAGE_SYSTEM_USER_ID,
        value: {
          season_id: seasonId,
          character_id: loserCharacterId,
          ahoge_rating: loserStorageAfter,
          total_match_wins: loserRecord.value.total_match_wins,
          total_ranked_matches: loserRecord.value.total_ranked_matches + 1
        },
        version: loserRecord.version,
        permissionRead: 1,
        permissionWrite: 0
      }
    ],
    mirror_match: false,
    winner_rating_before: winnerAhogeRatingBefore,
    winner_rating_after: winnerSettlementAfter,
    loser_rating_before: loserAhogeRatingBefore,
    loser_rating_after: loserSettlementAfter,
    winner_expected: winnerExpected,
    loser_expected: 1 - winnerExpected,
    winner_delta: delta,
    loser_delta: -delta,
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
  winnerCharacterId: string,
  loserCharacterId: string,
  seasonId: string
): boolean {
  try {
    syncAhogeRankingRecord(nk, winnerCharacterId, seasonId);
    if (loserCharacterId !== winnerCharacterId) {
      syncAhogeRankingRecord(nk, loserCharacterId, seasonId);
    }
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
  return JSON.stringify(readAhogeSeasonRank(nk, characterId, seasonId).value);
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
    rank_count: result.rankCount || rawRecords.length
  });
};
