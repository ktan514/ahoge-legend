extends RefCounted

const CharacterDefinitionScript := preload("res://src/domain/character_definition.gd")


static func all() -> Array:
	var characters: Array = []
	characters.append(CharacterDefinitionScript.create(
		"LONG_TEST",
		"LONG TEST",
		CharacterDefinitionScript.AhogeType.LONG,
		CharacterDefinitionScript.AttackType.SWING,
		"長いアホ毛で間合いを取るスタンダード型"
	))
	characters.append(CharacterDefinitionScript.create(
		"SHORT_TEST",
		"SHORT TEST",
		CharacterDefinitionScript.AhogeType.SHORT,
		CharacterDefinitionScript.AttackType.THROW,
		"短いアホ毛を投げてかき回す変則型"
	))
	return characters


static func get_by_id(character_id: String):
	for character in all():
		if character.character_id == character_id:
			return character
	return all()[0]
