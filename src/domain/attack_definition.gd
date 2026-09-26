extends Resource

var attack_id: String = ""
var motion_type: String = ""
var contact_ratio: float = 0.70
var projectile_enabled: bool = false
var ahoge_detach: bool = false
var ahoge_regrow_seconds: float = 0.0


static func create_for_character(character, config):
	var definition = new()
	definition.attack_id = "%s_PRIMARY" % character.character_id
	definition.contact_ratio = config.attack_contact_ratio

	match character.attack_type:
		0:
			definition.motion_type = "SWING"
		1:
			definition.motion_type = "THROW"
			definition.projectile_enabled = true
			definition.ahoge_detach = true
			definition.ahoge_regrow_seconds = config.short_ahoge_regrow_seconds

	return definition
