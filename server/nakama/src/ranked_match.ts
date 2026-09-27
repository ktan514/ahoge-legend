const COMBAT_INPUT_OPCODE = 1;
const INPUT_ACCEPTED_OPCODE = 101;
const COMBAT_STATE_CHANGED_OPCODE = 102;
const CONTACT_REACHED_OPCODE = 103;

const COMBAT_STATE_IDLE = "IDLE";
const COMBAT_STATE_CHARGING = "CHARGING";
const COMBAT_STATE_WINDUP = "WINDUP";
const COMBAT_STATE_STRIKE = "STRIKE";
const COMBAT_STATE_COOLDOWN = "COOLDOWN";

const ALLOWED_COMBAT_ACTIONS: {[key: string]: boolean} = {
  ATTACK_PRESS: true,
  ATTACK_RELEASE: true,
  DEFEND: true
};

interface AuthoritativeAttackState {
  state: string;
  chargeStartTick: number;
  chargeRatio: number;
  strikeStartTick: number;
  contactTick: number;
  strikeEndTick: number;
  cooldownEndTick: number;
  contactEmitted: boolean;
  releaseSequence: number;
}

interface AhogeRankedMatchState {
  expectedUserIds: {[key: string]: boolean};
  presences: {[key: string]: nkruntime.Presence};
  lastInputSequenceByUser: {[key: string]: number};
  lastAcceptedTickByUser: {[key: string]: number};
  attackStateByUser: {[key: string]: AuthoritativeAttackState};
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
      attackStateByUser: {}
    },
    tickRate: 30,
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
    if (!state.attackStateByUser[presence.userId]) {
      state.attackStateByUser[presence.userId] = createIdleAttackState();
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
    delete state.attackStateByUser[presence.userId];
  });
  logger.info("ahoge_ranked player left. size=%d", Object.keys(state.presences).length);
  return {state: state};
};

function createIdleAttackState(): AuthoritativeAttackState {
  return {
    state: COMBAT_STATE_IDLE,
    chargeStartTick: -1,
    chargeRatio: 0,
    strikeStartTick: -1,
    contactTick: -1,
    strikeEndTick: -1,
    cooldownEndTick: -1,
    contactEmitted: false,
    releaseSequence: 0
  };
}

function broadcastCombatState(
  dispatcher: nkruntime.MatchDispatcher,
  userId: string,
  attackState: AuthoritativeAttackState,
  tick: number
): void {
  dispatcher.broadcastMessage(
    COMBAT_STATE_CHANGED_OPCODE,
    JSON.stringify({
      user_id: userId,
      state: attackState.state,
      server_tick: tick,
      charge_ratio: attackState.chargeRatio
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
  attackState: AuthoritativeAttackState,
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
      input_sequence: attackState.releaseSequence,
      charge_ratio: attackState.chargeRatio
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
  const attackState = state.attackStateByUser[userId];
  if (!attackState) {
    return;
  }

  if (action === "ATTACK_PRESS") {
    if (attackState.state !== COMBAT_STATE_IDLE) {
      return;
    }

    state.attackStateByUser[userId] = {
      state: COMBAT_STATE_CHARGING,
      chargeStartTick: tick,
      chargeRatio: 0,
      strikeStartTick: -1,
      contactTick: -1,
      strikeEndTick: -1,
      cooldownEndTick: -1,
      contactEmitted: false,
      releaseSequence: 0
    };
    broadcastCombatState(
      dispatcher,
      userId,
      state.attackStateByUser[userId],
      tick
    );
    return;
  }

  if (action !== "ATTACK_RELEASE" || attackState.state !== COMBAT_STATE_CHARGING) {
    return;
  }

  const chargeRatio = combatChargeRatio(attackState.chargeStartTick, tick);
  const timing = combatAttackTiming(chargeRatio);
  const strikeStartTick = tick + timing.windupTicks;
  const strikeEndTick = strikeStartTick + timing.strikeTicks;

  state.attackStateByUser[userId] = {
    state: COMBAT_STATE_WINDUP,
    chargeStartTick: attackState.chargeStartTick,
    chargeRatio: chargeRatio,
    strikeStartTick: strikeStartTick,
    contactTick: strikeStartTick + timing.contactOffsetTicks,
    strikeEndTick: strikeEndTick,
    cooldownEndTick: strikeEndTick + timing.cooldownTicks,
    contactEmitted: false,
    releaseSequence: sequence
  };
  broadcastCombatState(
    dispatcher,
    userId,
    state.attackStateByUser[userId],
    tick
  );
}

function advanceAttackStates(
  dispatcher: nkruntime.MatchDispatcher,
  state: AhogeRankedMatchState,
  tick: number
): void {
  Object.keys(state.attackStateByUser).forEach(function (userId): void {
    const attackState = state.attackStateByUser[userId];

    if (
      attackState.state === COMBAT_STATE_WINDUP &&
      tick >= attackState.strikeStartTick
    ) {
      attackState.state = COMBAT_STATE_STRIKE;
      broadcastCombatState(dispatcher, userId, attackState, tick);
    }

    if (attackState.state === COMBAT_STATE_STRIKE) {
      if (!attackState.contactEmitted && tick >= attackState.contactTick) {
        attackState.contactEmitted = true;
        broadcastContactReached(dispatcher, state, userId, attackState, tick);
      }

      if (tick >= attackState.strikeEndTick) {
        attackState.state = COMBAT_STATE_COOLDOWN;
        broadcastCombatState(dispatcher, userId, attackState, tick);
      }
    }

    if (
      attackState.state === COMBAT_STATE_COOLDOWN &&
      tick >= attackState.cooldownEndTick
    ) {
      state.attackStateByUser[userId] = createIdleAttackState();
      broadcastCombatState(
        dispatcher,
        userId,
        state.attackStateByUser[userId],
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
  advanceAttackStates(dispatcher, state, tick);
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

    applyAttackInput(dispatcher, state, userId, action, sequence, tick);
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
