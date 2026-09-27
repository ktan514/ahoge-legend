const COMBAT_INPUT_OPCODE = 1;
const INPUT_ACCEPTED_OPCODE = 101;

const ALLOWED_COMBAT_ACTIONS: {[key: string]: boolean} = {
  ATTACK_PRESS: true,
  ATTACK_RELEASE: true,
  DEFEND: true
};

interface AhogeRankedMatchState {
  expectedUserIds: {[key: string]: boolean};
  presences: {[key: string]: nkruntime.Presence};
  lastInputSequenceByUser: {[key: string]: number};
  lastAcceptedTickByUser: {[key: string]: number};
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
      lastAcceptedTickByUser: {}
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
  });
  logger.info("ahoge_ranked player left. size=%d", Object.keys(state.presences).length);
  return {state: state};
};

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
