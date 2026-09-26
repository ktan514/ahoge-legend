class_name CharacterCatalog
extends RefCounted


static func all() -> Array[CharacterDefinition]:
	var characters: Array[CharacterDefinition] = []
	characters.append(CharacterDefinition.create(
		"LONG_TEST",
		"LONG TEST",
		CharacterDefinition.AhogeType.LONG,
		CharacterDefinition.AttackType.SWING
	))
	characters.append(CharacterDefinition.create(
		"SHORT_TEST",
		"SHORT TEST",
		CharacterDefinition.AhogeType.SHORT,
		CharacterDefinition.AttackType.THROW
	))
	return characters


static func get_by_id(character_id: String) -> CharacterDefinition:
	for character in all():
		if character.character_id == character_id:
			return character
	return all()[0]
