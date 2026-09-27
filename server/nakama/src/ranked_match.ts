const COMBAT_INPUT_OPCODE = 1;
const INPUT_ACCEPTED_OPCODE = 101;
const COMBAT_STATE_CHANGED_OPCODE = 102;
const CONTACT_REACHED_OPCODE = 103;
const DEFENSE_RESOLVED_OPCODE = 104;
const HIT_CONFIRMED_OPCODE = 105;
const ATTACK_CLASH_OPCODE = 106;

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
}

interface AhogeRankedMatchState {
  expectedUserIds: {[key: string]: boolean};
  presences: {[key: string]: nkruntime.Presence};
  lastInputSequenceByUser: {[key: string]: number};
  lastAcceptedTickByUser: {[key: string]: number};
  combatStateByUser: {[key: string]: AuthoritativeCombatState};
}

const rankedMatchInit: nkruntime.MatchInitFunction<AhogeRankedMatchState> = function (
  _ctx,
  logger,
  _nk,
  params
) {
  const expectedUserIds: {[key: string]: boolean} = {};
  const rawExpected = params.expectedUserIds;

  if (Array.isArray(rawExpected)) {
    rawExpected.forEach(function (userId: any): void {
      const id = String(userId);
      if (id) {
        expectedUserIds[id] = true;
      }
    });
  }

  logger.info("ahoge_ranked authoritative match initialized.");

  return {
    state: {
      expectedUserIds: expectedUserIds,
      presences: {},
      lastInputSequenceByUser: {},
      lastAcceptedTickByUser: {},
      combatStateByUser: {}
    },
    tickRate: AUTHORITATIVE_MATCH_TICK_RATE,
    label: JSON.stringify({
      mode: "ranked",
      phase: "waiting"
    })
  };
};

const rankedMatchJoinAttempt: nkruntime.MatchJoinAttemptFunction<AhogeRankedMatchState> = function (
  _ctx,
  _logger,
  _nk,
  _dispatcher,
  _tick,
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
  _dispatcher,
  _tick,
  state,
  presences
) {
  presences.forEach(function (presence): void {
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
  });
  logger.info("ahoge_ranked player joined. size=%d", Object.keys(state.presences).length);
  return {state: state};
};

const rankedMatchLeave: nkruntime.MatchLeaveFunction<AhogeRankedMatchState> = function (
  _ctx,
  logger,
  _nk,
  _dispatcher,
  _tick,
  state,
  presences
) {
  presences.forEach(function (presence): void {
    delete state.presences[presence.userId];
    delete state.lastInputSequenceByUser[presence.userId];
    delete state.lastAcceptedTickByUser[presence.userId];
    delete state.combatStateByUser[presence.userId];
  });
  logger.info("ahoge_ranked player left. size=%d", Object.keys(state.presences).length);
  return {state: state};
};

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
    resumeRemainingTicks: 0
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
      defense_just_until_tick: combatState.defenseJustUntilTick
    }),
    null,
    null,
    true
  );
}

function findOpponentUserId(
  state: AhogeRankedMatchState,
  attackerId: string
): string {
  const userIds = Object.keys(state.presences);
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

function hasPendingContact(combatState: AuthoritativeCombatState | undefined): boolean {
  return !!combatState && combatState.contactTick >= 0 && !combatState.contactEmitted;
}

function resolveDueContacts(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  tick: number
): void {
  const userIds = Object.keys(state.presences);
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
      return;
    }
  }

  userIds.forEach(function (attackerId): void {
    const combatState = state.combatStateByUser[attackerId];
    if (!hasPendingContact(combatState) || tick < combatState.contactTick) return;
    const defenderId = findOpponentUserId(state, attackerId);
    if (!defenderId) return;
    combatState.contactEmitted = true;
    const defenseResult = broadcastContactReached(dispatcher, state, attackerId, combatState, combatState.contactTick);
    if (defenseResult === DEFENSE_RESULT_NONE) {
      broadcastHitConfirmed(dispatcher, attackerId, defenderId, combatState, combatState.contactTick);
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
      defenseEndTick: -1,
      defenseJustUntilTick: -1,
      resumeState: COMBAT_STATE_IDLE,
      resumeRemainingTicks: 0
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
    resumeRemainingTicks: 0
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
  const combatState = state.combatStateByUser[userId];
  if (!combatState) {
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
    resumeRemainingTicks: resumeRemainingTicks
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
  Object.keys(state.combatStateByUser).forEach(function (userId): void {
    const combatState = state.combatStateByUser[userId];

    if (
      (combatState.state === COMBAT_STATE_PARRY ||
        combatState.state === COMBAT_STATE_DODGE) &&
      tick >= combatState.defenseEndTick
    ) {
      if (
        combatState.resumeState === COMBAT_STATE_COOLDOWN &&
        combatState.resumeRemainingTicks > 0
      ) {
        const resumed = createIdleCombatState(combatState.ahogeAvailable);
        resumed.state = COMBAT_STATE_COOLDOWN;
        resumed.chargeRatio = combatState.chargeRatio;
        resumed.releaseSequence = combatState.releaseSequence;
        resumed.cooldownEndTick = tick + combatState.resumeRemainingTicks;
        state.combatStateByUser[userId] = resumed;
      } else {
        state.combatStateByUser[userId] = createIdleCombatState(
          combatState.ahogeAvailable
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

const rankedMatchLoop: nkruntime.MatchLoopFunction<AhogeRankedMatchState> = function (
  _ctx,
  _logger,
  nk,
  dispatcher,
  tick,
  state,
  messages
) {
  messages.forEach(function (message): void {
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

  const expectedUserIds = [
    matches[0].presence.userId,
    matches[1].presence.userId
  ];

  const matchId = nk.matchCreate("ahoge_ranked", {
    expectedUserIds: expectedUserIds
  });

  logger.info("ahoge ranked authoritative match created.");
  return matchId;
};
