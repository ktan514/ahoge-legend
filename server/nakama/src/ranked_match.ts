const COMBAT_INPUT_OPCODE = 1;
const INPUT_ACCEPTED_OPCODE = 101;
const COMBAT_STATE_CHANGED_OPCODE = 102;
const CONTACT_REACHED_OPCODE = 103;
const DEFENSE_RESOLVED_OPCODE = 104;
const HIT_CONFIRMED_OPCODE = 105;
const ATTACK_CLASH_OPCODE = 106;
const ROUND_HIT_COUNT_CHANGED_OPCODE = 107;
const ROUND_TIMER_CHANGED_OPCODE = 108;
const ROUND_OVERTIME_STARTED_OPCODE = 109;
const ROUND_RESULT_OPCODE = 110;
const BO3_SCORE_CHANGED_OPCODE = 111;
const ROUND_STARTED_OPCODE = 112;
const MATCH_RESULT_OPCODE = 113;
const ROUND_COUNTDOWN_CHANGED_OPCODE = 114;
const MATCH_SNAPSHOT_OPCODE = 115;
const PLAYER_CONNECTION_CHANGED_OPCODE = 116;

const ROUND_COUNTDOWN_SECONDS = 3;
const RECONNECT_GRACE_TICKS = 15 * AUTHORITATIVE_MATCH_TICK_RATE;
const ROUND_RESULT_HOLD_TICKS = 2 * AUTHORITATIVE_MATCH_TICK_RATE;

const ROUNDS_TO_WIN_MATCH = 2;
const MAX_ROUNDS = 3;

const DEFENSE_RESULT_NONE = "NONE";
const DEFENSE_RESULT_PARRY = "PARRY";
const DEFENSE_RESULT_JUST_PARRY = "JUST_PARRY";
const DEFENSE_RESULT_DODGE = "DODGE";
const DEFENSE_RESULT_JUST_DODGE = "JUST_DODGE";

const COMBAT_STATE_IDLE = "IDLE";
const COMBAT_STATE_CHARGING = "CHARGING";
const COMBAT_STATE_WINDUP = "WINDUP";
const COMBAT_STATE_STRIKE = "STRIKE";
const COMBAT_STATE_COOLDOWN = "COOLDOWN";
const COMBAT_STATE_PARRY = "PARRY";
const COMBAT_STATE_DODGE = "DODGE";
const COMBAT_STATE_STAGGER = "STAGGER";
const COMBAT_STATE_ROUND_LOCKED = "ROUND_LOCKED";

const ROUND_FINISH_CAUSE_NONE = "NONE";
const ROUND_FINISH_CAUSE_HIT_LIMIT = "HIT_LIMIT";
const ROUND_FINISH_CAUSE_TIMEOUT = "TIMEOUT";
const ROUND_FINISH_CAUSE_OVERTIME_HIT = "OVERTIME_HIT";

const MATCH_FINISH_CAUSE_NONE = "NONE";
const MATCH_FINISH_CAUSE_BO3 = "BO3";
const MATCH_FINISH_CAUSE_DISCONNECT_TIMEOUT = "DISCONNECT_TIMEOUT";

const CHARACTER_LONG_TEST = "LONG_TEST";
const CHARACTER_SHORT_TEST = "SHORT_TEST";

const ALLOWED_COMBAT_ACTIONS: {[key: string]: boolean} = {
  ATTACK_PRESS: true,
  ATTACK_RELEASE: true,
  DEFEND: true
};

interface AuthoritativeCombatState {
  state: string;
  ahogeAvailable: boolean;
  chargeStartTick: number;
  chargeRatio: number;
  strikeStartTick: number;
  contactTick: number;
  strikeEndTick: number;
  cooldownEndTick: number;
  contactEmitted: boolean;
  releaseSequence: number;
  defenseStartTick: number;
  defenseEndTick: number;
  defenseJustUntilTick: number;
  resumeState: string;
  resumeRemainingTicks: number;
  staggerEndTick: number;
  regrowEndTick: number;
}

interface AhogeRankedMatchState {
  matchId: string;
  matchMode: string;
  friendRoomCode: string;
  friendMatchGeneration: number;
  friendRoomSettlementDone: boolean;
  friendRoomSettlementRetryTick: number;
  expectedUserIds: {[key: string]: boolean};
  presences: {[key: string]: nkruntime.Presence};
  lastInputSequenceByUser: {[key: string]: number};
  lastAcceptedTickByUser: {[key: string]: number};
  combatStateByUser: {[key: string]: AuthoritativeCombatState};
  characterIdByUser: {[key: string]: string};
  roundHitCountByUser: {[key: string]: number};
  roundHitCountSnapshotBroadcast: boolean;
  roundTimerStartTick: number;
  roundTimerEndTick: number;
  roundRemainingSeconds: number;
  roundFinished: boolean;
  roundWinnerUserId: string;
  roundFinishCause: string;
  roundAwaitingOvertime: boolean;
  roundOvertime: boolean;
  roundNumber: number;
  roundWinsByUser: {[key: string]: number};
  roundResetPending: boolean;
  roundResultHoldUntilTick: number;
  roundCountdownActive: boolean;
  roundCountdownStartTick: number;
  roundCountdownValue: number;
  reconnectDeadlineTickByUser: {[key: string]: number};
  roundBoundaryPauseStartTick: number;
  matchFinished: boolean;
  matchWinnerUserId: string;
  matchFinishCause: string;
  matchFinishedAtUnixMs: number;
  ratingSettlementDone: boolean;
  ratingSettlementRetryTick: number;
  activeMatchResultPersisted: boolean;
  activeMatchResultRetryTick: number;
}

