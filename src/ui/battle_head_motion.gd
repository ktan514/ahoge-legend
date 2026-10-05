extends RefCounted

# X=前方px、Y=下方px、Z=傾きdegree。頭部姿勢だけを担当する。
const StateScript := preload("res://src/domain/combatant_state.gd")
const CHARGE := Vector3(-20.0, 8.0, -5.0)
const WINDUP := Vector3(-26.0, 10.0, -6.0)
const STRIKE_DRIVE := Vector3(24.0, -4.0, 8.0)
const STRIKE_FOLLOW := Vector3(20.0, 6.0, 10.0)
const PARRY_PREPARE := Vector3(-5.0, 2.0, -2.0)
const PARRY_SWEEP := Vector3(12.0, -3.0, 6.0)
const PARRY_RECOIL := Vector3(4.0, 1.0, 2.0)
const RECOVER_SECONDS: float = 0.24
const FOLLOW_HOLD_SECONDS: float = 0.12


static func sample(action: int, elapsed: float, duration: float, max_charge: float, entry: Vector3) -> Vector3:
	if not entry.is_finite() or not is_finite(elapsed) or not is_finite(duration) or not is_finite(max_charge):
		return Vector3.ZERO
	# 状態の境界で頭部を別の初期位置へ飛ばさない。
	if elapsed <= 0.0:
		return entry
	var u: float = clampf(elapsed / maxf(duration, 0.001), 0.0, 1.0)
	match action:
		StateScript.ActionState.CHARGING:
			return entry.lerp(CHARGE, smoothstep(0.0, maxf(max_charge * 0.65, 0.08), elapsed))
		StateScript.ActionState.WINDUP:
			return entry.lerp(WINDUP, smoothstep(0.0, 1.0, u))
		StateScript.ActionState.STRIKE:
			if u < 0.40:
				return entry.lerp(STRIKE_DRIVE, smoothstep(0.0, 0.40, u))
			if u < 0.70:
				return STRIKE_DRIVE
			return STRIKE_DRIVE.lerp(STRIKE_FOLLOW, smoothstep(0.70, 1.0, u))
		StateScript.ActionState.PARRY:
			# 頭部の切り返しを毛先の払いピークより先に置く。
			if u < 0.16:
				return entry.lerp(PARRY_PREPARE, smoothstep(0.0, 0.16, u))
			if u < 0.40:
				return PARRY_PREPARE.lerp(PARRY_SWEEP, smoothstep(0.16, 0.40, u))
			if u < 0.72:
				return PARRY_SWEEP.lerp(PARRY_RECOIL, smoothstep(0.40, 0.72, u))
			return PARRY_RECOIL.lerp(Vector3.ZERO, smoothstep(0.72, 1.0, u))
		StateScript.ActionState.COOLDOWN:
			return entry.lerp(Vector3.ZERO, smoothstep(FOLLOW_HOLD_SECONDS, FOLLOW_HOLD_SECONDS + RECOVER_SECONDS, elapsed))
		StateScript.ActionState.DODGE:
			return entry.lerp(Vector3(-18.0, 24.0, -6.0), smoothstep(0.0, 0.06, elapsed))
		StateScript.ActionState.STAGGER:
			return entry.lerp(Vector3(-28.0, 8.0, -8.0), smoothstep(0.0, 0.08, elapsed))
		_:
			return entry.lerp(Vector3.ZERO, smoothstep(0.0, RECOVER_SECONDS, elapsed))
