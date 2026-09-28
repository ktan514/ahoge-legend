const AHOGE_SEASON_RANK_COLLECTION = "ahoge_season_rank";
const AHOGE_LEGEND_LEADERBOARD_PREFIX = "ahoge_legend_";
const AHOGE_LEGEND_MAX_LIMIT = 100;

const CHARACTER_RANK_OWNER_IDS: {[key: string]: string} = {
  LONG_TEST: "10000000-0000-0000-0000-000000000001",
  SHORT_TEST: "10000000-0000-0000-0000-000000000002"
};

interface AhogeSeasonRankValue {
  season_id: string;
  character_id: string;
  total_match_wins: number;
  total_ranked_matches: number;
}

interface AhogeSeasonRankRecord {
  value: AhogeSeasonRankValue;
  version: string;
  exists: boolean;
}

function characterRankingOwnerId(characterId: string): string {
  return CHARACTER_RANK_OWNER_IDS[characterId] || "";
}

function defaultAhogeSeasonRank(
  seasonId: string,
  characterId: string
): AhogeSeasonRankValue {
  return {
    season_id: seasonId,
    character_id: characterId,
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
      key: seasonId,
      userId: ownerId
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
      total_match_wins: Number(raw.total_match_wins || 0),
      total_ranked_matches: Number(raw.total_ranked_matches || 0)
    },
    version: object.version,
    exists: true
  };
}

function buildAhogeSeasonRankWrites(
  nk: nkruntime.Nakama,
  winnerCharacterId: string,
  loserCharacterId: string,
  seasonId: string
): nkruntime.StorageWriteRequest[] {
  const winnerOwnerId = characterRankingOwnerId(winnerCharacterId);
  const loserOwnerId = characterRankingOwnerId(loserCharacterId);
  if (!winnerOwnerId || !loserOwnerId) {
    throw new Error("unsupported character for AHOGE LEGEND ranking");
  }

  if (winnerCharacterId === loserCharacterId) {
    const record = readAhogeSeasonRank(nk, winnerCharacterId, seasonId);
    return [
      {
        collection: AHOGE_SEASON_RANK_COLLECTION,
        key: seasonId,
        userId: winnerOwnerId,
        value: {
          season_id: seasonId,
          character_id: winnerCharacterId,
          total_match_wins: record.value.total_match_wins + 1,
          total_ranked_matches: record.value.total_ranked_matches + 2
        },
        version: record.version,
        permissionRead: 1,
        permissionWrite: 0
      }
    ];
  }

  const winnerRecord = readAhogeSeasonRank(nk, winnerCharacterId, seasonId);
  const loserRecord = readAhogeSeasonRank(nk, loserCharacterId, seasonId);
  return [
    {
      collection: AHOGE_SEASON_RANK_COLLECTION,
      key: seasonId,
      userId: winnerOwnerId,
      value: {
        season_id: seasonId,
        character_id: winnerCharacterId,
        total_match_wins: winnerRecord.value.total_match_wins + 1,
        total_ranked_matches: winnerRecord.value.total_ranked_matches + 1
      },
      version: winnerRecord.version,
      permissionRead: 1,
      permissionWrite: 0
    },
    {
      collection: AHOGE_SEASON_RANK_COLLECTION,
      key: seasonId,
      userId: loserOwnerId,
      value: {
        season_id: seasonId,
        character_id: loserCharacterId,
        total_match_wins: loserRecord.value.total_match_wins,
        total_ranked_matches: loserRecord.value.total_ranked_matches + 1
      },
      version: loserRecord.version,
      permissionRead: 1,
      permissionWrite: 0
    }
  ];
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
    record.value.total_match_wins,
    0,
    {
      season_id: seasonId,
      character_id: characterId,
      total_ranked_matches: record.value.total_ranked_matches
    }
  );
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
  const limit = Math.max(1, Math.min(AHOGE_LEGEND_MAX_LIMIT, requestedLimit));

  const seasonId = currentSeasonIdJst(Date.now());
  const leaderboardId = ensureAhogeLegendLeaderboard(nk, seasonId);
  const result = nk.leaderboardRecordsList(
    leaderboardId,
    [],
    limit,
    "",
    0
  );

  const rawRecords = result.records || [];
  let previousWins: number | null = null;
  let previousDisplayRank = 0;

  const records = rawRecords.map(function (record, index): any {
    const wins = Number(record.score);
    let displayRank = index + 1;
    if (previousWins !== null && wins === previousWins) {
      displayRank = previousDisplayRank;
    }
    previousWins = wins;
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

    return {
      display_rank: displayRank,
      character_id: String(metadata.character_id || ""),
      total_match_wins: wins,
      total_ranked_matches: Number(metadata.total_ranked_matches || 0),
      legendary: displayRank === 1
    };
  });

  return JSON.stringify({
    season_id: seasonId,
    records: records,
    rank_count: result.rankCount || rawRecords.length
  });
};