const rankedMatchInit: nkruntime.MatchInitFunction<AhogeRankedMatchState> = function (
  ctx,
  logger,
  nk,
  params
) {
  const expectedUserIds: {[key: string]: boolean} = {};
  const characterIdByUser: {[key: string]: string} = {};
  const rawExpected = params.expectedUserIds;
  const rawCharacters = params.characterIds;
  const rawMatchMode = String(params.matchMode || "ranked");
  const matchMode = rawMatchMode === "friend" ? "friend" : "ranked";
  const friendRoomCode =
    matchMode === "friend" ? String(params.friendRoomCode || "") : "";
  const rawFriendMatchGeneration = Number(params.friendMatchGeneration || 0);
  const friendMatchGeneration =
    matchMode === "friend" &&
    isFinite(rawFriendMatchGeneration) &&
    Math.floor(rawFriendMatchGeneration) === rawFriendMatchGeneration &&
    rawFriendMatchGeneration > 0
      ? rawFriendMatchGeneration
      : 0;

  if (Array.isArray(rawExpected)) {
    rawExpected.forEach(function (userId: any): void {
      const id = String(userId);
      if (id) {
        expectedUserIds[id] = true;
      }
    });
  }

  if (rawCharacters && typeof rawCharacters === "object") {
    Object.keys(rawCharacters).forEach(function (userId): void {
      const characterId = String((rawCharacters as any)[userId] || "");
      if (isSupportedCharacterId(characterId)) characterIdByUser[userId] = characterId;
    });
  }

  const matchId = String(ctx.matchId || "");
  const participantIds = Object.keys(expectedUserIds);
  if (!matchId || participantIds.length !== 2) {
    throw new Error("invalid authoritative match participants");
  }
  createActiveOnlineMatchForUsers(
    nk,
    participantIds,
    matchId,
    matchMode,
    Date.now()
  );

  logger.info("ahoge_ranked authoritative match initialized.");

  return {
    state: {
      matchId: String(ctx.matchId || ""),
      matchMode: matchMode,
      friendRoomCode: friendRoomCode,
      friendMatchGeneration: friendMatchGeneration,
      friendRoomSettlementDone: matchMode !== "friend",
      friendRoomSettlementRetryTick: 0,
      expectedUserIds: expectedUserIds,
      presences: {},
      lastInputSequenceByUser: {},
      lastAcceptedTickByUser: {},
      combatStateByUser: {},
      characterIdByUser: characterIdByUser,
      roundHitCountByUser: {},
      roundHitCountSnapshotBroadcast: false,
      roundTimerStartTick: -1,
      roundTimerEndTick: -1,
      roundRemainingSeconds: ROUND_DURATION_SECONDS,
      roundFinished: false,
      roundWinnerUserId: "",
      roundFinishCause: ROUND_FINISH_CAUSE_NONE,
      roundAwaitingOvertime: false,
      roundOvertime: false,
      roundNumber: 1,
      roundWinsByUser: {},
      roundResetPending: false,
      roundResultHoldUntilTick: -1,
      roundCountdownActive: false,
      roundCountdownStartTick: -1,
      roundCountdownValue: -1,
      reconnectDeadlineTickByUser: {},
      roundBoundaryPauseStartTick: -1,
      matchFinished: false,
      matchWinnerUserId: "",
      matchFinishCause: MATCH_FINISH_CAUSE_NONE,
      matchFinishedAtUnixMs: -1,
      ratingSettlementDone: false,
      ratingSettlementRetryTick: 0,
      activeMatchResultPersisted: false,
      activeMatchResultRetryTick: 0
    },
    tickRate: AUTHORITATIVE_MATCH_TICK_RATE,
    label: JSON.stringify({
      mode: matchMode,
      phase: "waiting"
    })
  };
};

const rankedMatchJoinAttempt: nkruntime.MatchJoinAttemptFunction<AhogeRankedMatchState> = function (
  _ctx,
  _logger,
  _nk,
  _dispatcher,
  tick,
  state,
  presence,
  _metadata
) {
  if (!state.expectedUserIds[presence.userId]) {
    return {
      state: state,
      accept: false,
      rejectMessage: "user was not selected by matchmaker"
    };
  }

  const reconnectDeadline = state.reconnectDeadlineTickByUser[presence.userId];
  if (
    !state.matchFinished &&
    reconnectDeadline !== undefined &&
    tick >= reconnectDeadline
  ) {
    return {state: state, accept: false, rejectMessage: "reconnect grace expired"};
  }

  if (!isSupportedCharacterId(state.characterIdByUser[presence.userId])) {
    return {state: state, accept: false, rejectMessage: "character was not selected"};
  }

  const existing = state.presences[presence.userId];
  if (!existing && Object.keys(state.presences).length >= 2) {
    return {
      state: state,
      accept: false,
      rejectMessage: "match is full"
    };
  }

  return {
    state: state,
    accept: true
  };
};

const rankedMatchJoin: nkruntime.MatchJoinFunction<AhogeRankedMatchState> = function (
  _ctx,
  logger,
  _nk,
  dispatcher,
  tick,
  state,
  presences
) {
  const reconnectedUserIds: string[] = [];

  presences.forEach(function (presence): void {
    const reconnectDeadline = state.reconnectDeadlineTickByUser[presence.userId];
    const isReconnect = reconnectDeadline !== undefined;

    state.presences[presence.userId] = presence;
    if (state.lastInputSequenceByUser[presence.userId] === undefined) {
      state.lastInputSequenceByUser[presence.userId] = 0;
    }
    if (state.lastAcceptedTickByUser[presence.userId] === undefined) {
      state.lastAcceptedTickByUser[presence.userId] = -1;
    }
    if (!state.combatStateByUser[presence.userId]) {
      state.combatStateByUser[presence.userId] = createIdleCombatState(true);
    }
    if (state.roundHitCountByUser[presence.userId] === undefined) {
      state.roundHitCountByUser[presence.userId] = 0;
    }
    if (state.roundWinsByUser[presence.userId] === undefined) {
      state.roundWinsByUser[presence.userId] = 0;
    }

    if (isReconnect) {
      delete state.reconnectDeadlineTickByUser[presence.userId];
      reconnectedUserIds.push(presence.userId);
    }
  });

  if (!state.matchFinished && allExpectedPlayersConnected(state)) {
    resumeRoundBoundaryAfterReconnect(state, tick);
  }

  presences.forEach(function (presence): void {
    const userId = presence.userId;
    const wasReconnect = reconnectedUserIds.indexOf(userId) >= 0;
    if (wasReconnect) {
      broadcastPlayerConnectionChanged(dispatcher, userId, true, -1, tick);
    }
    // 通常join時も初期snapshotを送り、GameFlow/UIがserver stateを正本にできるようにする。
    broadcastMatchSnapshot(dispatcher, state, presence, tick);
  });

  logger.info("ahoge_ranked player joined. size=%d", Object.keys(state.presences).length);
  return {state: state};
};

const rankedMatchLeave: nkruntime.MatchLeaveFunction<AhogeRankedMatchState> = function (
  _ctx,
  logger,
  _nk,
  dispatcher,
  tick,
  state,
  presences
) {
  presences.forEach(function (presence): void {
    delete state.presences[presence.userId];

    if (!state.matchFinished) {
      const deadlineTick = tick + RECONNECT_GRACE_TICKS;
      state.reconnectDeadlineTickByUser[presence.userId] = deadlineTick;
      if (!isActiveRoundPhase(state)) {
        beginRoundBoundaryReconnectWait(state, tick);
      }
      broadcastPlayerConnectionChanged(
        dispatcher,
        presence.userId,
        false,
        deadlineTick,
        tick
      );
    }
  });

  logger.info("ahoge_ranked player left. size=%d", Object.keys(state.presences).length);
  return {state: state};
};

function participantUserIds(state: AhogeRankedMatchState): string[] {
  return Object.keys(state.expectedUserIds);
}

function allExpectedPlayersConnected(state: AhogeRankedMatchState): boolean {
  const userIds = participantUserIds(state);
  if (userIds.length !== 2) {
    return false;
  }
  return userIds.every(function (userId): boolean {
    return !!state.presences[userId];
  });
}

function isActiveRoundPhase(state: AhogeRankedMatchState): boolean {
  return (
    !state.matchFinished &&
    !state.roundFinished &&
    !state.roundCountdownActive &&
    state.roundTimerStartTick >= 0
  );
}

function beginRoundBoundaryReconnectWait(
  state: AhogeRankedMatchState,
  tick: number
): void {
  if (state.roundBoundaryPauseStartTick < 0) {
    state.roundBoundaryPauseStartTick = tick;
  }
}

