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
