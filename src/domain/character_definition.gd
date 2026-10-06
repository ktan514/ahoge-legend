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
	ahoge_head_anchor_x_ratio_value: float = 0.50
):
	var definition = new()
	definition.character_id = id_value
	definition.display_name = name_value
	definition.feature_text = feature_text_value
	definition.head_asset_path = head_asset_path_value
	definition.ahoge_asset_path = ahoge_asset_path_value
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