function resumeRoundBoundaryAfterReconnect(
  state: AhogeRankedMatchState,
  tick: number
): void {
  if (state.roundBoundaryPauseStartTick < 0) {
    return;
  }

  const pausedTicks = Math.max(0, tick - state.roundBoundaryPauseStartTick);
  if (state.roundCountdownActive) {
    state.roundCountdownStartTick += pausedTicks;
  }
  if (
    state.roundFinished &&
    state.roundResetPending &&
    state.roundResultHoldUntilTick >= 0
  ) {
    state.roundResultHoldUntilTick += pausedTicks;
  }
  state.roundBoundaryPauseStartTick = -1;
}

function combatStateSnapshot(
  state: AhogeRankedMatchState
): {[key: string]: any} {
  const snapshot: {[key: string]: any} = {};
  participantUserIds(state).forEach(function (userId): void {
    const combat = state.combatStateByUser[userId];
    if (!combat) {
      return;
    }
    snapshot[userId] = {
      state: combat.state,
      charge_ratio: combat.chargeRatio,
      ahoge_available: combat.ahogeAvailable,
      charge_start_tick: combat.chargeStartTick,
      strike_start_tick: combat.strikeStartTick,
      contact_tick: combat.contactTick,
      strike_end_tick: combat.strikeEndTick,
      cooldown_end_tick: combat.cooldownEndTick,
      defense_active_until_tick: combat.defenseEndTick,
      defense_just_until_tick: combat.defenseJustUntilTick,
      stagger_until_tick: combat.staggerEndTick,
      regrow_until_tick: combat.regrowEndTick
    };
  });
  return snapshot;
}

function broadcastMatchSnapshot(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  presence: nkruntime.Presence,
  tick: number
): void {
  dispatcher.broadcastMessage(
    MATCH_SNAPSHOT_OPCODE,
    JSON.stringify({
      server_tick: tick,
      match_mode: state.matchMode,
      round_number: state.roundNumber,
      round_wins_by_user: roundWinsSnapshot(state),
      round_hit_count_by_user: state.roundHitCountByUser,
      remaining_seconds: state.roundRemainingSeconds,
      round_finished: state.roundFinished,
      round_winner_user_id: state.roundWinnerUserId,
      round_finish_cause: state.roundFinishCause,
      round_awaiting_overtime: state.roundAwaitingOvertime,
      round_overtime: state.roundOvertime,
      round_countdown_active: state.roundCountdownActive,
      round_countdown_value: state.roundCountdownValue,
      match_finished: state.matchFinished,
      match_winner_user_id: state.matchWinnerUserId,
      match_finish_cause: state.matchFinishCause,
      character_id_by_user: state.characterIdByUser,
      last_input_sequence: state.lastInputSequenceByUser[presence.userId] || 0,
      combat_state_by_user: combatStateSnapshot(state)
    }),
    [presence],
    null,
    true
  );
}

function broadcastPlayerConnectionChanged(
  dispatcher: nkruntime.MatchDispatcher,
  userId: string,
  connected: boolean,
  reconnectDeadlineTick: number,
  tick: number
): void {
  dispatcher.broadcastMessage(
    PLAYER_CONNECTION_CHANGED_OPCODE,
    JSON.stringify({
      user_id: userId,
      connected: connected,
      reconnect_deadline_tick: reconnectDeadlineTick,
      server_tick: tick
    }),
    null,
    null,
    true
  );
}

function createIdleCombatState(ahogeAvailable: boolean): AuthoritativeCombatState {
  return {
    state: COMBAT_STATE_IDLE,
    ahogeAvailable: ahogeAvailable,
    chargeStartTick: -1,
    chargeRatio: 0,
    strikeStartTick: -1,
    contactTick: -1,
    strikeEndTick: -1,
    cooldownEndTick: -1,
    contactEmitted: false,
    releaseSequence: 0,
    defenseStartTick: -1,
    defenseEndTick: -1,
    defenseJustUntilTick: -1,
    resumeState: COMBAT_STATE_IDLE,
    resumeRemainingTicks: 0,
    staggerEndTick: -1,
    regrowEndTick: -1
  };
}

function broadcastCombatState(
  dispatcher: nkruntime.MatchDispatcher,
  userId: string,
  combatState: AuthoritativeCombatState,
  tick: number
): void {
  dispatcher.broadcastMessage(
    COMBAT_STATE_CHANGED_OPCODE,
    JSON.stringify({
      user_id: userId,
      state: combatState.state,
      server_tick: tick,
      charge_ratio: combatState.chargeRatio,
      ahoge_available: combatState.ahogeAvailable,
      defense_active_until_tick: combatState.defenseEndTick,
      defense_just_until_tick: combatState.defenseJustUntilTick,
      stagger_until_tick: combatState.staggerEndTick,
      regrow_until_tick: combatState.regrowEndTick
    }),
    null,
    null,
    true
  );
}

function broadcastRoundHitCount(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  userId: string,
  tick: number,
  inputSequence: number
): void {
  dispatcher.broadcastMessage(
    ROUND_HIT_COUNT_CHANGED_OPCODE,
    JSON.stringify({
      user_id: userId,
      hit_count: state.roundHitCountByUser[userId] || 0,
      server_tick: tick,
      input_sequence: inputSequence
    }),
    null,
    null,
    true
  );
}

function broadcastRoundTimer(
  dispatcher: nkruntime.MatchDispatcher,
  remainingSeconds: number,
  tick: number
): void {
  dispatcher.broadcastMessage(
    ROUND_TIMER_CHANGED_OPCODE,
    JSON.stringify({
      remaining_seconds: remainingSeconds,
      server_tick: tick
    }),
    null,
    null,
    true
  );
}

function broadcastRoundOvertimeStarted(
  dispatcher: nkruntime.MatchDispatcher,
  tick: number
): void {
  dispatcher.broadcastMessage(
    ROUND_OVERTIME_STARTED_OPCODE,
    JSON.stringify({server_tick: tick}),
    null,
    null,
    true
  );
}

function broadcastRoundResult(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  winnerUserId: string,
  finishCause: string,
  tick: number
): void {
  const loserUserId = findOpponentUserId(state, winnerUserId);
  if (!loserUserId) {
    return;
  }

  dispatcher.broadcastMessage(
    ROUND_RESULT_OPCODE,
    JSON.stringify({
      round_number: state.roundNumber,
      winner_user_id: winnerUserId,
      loser_user_id: loserUserId,
      finish_cause: finishCause,
      winner_hits: state.roundHitCountByUser[winnerUserId] || 0,
      loser_hits: state.roundHitCountByUser[loserUserId] || 0,
      server_tick: tick
    }),
    null,
    null,
    true
  );
}

function roundWinsSnapshot(state: AhogeRankedMatchState): {[key: string]: number} {
  const snapshot: {[key: string]: number} = {};
  Object.keys(state.roundWinsByUser).forEach(function (userId): void {
    snapshot[userId] = state.roundWinsByUser[userId] || 0;
  });
  return snapshot;
}

function broadcastBo3ScoreChanged(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  completedRoundNumber: number,
  roundWinnerUserId: string,
  tick: number
): void {
  dispatcher.broadcastMessage(
    BO3_SCORE_CHANGED_OPCODE,
    JSON.stringify({
      completed_round_number: completedRoundNumber,
      round_winner_user_id: roundWinnerUserId,
      round_wins_by_user: roundWinsSnapshot(state),
      match_finished: state.matchFinished,
      server_tick: tick
    }),
    null,
    null,
    true
  );
}

