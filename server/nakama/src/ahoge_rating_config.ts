// #88 balance / abuse tuning values.
// AHOGE_BASE_RATING is a product rule. The other values are development defaults,
// centralized here so balance and abuse controls can change without touching settlement logic.
const AHOGE_BASE_RATING = 1500;
const AHOGE_RATING_WEIGHT = 1.0;
const AHOGE_RATING_BASE_K = 32;

const AHOGE_PLAYER_CHARACTER_ABSOLUTE_INFLUENCE_CAP = 100;
const AHOGE_SAME_PAIR_FULL_WEIGHT_MATCHES = 5;
const AHOGE_SAME_PAIR_REDUCED_WEIGHT_MATCHES = 10;
const AHOGE_SAME_PAIR_REDUCED_WEIGHT = 0.5;
const AHOGE_SAME_PAIR_MIN_WEIGHT = 0.25;
const AHOGE_NO_ACTIVITY_WEIGHT = 0.0;

interface AhogeKStage {
  min_match_count: number;
  k: number;
}

// Balance validation may add stages such as lower K values for mature samples.
// Empty by default means no automatic K shrink is finalized yet.
const AHOGE_RATING_K_STAGES: AhogeKStage[] = [];

function ahogeKForMatchCounts(
  firstMatchCount: number,
  secondMatchCount: number
): number {
  const sampleCount = Math.max(
    0,
    Math.min(
      Math.floor(firstMatchCount),
      Math.floor(secondMatchCount)
    )
  );
  let k = AHOGE_RATING_BASE_K;

  AHOGE_RATING_K_STAGES.forEach(function (stage): void {
    if (
      isFinite(stage.min_match_count) &&
      isFinite(stage.k) &&
      stage.min_match_count >= 0 &&
      stage.k > 0 &&
      sampleCount >= Math.floor(stage.min_match_count)
    ) {
      k = stage.k;
    }
  });

  return k;
}

function ahogeSamePairWeight(matchCountBefore: number): number {
  const count = Math.max(0, Math.floor(matchCountBefore));
  if (count < AHOGE_SAME_PAIR_FULL_WEIGHT_MATCHES) {
    return 1.0;
  }
  if (count < AHOGE_SAME_PAIR_REDUCED_WEIGHT_MATCHES) {
    return AHOGE_SAME_PAIR_REDUCED_WEIGHT;
  }
  return AHOGE_SAME_PAIR_MIN_WEIGHT;
}

function roundSymmetricRatingDelta(value: number): number {
  if (!isFinite(value)) {
    throw new Error("invalid rating delta");
  }
  if (value < 0) {
    return -Math.round(Math.abs(value));
  }
  return Math.round(value);
}
