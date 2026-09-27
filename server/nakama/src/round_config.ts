const ROUND_DURATION_SECONDS = 85;

function roundDurationTicks(): number {
  return ROUND_DURATION_SECONDS * AUTHORITATIVE_MATCH_TICK_RATE;
}

function roundRemainingSeconds(roundEndTick: number, tick: number): number {
  const remainingTicks = Math.max(0, roundEndTick - tick);
  return Math.ceil(remainingTicks / AUTHORITATIVE_MATCH_TICK_RATE);
}