function broadcastMatchResult(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  tick: number
): void {
  if (!state.matchFinished || !state.matchWinnerUserId) {
    return;
  }
  const loserUserId = findOpponentUserId(state, state.matchWinnerUserId);
  if (!loserUserId) {
    return;
  }

  dispatcher.broadcastMessage(
    MATCH_RESULT_OPCODE,
    JSON.stringify({
      winner_user_id: state.matchWinnerUserId,
      loser_user_id: loserUserId,
      round_wins_by_user: roundWinsSnapshot(state),
      final_round_number: state.roundNumber,
      finish_cause: state.matchFinishCause,
      server_tick: tick
    }),
    null,
    null,
    true
  );
}

function broadcastRoundStarted(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  tick: number
): void {
  dispatcher.broadcastMessage(
    ROUND_STARTED_OPCODE,
    JSON.stringify({
      round_number: state.roundNumber,
      round_wins_by_user: roundWinsSnapshot(state),
      server_tick: tick
    }),
    null,
    null,
    true
  );
}

function broadcastRoundCountdownChanged(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  countdownValue: number,
  tick: number
): void {
  dispatcher.broadcastMessage(
    ROUND_COUNTDOWN_CHANGED_OPCODE,
    JSON.stringify({
      round_number: state.roundNumber,
      countdown_value: countdownValue,
      server_tick: tick
    }),
    null,
    null,
    true
  );
}

function beginRoundCountdown(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  tick: number
): void {
  state.roundCountdownActive = true;
  state.roundCountdownStartTick = tick;
  state.roundCountdownValue = ROUND_COUNTDOWN_SECONDS;
  state.roundTimerStartTick = -1;
  state.roundTimerEndTick = -1;
  state.roundRemainingSeconds = ROUND_DURATION_SECONDS;
  state.roundFinished = false;
  state.roundWinnerUserId = "";
  state.roundFinishCause = ROUND_FINISH_CAUSE_NONE;
  state.roundAwaitingOvertime = false;
  state.roundOvertime = false;
  state.roundHitCountSnapshotBroadcast = true;

  participantUserIds(state).forEach(function (userId): void {
    state.roundHitCountByUser[userId] = 0;
    const locked = createIdleCombatState(true);
    locked.state = COMBAT_STATE_ROUND_LOCKED;
    state.combatStateByUser[userId] = locked;
    broadcastRoundHitCount(dispatcher, state, userId, tick, 0);
  });

  broadcastRoundTimer(dispatcher, ROUND_DURATION_SECONDS, tick);
  participantUserIds(state).forEach(function (userId): void {
    broadcastCombatState(dispatcher, userId, state.combatStateByUser[userId], tick);
  });
  broadcastRoundCountdownChanged(dispatcher, state, ROUND_COUNTDOWN_SECONDS, tick);
}

function startRoundAfterCountdown(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  tick: number
): void {
  state.roundCountdownActive = false;
  state.roundCountdownValue = 0;
  broadcastRoundCountdownChanged(dispatcher, state, 0, tick);

  state.roundTimerStartTick = tick;
  state.roundTimerEndTick = tick + roundDurationTicks();
  state.roundRemainingSeconds = ROUND_DURATION_SECONDS;

  participantUserIds(state).forEach(function (userId): void {
    state.roundHitCountByUser[userId] = 0;
    state.combatStateByUser[userId] = createIdleCombatState(true);
  });

  broadcastRoundStarted(dispatcher, state, tick);
  participantUserIds(state).forEach(function (userId): void {
    broadcastRoundHitCount(dispatcher, state, userId, tick, 0);
  });
  broadcastRoundTimer(dispatcher, ROUND_DURATION_SECONDS, tick);
  participantUserIds(state).forEach(function (userId): void {
    broadcastCombatState(dispatcher, userId, state.combatStateByUser[userId], tick);
  });
}

function advanceRoundCountdown(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  tick: number
): void {
  if (!state.roundCountdownActive) {
    return;
  }

  const elapsedTicks = Math.max(0, tick - state.roundCountdownStartTick);
  const elapsedSeconds = Math.floor(elapsedTicks / AUTHORITATIVE_MATCH_TICK_RATE);
  const nextValue = ROUND_COUNTDOWN_SECONDS - elapsedSeconds;

  if (nextValue > 0 && nextValue !== state.roundCountdownValue) {
    state.roundCountdownValue = nextValue;
    broadcastRoundCountdownChanged(dispatcher, state, nextValue, tick);
  }

  if (elapsedTicks >= ROUND_COUNTDOWN_SECONDS * AUTHORITATIVE_MATCH_TICK_RATE) {
    startRoundAfterCountdown(dispatcher, state, tick);
  }
}

function lockRoundCombat(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  tick: number
): void {
  Object.keys(state.combatStateByUser).forEach(function (userId): void {
    const current = state.combatStateByUser[userId];
    const locked = createIdleCombatState(current ? current.ahogeAvailable : true);
    locked.state = COMBAT_STATE_ROUND_LOCKED;
    state.combatStateByUser[userId] = locked;
    broadcastCombatState(dispatcher, userId, locked, tick);
  });
}

function finishRound(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  winnerUserId: string,
  finishCause: string,
  tick: number
): void {
  if (state.roundFinished || state.roundAwaitingOvertime || state.matchFinished) {
    return;
  }
  state.roundFinished = true;
  state.roundWinnerUserId = winnerUserId;
  state.roundFinishCause = finishCause;
  state.roundOvertime = false;
  lockRoundCombat(dispatcher, state, tick);
  broadcastRoundResult(dispatcher, state, winnerUserId, finishCause, tick);

  state.roundWinsByUser[winnerUserId] = (state.roundWinsByUser[winnerUserId] || 0) + 1;
  if (state.roundWinsByUser[winnerUserId] >= ROUNDS_TO_WIN_MATCH) {
    state.matchFinished = true;
    state.matchWinnerUserId = winnerUserId;
    state.matchFinishCause = MATCH_FINISH_CAUSE_BO3;
    state.matchFinishedAtUnixMs = Date.now();
    state.roundResetPending = false;
    state.roundResultHoldUntilTick = -1;
  } else {
    state.roundResetPending = true;
    state.roundResultHoldUntilTick = tick + ROUND_RESULT_HOLD_TICKS;
  }

  broadcastBo3ScoreChanged(
    dispatcher,
    state,
    state.roundNumber,
    winnerUserId,
    tick
  );
  if (state.matchFinished) {
    broadcastMatchResult(dispatcher, state, tick);
  } else if (!allExpectedPlayersConnected(state)) {
    beginRoundBoundaryReconnectWait(state, tick);
  }
}

function finishRoundByHitLimit(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  winnerUserId: string,
  tick: number
): void {
  finishRound(
    dispatcher,
    state,
    winnerUserId,
    ROUND_FINISH_CAUSE_HIT_LIMIT,
    tick
  );
}

