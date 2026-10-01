const healthRpc: nkruntime.RpcFunction = function (
  ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  _nk: nkruntime.Nakama,
  _payload: string
): string {
  if (ctx.userId) {
    logger.warn("ahoge_health rejected a user-session request.");
    throw new Error("ahoge_health is server-to-server only");
  }

  return JSON.stringify({
    service: "ahoge-legend",
    status: "ok",
    runtime: "typescript"
  });
};

let InitModule: nkruntime.InitModule = function (
  _ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  _nk: nkruntime.Nakama,
  initializer: nkruntime.Initializer
): void {
  initializer.registerRpc("ahoge_health", healthRpc);
  initializer.registerRpc("ahoge_season_metadata", seasonMetadataRpc);
  initializer.registerRpc("ahoge_current_rating", currentRatingRpc);
  initializer.registerRpc("ahoge_player_ranking", playerRankingRpc);
  initializer.registerRpc("ahoge_character_rating", ahogeCharacterRatingRpc);
  initializer.registerRpc("ahoge_legend_ranking", ahogeLegendRankingRpc);
  initializer.registerRpc("ahoge_ranked_settlement", rankedMatchSettlementRpc);
  initializer.registerRpc("ahoge_active_match_get", activeOnlineMatchGetRpc);
  initializer.registerRpc("ahoge_active_match_ack", activeOnlineMatchAckRpc);
  initializer.registerRpc("ahoge_friend_room_create", friendRoomCreateRpc);
  initializer.registerRpc("ahoge_friend_room_join", friendRoomJoinRpc);
  initializer.registerRpc("ahoge_friend_room_status", friendRoomStatusRpc);
  initializer.registerRpc("ahoge_friend_room_character", friendRoomCharacterRpc);
  initializer.registerRpc("ahoge_friend_room_ready", friendRoomReadyRpc);
  initializer.registerRpc("ahoge_friend_room_result_action", friendRoomResultActionRpc);
  initializer.registerRpc("ahoge_friend_room_leave", friendRoomLeaveRpc);
  initializer.registerMatch("ahoge_ranked", rankedMatchHandler);
  initializer.registerMatchmakerMatched(rankedMatchmakerMatched);
  logger.info("AHOGE LEGEND TypeScript runtime loaded.");
};
