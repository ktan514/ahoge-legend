extends RefCounted

const OnlineConfigScript := preload("res://src/config/online_config.gd")


static func build(rating: int) -> String:
	var min_rating := rating - OnlineConfigScript.RANKED_INITIAL_RATING_RANGE
	var max_rating := rating + OnlineConfigScript.RANKED_INITIAL_RATING_RANGE
	return "+properties.mode:%s +properties.rating:>=%d +properties.rating:<=%d" % [
		OnlineConfigScript.RANKED_MATCHMAKER_MODE,
		min_rating,
		max_rating,
	]
