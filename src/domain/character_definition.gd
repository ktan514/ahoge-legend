extends Resource

enum AhogeType {
	LONG,
	NORMAL,
	SHORT,
}

enum AttackType {
	SWING,
	THROW,
}

@export var character_id: String = ""
@export var display_name: String = ""
@export var feature_text: String = ""
@export var head_asset_path: String = ""
@export var ahoge_asset_path: String = ""
@export var ahoge_profile_path: String = ""
@export_range(0.5, 2.0, 0.01) var ahoge_display_scale: float = 1.0
@export_range(0.0, 20.0, 0.1) var breath_primary_amplitude_px: float = 4.0
@export_range(0.0, 20.0, 0.1) var breath_secondary_amplitude_px: float = 1.6
@export_range(0.1, 8.0, 0.1) var breath_primary_speed: float = 2.0
@export_range(0.1, 8.0, 0.1) var breath_secondary_speed: float = 0.8
@export_range(0.0, 12.0, 0.1) var ahoge_breath_sway_degrees: float = 1.5
@export_range(0.0, 3.141593, 0.01) var ahoge_breath_sway_phase_lag: float = 0.45
@export var ahoge_type: int = AhogeType.LONG
@export var attack_type: int = AttackType.SWING
@export_range(0.0, 1.0, 0.001) var ahoge_head_anchor_x_ratio: float = 0.50


static func create(
	id_value: String,
	name_value: String,
	ahoge_type_value: int,
	attack_type_value: int,
	feature_text_value: String = "",
	head_asset_path_value: String = "",
	ahoge_asset_path_value: String = "",
	ahoge_head_anchor_x_ratio_value: float = 0.50,
	ahoge_profile_path_value: String = "",
	ahoge_display_scale_value: float = 1.0,
	breath_primary_amplitude_px_value: float = 4.0,
	breath_secondary_amplitude_px_value: float = 1.6,
	breath_primary_speed_value: float = 2.0,
	breath_secondary_speed_value: float = 0.8,
	ahoge_breath_sway_degrees_value: float = 1.5,
	ahoge_breath_sway_phase_lag_value: float = 0.45
):
	var definition = new()
	definition.character_id = id_value
	definition.display_name = name_value
	definition.feature_text = feature_text_value
	definition.head_asset_path = head_asset_path_value
	definition.ahoge_asset_path = ahoge_asset_path_value
	definition.ahoge_profile_path = ahoge_profile_path_value
	definition.ahoge_display_scale = clampf(ahoge_display_scale_value, 0.5, 2.0)
	definition.breath_primary_amplitude_px = maxf(breath_primary_amplitude_px_value, 0.0)
	definition.breath_secondary_amplitude_px = maxf(breath_secondary_amplitude_px_value, 0.0)
	definition.breath_primary_speed = maxf(breath_primary_speed_value, 0.1)
	definition.breath_secondary_speed = maxf(breath_secondary_speed_value, 0.1)
	definition.ahoge_breath_sway_degrees = maxf(ahoge_breath_sway_degrees_value, 0.0)
	definition.ahoge_breath_sway_phase_lag = clampf(ahoge_breath_sway_phase_lag_value, 0.0, PI)
	definition.ahoge_type = ahoge_type_value
	definition.attack_type = attack_type_value
	definition.ahoge_head_anchor_x_ratio = clampf(ahoge_head_anchor_x_ratio_value, 0.0, 1.0)
	return definition


func ahoge_type_name() -> String:
	match ahoge_type:
		AhogeType.LONG:
			return "LONG"
		AhogeType.NORMAL:
			return "NORMAL"
		AhogeType.SHORT:
			return "SHORT"
	return "UNKNOWN"


func attack_type_name() -> String:
	match attack_type:
		AttackType.SWING:
			return "SWING"
		AttackType.THROW:
			return "THROW"
	return "UNKNOWN"
