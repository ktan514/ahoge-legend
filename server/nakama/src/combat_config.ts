const AUTHORITATIVE_MATCH_TICK_RATE = 30;

const SERVER_COMBAT_CONFIG = {
  normalWindupSeconds: 0.18,
  normalStrikeSeconds: 0.20,
  normalCooldownSeconds: 0.48,
  maxChargeSeconds: 0.60,
  chargedReleaseWindupSeconds: 0.08,
  chargedStrikeSeconds: 0.13,
  chargedCooldownSeconds: 0.82,
  attackContactRatio: 0.70
};

interface ServerAttackTiming {
  windupTicks: number;
  strikeTicks: number;
  cooldownTicks: number;
  contactOffsetTicks: number;
}

function combatClamp01(value: number): number {
  return Math.max(0, Math.min(1, value));
}

function combatLerp(fromValue: number, toValue: number, ratio: number): number {
  const clamped = combatClamp01(ratio);
  return fromValue + (toValue - fromValue) * clamped;
}

function combatSecondsToTicks(seconds: number): number {
  return Math.max(1, Math.ceil(seconds * AUTHORITATIVE_MATCH_TICK_RATE));
}

function combatMaxChargeTicks(): number {
  return combatSecondsToTicks(SERVER_COMBAT_CONFIG.maxChargeSeconds);
}

function combatChargeRatio(chargeStartTick: number, releaseTick: number): number {
  const elapsedTicks = Math.max(0, releaseTick - chargeStartTick);
  return combatClamp01(elapsedTicks / combatMaxChargeTicks());
}

function combatAttackTiming(chargeRatio: number): ServerAttackTiming {
  const ratio = combatClamp01(chargeRatio);
  const windupSeconds = combatLerp(
    SERVER_COMBAT_CONFIG.normalWindupSeconds,
    SERVER_COMBAT_CONFIG.chargedReleaseWindupSeconds,
    ratio
  );
  const strikeSeconds = combatLerp(
    SERVER_COMBAT_CONFIG.normalStrikeSeconds,
    SERVER_COMBAT_CONFIG.chargedStrikeSeconds,
    ratio
  );
  const cooldownSeconds = combatLerp(
    SERVER_COMBAT_CONFIG.normalCooldownSeconds,
    SERVER_COMBAT_CONFIG.chargedCooldownSeconds,
    ratio
  );

  return {
    windupTicks: combatSecondsToTicks(windupSeconds),
    strikeTicks: combatSecondsToTicks(strikeSeconds),
    cooldownTicks: combatSecondsToTicks(cooldownSeconds),
    contactOffsetTicks: Math.max(
      1,
      Math.ceil(
        strikeSeconds *
        SERVER_COMBAT_CONFIG.attackContactRatio *
        AUTHORITATIVE_MATCH_TICK_RATE
      )
    )
  };
}
