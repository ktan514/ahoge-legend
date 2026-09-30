const fs = require("fs");
const vm = require("vm");

const context = {
  console,
  Math,
  Date,
  JSON,
  isFinite
};
vm.createContext(context);
vm.runInContext(
  fs.readFileSync("build/index.js", "utf8"),
  context,
  {filename: "build/index.js"}
);

function evaluate(expression) {
  return vm.runInContext(expression, context);
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

const draw = evaluate("calculateEloOutcome(1700, 1500, 0.5)");
assert(draw.firstDelta + draw.secondDelta === 0, "Player Rating must be zero-sum");
assert(draw.firstDelta < 0, "Higher-rated player must lose Rating on draw");
assert(draw.secondDelta > 0, "Lower-rated player must gain Rating on draw");
assert(evaluate("roundSymmetricRatingDelta(2.5)") === 3, "positive half rounding");
assert(evaluate("roundSymmetricRatingDelta(-2.5)") === -3, "negative half rounding");

const win = evaluate("calculateEloOutcome(1500, 1500, 1)");
assert(win.firstDelta === 16, "Equal-rating winner delta must be +16");
assert(win.secondDelta === -16, "Equal-rating loser delta must be -16");

assert(evaluate("ahogeSamePairWeight(0)") === 1, "first pair match weight");
assert(evaluate("ahogeSamePairWeight(4)") === 1, "fifth pair match weight");
assert(evaluate("ahogeSamePairWeight(5)") === 0.5, "sixth pair match reduced weight");
assert(evaluate("ahogeSamePairWeight(9)") === 0.5, "tenth pair match reduced weight");
assert(evaluate("ahogeSamePairWeight(10)") === 0.25, "eleventh pair match minimum weight");

assert(
  evaluate("clampAhogeDeltaByInfluenceBudget(16, 95, 90)") === 5,
  "positive Ahoge delta must respect smaller remaining influence budget"
);
assert(
  evaluate("clampAhogeDeltaByInfluenceBudget(-16, 95, 99)") === -1,
  "negative Ahoge delta must respect smaller remaining influence budget"
);
assert(
  evaluate("clampAhogeDeltaByInfluenceBudget(16, 100, 0)") === 0,
  "exhausted player-character influence budget must stop Ahoge delta"
);

console.log("AHOGE LEGEND rating model smoke: PASS");


const seasonBoundary = Date.UTC(2026, 9, 1, 0, 0, 0, 0) - 9 * 60 * 60 * 1000;
const previousSeason = "2026-09";
const currentSeason = "2026-10";

const hiddenBeforeEight = evaluate(
  'seasonRankingVisibility("2026-09", ' + (seasonBoundary + 8 * 60 * 60 * 1000 - 1) + ')'
);
assert(hiddenBeforeEight.ranking_public === false, "old season must stay hidden until 08:00 JST");
assert(
  hiddenBeforeEight.ranking_hidden_until_unix_ms === seasonBoundary + 8 * 60 * 60 * 1000,
  "old season hidden-until must be 08:00 JST"
);

const visibleAtEight = evaluate(
  'seasonRankingVisibility("2026-09", ' + (seasonBoundary + 8 * 60 * 60 * 1000) + ')'
);
assert(visibleAtEight.ranking_public === true, "old season must publish at 08:00 JST");

const newSeasonAtMidnight = evaluate(
  'seasonRankingVisibility("2026-10", ' + seasonBoundary + ')'
);
assert(newSeasonAtMidnight.ranking_public === true, "new season must be public at 00:00 JST");

assert(
  evaluate('resolveRankedSettlementSeasonId(' + (seasonBoundary - 1) + ', ' + (seasonBoundary + 9 * 60 * 60 * 1000) + ')') === previousSeason,
  "pre-midnight match must stay in old season regardless of finish time"
);
assert(
  evaluate('resolveRankedSettlementSeasonId(' + seasonBoundary + ', ' + (seasonBoundary + 1000) + ')') === currentSeason,
  "match starting exactly at 00:00 must belong to new season"
);
