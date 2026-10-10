extends RefCounted

const CharacterDefinitionScript := preload("res://src/domain/character_definition.gd")


static func all() -> Array:
	var characters: Array = []
	characters.append(CharacterDefinitionScript.create(
		"SAKURAMIKO",
		"さくらみこ",
		CharacterDefinitionScript.AhogeType.LONG,
		CharacterDefinitionScript.AttackType.SWING,
		"1人目の正式実装キャラクター",
		"res://assets/characters/sakuramiko/head.png",
		"res://assets/characters/sakuramiko/ahoge.png",
		0.64,
		"res://assets/characters/sakuramiko/ahoge_profile.tres",
		1.15,
		4.0,
		1.2,
		2.0,
		0.8,
		2.2,
		0.55
	))
	characters.append(CharacterDefinitionScript.create(
		"LONG_TEST",
		"LONG TEST",
		CharacterDefinitionScript.AhogeType.LONG,
		CharacterDefinitionScript.AttackType.SWING,
		"長いアホ毛で間合いを取るスタンダード型",
		"res://assets/characters/prototype/charactor_01/head.png",
		"res://assets/characters/prototype/charactor_01/ahoge_straight.png",
		0.64
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
