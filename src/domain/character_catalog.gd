extends RefCounted

const CharacterDefinitionScript := preload("res://src/domain/character_definition.gd")


static func all() -> Array:
	var characters: Array = []
	characters.append(CharacterDefinitionScript.create(
		"LONG_TEST",
		"LONG TEST",
		CharacterDefinitionScript.AhogeType.LONG,
		CharacterDefinitionScript.AttackType.SWING
	))
	characters.append(CharacterDefinitionScript.create(
		"SHORT_TEST",
		"SHORT TEST",
		CharacterDefinitionScript.AhogeType.SHORT,
		CharacterDefinitionScript.AttackType.THROW
	))
	return characters


static func get_by_id(character_id: String):
	for character in all():
		if character.character_id == character_id:
			return character
	return all()[0]
