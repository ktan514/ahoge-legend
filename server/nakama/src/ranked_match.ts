const COMBAT_INPUT_OPCODE = 1;
const INPUT_ACCEPTED_OPCODE = 101;
const COMBAT_STATE_CHANGED_OPCODE = 102;
const CONTACT_REACHED_OPCODE = 103;

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

function broadcastContactReached(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  attackerId: string,
  combatState: AuthoritativeCombatState,
  tick: number
): void {
  const defenderId = findOpponentUserId(state, attackerId);
  if (!defenderId) {
    return;
  }

  dispatcher.broadcastMessage(
    CONTACT_REACHED_OPCODE,
    JSON.stringify({
      attacker_id: attackerId,
      defender_id: defenderId,
      server_tick: tick,
      input_sequence: combatState.releaseSequence,
      charge_ratio: combatState.chargeRatio
    }),
    null,
    null,
    true
  );
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
      if (!combatState.contactEmitted && tick >= combatState.contactTick) {
        combatState.contactEmitted = true;
        broadcastContactReached(dispatcher, state, userId, combatState, tick);
      }

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
  advanceCombatStates(dispatcher, state, tick);

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
