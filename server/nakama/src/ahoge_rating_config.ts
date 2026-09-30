// #88 balance tuning values.
// AHOGE_BASE_RATING is a product rule. The other values are development defaults,
// centralized here so balance work can change them without touching calculation logic.
const AHOGE_BASE_RATING = 1500;
const AHOGE_RATING_WEIGHT = 1.0;
const AHOGE_RATING_BASE_K = 32;

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
