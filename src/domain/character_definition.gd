class_name CharacterDefinition
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
@export var ahoge_type: AhogeType = AhogeType.LONG
@export var attack_type: AttackType = AttackType.SWING


static func create(
	id_value: String,
	name_value: String,
	ahoge_type_value: AhogeType,
	attack_type_value: AttackType
) -> CharacterDefinition:
	var definition := CharacterDefinition.new()
	definition.character_id = id_value
	definition.display_name = name_value
	definition.ahoge_type = ahoge_type_value
	definition.attack_type = attack_type_value
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
