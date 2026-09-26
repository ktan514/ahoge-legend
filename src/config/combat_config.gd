extends Resource

@export var round_seconds: float = 85.0
@export var hits_to_win_round: int = 5
@export var rounds_to_win_match: int = 2

@export var normal_windup_seconds: float = 0.18
@export var normal_strike_seconds: float = 0.20
@export var normal_cooldown_seconds: float = 0.48

@export var max_charge_seconds: float = 0.60
@export var charged_release_windup_seconds: float = 0.08
@export var charged_strike_seconds: float = 0.13
@export var charged_cooldown_seconds: float = 0.82

@export var parry_active_seconds: float = 0.18
@export var just_parry_seconds: float = 0.07
@export var dodge_active_seconds: float = 0.22
@export var just_dodge_seconds: float = 0.07
@export var attack_clash_window_seconds: float = 0.067
@export var stagger_seconds: float = 0.45
@export var short_ahoge_regrow_seconds: float = 0.60


func charge_ratio(elapsed_seconds: float) -> float:
	if max_charge_seconds <= 0.0:
		return 1.0
	return clampf(elapsed_seconds / max_charge_seconds, 0.0, 1.0)


func attack_windup_seconds(charge_ratio_value: float) -> float:
	return lerpf(normal_windup_seconds, charged_release_windup_seconds, clampf(charge_ratio_value, 0.0, 1.0))


func attack_strike_seconds(charge_ratio_value: float) -> float:
	return lerpf(normal_strike_seconds, charged_strike_seconds, clampf(charge_ratio_value, 0.0, 1.0))


func attack_cooldown_seconds(charge_ratio_value: float) -> float:
	return lerpf(normal_cooldown_seconds, charged_cooldown_seconds, clampf(charge_ratio_value, 0.0, 1.0))