function resolveRoundTimeout(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  tick: number
): void {
  if (state.roundFinished || state.roundAwaitingOvertime || state.matchFinished) {
    return;
  }

  const userIds = participantUserIds(state);
  if (userIds.length !== 2) {
    return;
  }

  const firstId = userIds[0];
  const secondId = userIds[1];
  const firstHits = state.roundHitCountByUser[firstId] || 0;
  const secondHits = state.roundHitCountByUser[secondId] || 0;

  if (firstHits > secondHits) {
    finishRound(
      dispatcher,
      state,
      firstId,
      ROUND_FINISH_CAUSE_TIMEOUT,
      tick
    );
    return;
  }

  if (secondHits > firstHits) {
    finishRound(
      dispatcher,
      state,
      secondId,
      ROUND_FINISH_CAUSE_TIMEOUT,
      tick
    );
    return;
  }

  state.roundAwaitingOvertime = true;
  state.roundWinnerUserId = "";
  state.roundFinishCause = ROUND_FINISH_CAUSE_NONE;
  lockRoundCombat(dispatcher, state, tick);
}

function startRoundOvertime(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  tick: number
): void {
  if (!state.roundAwaitingOvertime || state.roundFinished) {
    return;
  }

  state.roundAwaitingOvertime = false;
  state.roundOvertime = true;
  state.roundWinnerUserId = "";
  state.roundFinishCause = ROUND_FINISH_CAUSE_NONE;

  broadcastRoundOvertimeStarted(dispatcher, tick);

  Object.keys(state.combatStateByUser).forEach(function (userId): void {
    const idle = createIdleCombatState(true);
    state.combatStateByUser[userId] = idle;
    broadcastCombatState(dispatcher, userId, idle, tick);
  });
}

function startNextRound(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  tick: number
): void {
  if (!state.roundResetPending || state.matchFinished) {
    return;
  }
  if (!allExpectedPlayersConnected(state)) {
    beginRoundBoundaryReconnectWait(state, tick);
    return;
  }

  state.roundResetPending = false;
  state.roundResultHoldUntilTick = -1;
  state.roundNumber += 1;
  if (state.roundNumber > MAX_ROUNDS) {
    state.matchFinished = true;
    return;
  }

  beginRoundCountdown(dispatcher, state, tick);
}

function incrementRoundHitCount(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  userId: string,
  tick: number,
  inputSequence: number
): void {
  if (state.roundFinished || state.roundAwaitingOvertime || state.matchFinished) {
    return;
  }
  state.roundHitCountByUser[userId] = (state.roundHitCountByUser[userId] || 0) + 1;
  broadcastRoundHitCount(dispatcher, state, userId, tick, inputSequence);

  if (state.roundOvertime) {
    finishRound(
      dispatcher,
      state,
      userId,
      ROUND_FINISH_CAUSE_OVERTIME_HIT,
      tick
    );
    return;
  }

  if (roundReachedHitLimit(state.roundHitCountByUser[userId])) {
    finishRoundByHitLimit(dispatcher, state, userId, tick);
  }
}

function isSupportedCharacterId(characterId: string): boolean {
  return characterId === CHARACTER_LONG_TEST || characterId === CHARACTER_SHORT_TEST;
}

function isShortCharacter(state: AhogeRankedMatchState, userId: string): boolean {
  return state.characterIdByUser[userId] === CHARACTER_SHORT_TEST;
}

function preserveRegrow(source: AuthoritativeCombatState, target: AuthoritativeCombatState): AuthoritativeCombatState {
  target.regrowEndTick = source.regrowEndTick;
  return target;
}

function findOpponentUserId(
  state: AhogeRankedMatchState,
  attackerId: string
): string {
  const userIds = participantUserIds(state);
  for (let index = 0; index < userIds.length; index += 1) {
    if (userIds[index] !== attackerId) {
      return userIds[index];
    }
  }
  return "";
}

function resolveDefenseResult(
  state: AhogeRankedMatchState,
  defenderId: string,
  tick: number
): string {
  // 切断中は新規防御入力不能かつ無防備扱い。切断前にPARRY/DODGE中でも防御成立させない。
  if (!state.presences[defenderId]) {
    return DEFENSE_RESULT_NONE;
  }

  const defenderState = state.combatStateByUser[defenderId];
  if (!defenderState) {
    return DEFENSE_RESULT_NONE;
  }

  if (
    defenderState.state !== COMBAT_STATE_PARRY &&
    defenderState.state !== COMBAT_STATE_DODGE
  ) {
    return DEFENSE_RESULT_NONE;
  }

  if (
    tick < defenderState.defenseStartTick ||
    tick >= defenderState.defenseEndTick
  ) {
    return DEFENSE_RESULT_NONE;
  }

  const isJust = tick < defenderState.defenseJustUntilTick;
  if (defenderState.state === COMBAT_STATE_PARRY) {
    return isJust ? DEFENSE_RESULT_JUST_PARRY : DEFENSE_RESULT_PARRY;
  }

  return isJust ? DEFENSE_RESULT_JUST_DODGE : DEFENSE_RESULT_DODGE;
}

function broadcastDefenseResolved(
  dispatcher: nkruntime.MatchDispatcher,
  attackerId: string,
  defenderId: string,
  combatState: AuthoritativeCombatState,
  tick: number,
  result: string
): void {
  dispatcher.broadcastMessage(
    DEFENSE_RESOLVED_OPCODE,
    JSON.stringify({
      attacker_id: attackerId,
      defender_id: defenderId,
      server_tick: tick,
      input_sequence: combatState.releaseSequence,
      result: result
    }),
    null,
    null,
    true
  );
}

function broadcastContactReached(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  attackerId: string,
  combatState: AuthoritativeCombatState,
  contactTick: number
): string {
  const defenderId = findOpponentUserId(state, attackerId);
  if (!defenderId) {
    return DEFENSE_RESULT_NONE;
  }

  const defenseResult = resolveDefenseResult(state, defenderId, contactTick);

  dispatcher.broadcastMessage(
    CONTACT_REACHED_OPCODE,
    JSON.stringify({
      attacker_id: attackerId,
      defender_id: defenderId,
      server_tick: contactTick,
      input_sequence: combatState.releaseSequence,
      charge_ratio: combatState.chargeRatio
    }),
    null,
    null,
    true
  );

  broadcastDefenseResolved(
    dispatcher,
    attackerId,
    defenderId,
    combatState,
    contactTick,
    defenseResult
  );

  return defenseResult;
}

function broadcastHitConfirmed(
  dispatcher: nkruntime.MatchDispatcher,
  attackerId: string,
  defenderId: string,
  combatState: AuthoritativeCombatState,
  contactTick: number
): void {
  dispatcher.broadcastMessage(
    HIT_CONFIRMED_OPCODE,
    JSON.stringify({attacker_id: attackerId, defender_id: defenderId, server_tick: contactTick, input_sequence: combatState.releaseSequence}),
    null,
    null,
    true
  );
}

function broadcastAttackClash(
  dispatcher: nkruntime.MatchDispatcher,
  attackerAId: string,
  attackerAState: AuthoritativeCombatState,
  attackerBId: string,
  attackerBState: AuthoritativeCombatState,
  tick: number
): void {
  dispatcher.broadcastMessage(
    ATTACK_CLASH_OPCODE,
    JSON.stringify({attacker_a_id: attackerAId, attacker_b_id: attackerBId, attacker_a_input_sequence: attackerAState.releaseSequence, attacker_b_input_sequence: attackerBState.releaseSequence, server_tick: tick}),
    null,
    null,
    true
  );
}

function applyStagger(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  userId: string,
  tick: number
): void {
  const current = state.combatStateByUser[userId];
  if (!current) {
    return;
  }

  const staggered = preserveRegrow(current, createIdleCombatState(current.ahogeAvailable));
  staggered.state = COMBAT_STATE_STAGGER;
  staggered.staggerEndTick = tick + combatStaggerTicks();
  state.combatStateByUser[userId] = staggered;
  broadcastCombatState(dispatcher, userId, staggered, tick);
}

function hasPendingContact(combatState: AuthoritativeCombatState | undefined): boolean {
  return !!combatState && combatState.contactTick >= 0 && !combatState.contactEmitted;
}

function resolveDueContacts(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  tick: number
): void {
  if (state.roundFinished || state.roundAwaitingOvertime || state.matchFinished) {
    return;
  }
  const userIds = participantUserIds(state);
  if (userIds.length !== 2) return;
  const firstId = userIds[0];
  const secondId = userIds[1];
  const first = state.combatStateByUser[firstId];
  const second = state.combatStateByUser[secondId];

  if (hasPendingContact(first) && hasPendingContact(second)) {
    const contactDifference = Math.abs(first.contactTick - second.contactTick);
    if (contactDifference <= combatAttackClashWindowTicks()) {
      const clashTick = Math.max(first.contactTick, second.contactTick);
      if (tick < clashTick) return;
      first.contactEmitted = true;
      second.contactEmitted = true;
      broadcastContactReached(dispatcher, state, firstId, first, first.contactTick);
      broadcastContactReached(dispatcher, state, secondId, second, second.contactTick);
      broadcastAttackClash(dispatcher, firstId, first, secondId, second, tick);
      applyStagger(dispatcher, state, firstId, tick);
      applyStagger(dispatcher, state, secondId, tick);
      return;
    }
  }

  userIds.forEach(function (attackerId): void {
    if (state.roundFinished || state.roundAwaitingOvertime || state.roundCountdownActive || state.matchFinished) {
      return;
    }
    const combatState = state.combatStateByUser[attackerId];
    if (!hasPendingContact(combatState) || tick < combatState.contactTick) return;
    const defenderId = findOpponentUserId(state, attackerId);
    if (!defenderId) return;
    combatState.contactEmitted = true;
    const defenseResult = broadcastContactReached(dispatcher, state, attackerId, combatState, combatState.contactTick);
    if (defenseResult === DEFENSE_RESULT_NONE) {
      broadcastHitConfirmed(dispatcher, attackerId, defenderId, combatState, combatState.contactTick);
      incrementRoundHitCount(
        dispatcher,
        state,
        attackerId,
        combatState.contactTick,
        combatState.releaseSequence
      );
    } else if (
      defenseResult === DEFENSE_RESULT_JUST_PARRY ||
      defenseResult === DEFENSE_RESULT_JUST_DODGE
    ) {
      applyStagger(dispatcher, state, attackerId, tick);
    }
  });
}

function applyAttackInput(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  userId: string,
  action: string,
  sequence: number,
  tick: number
): void {
  if (state.roundFinished || state.roundAwaitingOvertime || state.matchFinished) {
    return;
  }
  const combatState = state.combatStateByUser[userId];
  if (!combatState) {
    return;
  }

  if (action === "ATTACK_PRESS") {
    if (combatState.state !== COMBAT_STATE_IDLE) {
      return;
    }

    state.combatStateByUser[userId] = {
      state: COMBAT_STATE_CHARGING,
      ahogeAvailable: combatState.ahogeAvailable,
      chargeStartTick: tick,
      chargeRatio: 0,
      strikeStartTick: -1,
      contactTick: -1,
      strikeEndTick: -1,
      cooldownEndTick: -1,
      contactEmitted: false,
      releaseSequence: 0,
      defenseStartTick: -1,
      defenseEndTick: -1,
      defenseJustUntilTick: -1,
      resumeState: COMBAT_STATE_IDLE,
      resumeRemainingTicks: 0,
      staggerEndTick: -1,
      regrowEndTick: combatState.regrowEndTick
    };
    broadcastCombatState(
      dispatcher,
      userId,
      state.combatStateByUser[userId],
      tick
    );
    return;
  }

  if (action !== "ATTACK_RELEASE" || combatState.state !== COMBAT_STATE_CHARGING) {
    return;
  }

  const chargeRatio = combatChargeRatio(combatState.chargeStartTick, tick);
  const timing = combatAttackTiming(chargeRatio);
  const strikeStartTick = tick + timing.windupTicks;
  const strikeEndTick = strikeStartTick + timing.strikeTicks;

  state.combatStateByUser[userId] = {
    state: COMBAT_STATE_WINDUP,
    ahogeAvailable: combatState.ahogeAvailable,
    chargeStartTick: combatState.chargeStartTick,
    chargeRatio: chargeRatio,
    strikeStartTick: strikeStartTick,
    contactTick: strikeStartTick + timing.contactOffsetTicks,
    strikeEndTick: strikeEndTick,
    cooldownEndTick: strikeEndTick + timing.cooldownTicks,
    contactEmitted: false,
    releaseSequence: sequence,
    defenseStartTick: -1,
    defenseEndTick: -1,
    defenseJustUntilTick: -1,
    resumeState: COMBAT_STATE_IDLE,
    resumeRemainingTicks: 0,
    staggerEndTick: -1,
    regrowEndTick: combatState.regrowEndTick
  };
  broadcastCombatState(
    dispatcher,
    userId,
    state.combatStateByUser[userId],
    tick
  );
}

function applyDefenseInput(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  userId: string,
  tick: number
): void {
  if (state.roundFinished || state.roundAwaitingOvertime || state.matchFinished) {
    return;
  }
  const combatState = state.combatStateByUser[userId];
  if (!combatState || combatState.state === COMBAT_STATE_STAGGER) {
    return;
  }

  let resumeState = COMBAT_STATE_IDLE;
  let resumeRemainingTicks = 0;
  let preservedChargeRatio = 0;
  let preservedReleaseSequence = 0;

  if (combatState.state === COMBAT_STATE_COOLDOWN) {
    resumeState = COMBAT_STATE_COOLDOWN;
    resumeRemainingTicks = Math.max(0, combatState.cooldownEndTick - tick);
    preservedChargeRatio = combatState.chargeRatio;
    preservedReleaseSequence = combatState.releaseSequence;
  }

  const timing = combatDefenseTiming(combatState.ahogeAvailable);
  state.combatStateByUser[userId] = {
    state: combatState.ahogeAvailable ? COMBAT_STATE_PARRY : COMBAT_STATE_DODGE,
    ahogeAvailable: combatState.ahogeAvailable,
    chargeStartTick: -1,
    chargeRatio: preservedChargeRatio,
    strikeStartTick: -1,
    contactTick: -1,
    strikeEndTick: -1,
    cooldownEndTick: -1,
    contactEmitted: false,
    releaseSequence: preservedReleaseSequence,
    defenseStartTick: tick,
    defenseEndTick: tick + timing.activeTicks,
    defenseJustUntilTick: tick + timing.justTicks,
    resumeState: resumeState,
    resumeRemainingTicks: resumeRemainingTicks,
    staggerEndTick: -1,
    regrowEndTick: combatState.regrowEndTick
  };

  broadcastCombatState(
    dispatcher,
    userId,
    state.combatStateByUser[userId],
    tick
  );
}

function advanceCombatStates(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  tick: number
): void {
  if (state.roundFinished || state.roundAwaitingOvertime || state.roundCountdownActive || state.matchFinished) {
    return;
  }
  Object.keys(state.combatStateByUser).forEach(function (userId): void {
    const combatState = state.combatStateByUser[userId];

    if (!combatState.ahogeAvailable && combatState.regrowEndTick >= 0 && tick >= combatState.regrowEndTick) {
      combatState.ahogeAvailable = true;
      combatState.regrowEndTick = -1;
      broadcastCombatState(dispatcher, userId, combatState, tick);
    }

    if (combatState.state === COMBAT_STATE_STAGGER) {
      if (tick >= combatState.staggerEndTick) {
        state.combatStateByUser[userId] = preserveRegrow(combatState, createIdleCombatState(combatState.ahogeAvailable));
        broadcastCombatState(dispatcher, userId, state.combatStateByUser[userId], tick);
      }
      return;
    }

    if (
      (combatState.state === COMBAT_STATE_PARRY ||
        combatState.state === COMBAT_STATE_DODGE) &&
      tick >= combatState.defenseEndTick
    ) {
      if (
        combatState.resumeState === COMBAT_STATE_COOLDOWN &&
        combatState.resumeRemainingTicks > 0
      ) {
        const resumed = preserveRegrow(combatState, createIdleCombatState(combatState.ahogeAvailable));
        resumed.state = COMBAT_STATE_COOLDOWN;
        resumed.chargeRatio = combatState.chargeRatio;
        resumed.releaseSequence = combatState.releaseSequence;
        resumed.cooldownEndTick = tick + combatState.resumeRemainingTicks;
        state.combatStateByUser[userId] = resumed;
      } else {
        state.combatStateByUser[userId] = preserveRegrow(
          combatState,
          createIdleCombatState(combatState.ahogeAvailable)
        );
      }

      broadcastCombatState(
        dispatcher,
        userId,
        state.combatStateByUser[userId],
        tick
      );
      return;
    }

    if (
      combatState.state === COMBAT_STATE_WINDUP &&
      tick >= combatState.strikeStartTick
    ) {
      combatState.state = COMBAT_STATE_STRIKE;
      if (isShortCharacter(state, userId)) {
        combatState.ahogeAvailable = false;
        combatState.regrowEndTick = tick + combatShortAhogeRegrowTicks();
      }
      broadcastCombatState(dispatcher, userId, combatState, tick);
    }

    if (combatState.state === COMBAT_STATE_STRIKE) {
      if (tick >= combatState.strikeEndTick) {
        combatState.state = COMBAT_STATE_COOLDOWN;
        broadcastCombatState(dispatcher, userId, combatState, tick);
      }
    }

    if (
      combatState.state === COMBAT_STATE_COOLDOWN &&
      tick >= combatState.cooldownEndTick
    ) {
      state.combatStateByUser[userId] = createIdleCombatState(
        combatState.ahogeAvailable
      );
      broadcastCombatState(
        dispatcher,
        userId,
        state.combatStateByUser[userId],
        tick
      );
    }
  });

  resolveDueContacts(dispatcher, state, tick);
}

function settleRankedRatingIfNeeded(
  nk: nkruntime.Nakama,
  logger: nkruntime.Logger,
  state: AhogeRankedMatchState,
  tick: number
): void {
  if (!state.matchFinished || state.ratingSettlementDone) {
    return;
  }
  if (tick < state.ratingSettlementRetryTick) {
    return;
  }

  const loserUserId = findOpponentUserId(state, state.matchWinnerUserId);
  if (!loserUserId) {
    state.ratingSettlementRetryTick = tick + AUTHORITATIVE_MATCH_TICK_RATE;
    return;
  }

  const settled = settleRankedMatchRating(
    nk,
    logger,
    state.matchId,
    state.matchMode,
    state.matchWinnerUserId,
    loserUserId,
    state.characterIdByUser,
    state.matchFinishCause,
    state.matchFinishedAtUnixMs >= 0 ? state.matchFinishedAtUnixMs : Date.now()
  );

  if (settled) {
    state.ratingSettlementDone = true;
    return;
  }

  state.ratingSettlementRetryTick = tick + AUTHORITATIVE_MATCH_TICK_RATE;
}


function persistActiveMatchResultIfNeeded(
  nk: nkruntime.Nakama,
  state: AhogeRankedMatchState,
  tick: number
): void {
  if (!state.matchFinished || state.activeMatchResultPersisted) {
    return;
  }
  if (tick < state.activeMatchResultRetryTick) {
    return;
  }

  const snapshot = {
    server_tick: tick,
    match_mode: state.matchMode,
    round_number: state.roundNumber,
    round_wins_by_user: roundWinsSnapshot(state),
    round_hit_count_by_user: state.roundHitCountByUser,
    remaining_seconds: state.roundRemainingSeconds,
    round_finished: state.roundFinished,
    round_winner_user_id: state.roundWinnerUserId,
    round_finish_cause: state.roundFinishCause,
    round_awaiting_overtime: state.roundAwaitingOvertime,
    round_overtime: state.roundOvertime,
    round_countdown_active: state.roundCountdownActive,
    round_countdown_value: state.roundCountdownValue,
    match_finished: true,
    match_winner_user_id: state.matchWinnerUserId,
    match_finish_cause: state.matchFinishCause,
    character_id_by_user: state.characterIdByUser
  };

  const persisted = markActiveOnlineMatchResult(
    nk,
    participantUserIds(state),
    state.matchId,
    state.matchMode,
    snapshot,
    Date.now()
  );
  if (persisted) {
    state.activeMatchResultPersisted = true;
    return;
  }

  state.activeMatchResultRetryTick =
    tick + AUTHORITATIVE_MATCH_TICK_RATE;
}

function settleFriendRoomIfNeeded(
  nk: nkruntime.Nakama,
  state: AhogeRankedMatchState,
  tick: number
): void {
  if (
    state.matchMode !== "friend" ||
    !state.matchFinished ||
    state.friendRoomSettlementDone
  ) {
    return;
  }
  if (tick < state.friendRoomSettlementRetryTick) {
    return;
  }

  const settled = markFriendRoomMatchFinished(
    nk,
    state.friendRoomCode,
    state.matchId,
    state.friendMatchGeneration
  );
  if (settled) {
    state.friendRoomSettlementDone = true;
    return;
  }

  state.friendRoomSettlementRetryTick =
    tick + AUTHORITATIVE_MATCH_TICK_RATE;
}


function resolveReconnectTimeout(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  tick: number
): void {
  if (state.matchFinished) {
    return;
  }

  const expiredUserIds = Object.keys(state.reconnectDeadlineTickByUser).filter(
    function (userId): boolean {
      return tick >= state.reconnectDeadlineTickByUser[userId];
    }
  );

  // 両者同時切断は別契約で扱うため、ここでは片側timeoutだけを勝敗確定する。
  if (expiredUserIds.length !== 1) {
    return;
  }

  const loserUserId = expiredUserIds[0];
  let winnerUserId = "";
  const participantIds = participantUserIds(state);
  for (let index = 0; index < participantIds.length; index += 1) {
    const userId = participantIds[index];
    if (userId !== loserUserId && state.presences[userId]) {
      winnerUserId = userId;
      break;
    }
  }

  if (!winnerUserId) {
    return;
  }

  state.matchFinished = true;
  state.matchWinnerUserId = winnerUserId;
  state.matchFinishCause = MATCH_FINISH_CAUSE_DISCONNECT_TIMEOUT;
  state.matchFinishedAtUnixMs = Date.now();
  state.roundResetPending = false;
  state.roundCountdownActive = false;
  state.roundBoundaryPauseStartTick = -1;

  delete state.reconnectDeadlineTickByUser[loserUserId];

  lockRoundCombat(dispatcher, state, tick);
  broadcastMatchResult(dispatcher, state, tick);
}

const rankedMatchLoop: nkruntime.MatchLoopFunction<AhogeRankedMatchState> = function (
  _ctx,
  logger,
  nk,
  dispatcher,
  tick,
  state,
  messages
) {
  resolveReconnectTimeout(dispatcher, state, tick);
  settleRankedRatingIfNeeded(nk, logger, state, tick);
  settleFriendRoomIfNeeded(nk, state, tick);
  persistActiveMatchResultIfNeeded(nk, state, tick);

  if (
    state.roundResetPending &&
    !state.matchFinished &&
    allExpectedPlayersConnected(state) &&
    state.roundBoundaryPauseStartTick < 0 &&
    tick >= state.roundResultHoldUntilTick
  ) {
    startNextRound(dispatcher, state, tick);
  }

  if (
    allExpectedPlayersConnected(state) &&
    state.roundTimerStartTick < 0 &&
    !state.roundCountdownActive &&
    state.roundNumber === 1
  ) {
    beginRoundCountdown(dispatcher, state, tick);
  }

  if (state.roundCountdownActive && allExpectedPlayersConnected(state)) {
    advanceRoundCountdown(dispatcher, state, tick);
  }

  if (state.roundAwaitingOvertime) {
    startRoundOvertime(dispatcher, state, tick);
  }

  if (
    !state.roundFinished &&
    !state.roundAwaitingOvertime &&
    state.roundTimerStartTick >= 0 &&
    state.roundRemainingSeconds > 0
  ) {
    const remainingSeconds = roundRemainingSeconds(state.roundTimerEndTick, tick);
    if (remainingSeconds !== state.roundRemainingSeconds) {
      state.roundRemainingSeconds = remainingSeconds;
      broadcastRoundTimer(dispatcher, remainingSeconds, tick);
      if (remainingSeconds === 0) {
        resolveRoundTimeout(dispatcher, state, tick);
      }
    }
  }

  if (
    allExpectedPlayersConnected(state) &&
    !state.roundHitCountSnapshotBroadcast
  ) {
    participantUserIds(state).forEach(function (userId): void {
      broadcastRoundHitCount(dispatcher, state, userId, tick, 0);
    });
    state.roundHitCountSnapshotBroadcast = true;
  }


  messages.forEach(function (message): void {
    if (state.roundFinished || state.roundAwaitingOvertime || state.roundCountdownActive || state.matchFinished) {
      return;
    }
    if (message.opCode !== COMBAT_INPUT_OPCODE) {
      return;
    }

    const userId = message.sender.userId;
    if (!state.presences[userId]) {
      return;
    }

    if (state.lastAcceptedTickByUser[userId] === tick) {
      return;
    }

    let payload: any;
    try {
      payload = JSON.parse(nk.binaryToString(message.data));
    } catch (_error) {
      return;
    }

    const sequence = payload.input_sequence;
    const action = String(payload.action || "");

    if (
      typeof sequence !== "number" ||
      !isFinite(sequence) ||
      Math.floor(sequence) !== sequence ||
      sequence <= 0
    ) {
      return;
    }

    if (!ALLOWED_COMBAT_ACTIONS[action]) {
      return;
    }

    const lastSequence = state.lastInputSequenceByUser[userId] || 0;
    if (sequence <= lastSequence) {
      return;
    }

    state.lastInputSequenceByUser[userId] = sequence;
    state.lastAcceptedTickByUser[userId] = tick;

    dispatcher.broadcastMessage(
      INPUT_ACCEPTED_OPCODE,
      JSON.stringify({
        user_id: userId,
        input_sequence: sequence,
        action: action,
        server_tick: tick
      }),
      null,
      message.sender,
      true
    );

    if (action === "DEFEND") {
      applyDefenseInput(dispatcher, state, userId, tick);
    } else {
      applyAttackInput(dispatcher, state, userId, action, sequence, tick);
    }
  });

  // 同一tickで受理した入力を、そのtickのContact/Defense判定へ先に反映する。
  // Defense開始tickをactiveに含む設計のため、state advanceは入力処理後に行う。
  advanceCombatStates(dispatcher, state, tick);

  return {state: state};
};

const rankedMatchTerminate: nkruntime.MatchTerminateFunction<AhogeRankedMatchState> = function (
  _ctx,
  _logger,
  _nk,
  _dispatcher,
  _tick,
  state,
  _graceSeconds
) {
  return {state: state};
};

const rankedMatchSignal: nkruntime.MatchSignalFunction<AhogeRankedMatchState> = function (
  _ctx,
  _logger,
  _nk,
  _dispatcher,
  _tick,
  state,
  _data
) {
  return {state: state};
};

const rankedMatchHandler: nkruntime.MatchHandler<AhogeRankedMatchState> = {
  matchInit: rankedMatchInit,
  matchJoinAttempt: rankedMatchJoinAttempt,
  matchJoin: rankedMatchJoin,
  matchLeave: rankedMatchLeave,
  matchLoop: rankedMatchLoop,
  matchTerminate: rankedMatchTerminate,
  matchSignal: rankedMatchSignal
};

const rankedMatchmakerMatched: nkruntime.MatchmakerMatchedFunction = function (
  _ctx,
  logger,
  nk,
  matches
): string | void {
  if (matches.length !== 2) {
    logger.warn("ahoge ranked matchmaker expected exactly 2 users, got %d.", matches.length);
    return;
  }

  if (
    matches[0].properties.mode !== "ranked" ||
    matches[1].properties.mode !== "ranked"
  ) {
    logger.warn("ahoge ranked matchmaker received non-ranked users.");
    return;
  }

  const expectedUserIds = [matches[0].presence.userId, matches[1].presence.userId];
  for (let index = 0; index < expectedUserIds.length; index += 1) {
    if (resolveActiveOnlineMatchForUser(nk, expectedUserIds[index])) {
      logger.warn("ahoge ranked matchmaker rejected unresolved online match.");
      return;
    }
  }

  const characterIds: {[key: string]: string} = {};
  for (let index = 0; index < matches.length; index += 1) {
    const userId = matches[index].presence.userId;
    const characterId = String(matches[index].properties.character_id || "");
    if (!isSupportedCharacterId(characterId)) {
      logger.warn("ahoge ranked matchmaker received unsupported character_id.");
      return;
    }
    characterIds[userId] = characterId;
  }

  const matchId = nk.matchCreate("ahoge_ranked", {
    matchMode: "ranked",
    expectedUserIds: expectedUserIds,
    characterIds: characterIds
  });

  logger.info("ahoge ranked authoritative match created.");
  return matchId;
};
