extends RefCounted

const OnlineConfigScript := preload("res://src/config/online_config.gd")


static func build(rating: int) -> String:
	return build_with_range(rating, OnlineConfigScript.RANKED_INITIAL_RATING_RANGE)


static func build_with_range(rating: int, rating_range: int) -> String:
	var clamped_range := clampi(
		rating_range,
		OnlineConfigScript.RANKED_INITIAL_RATING_RANGE,
		OnlineConfigScript.RANKED_MAX_RATING_RANGE
	)
	var min_rating := rating - clamped_range
	var max_rating := rating + clamped_range
	return "+properties.mode:%s +properties.rating:>=%d +properties.rating:<=%d" % [
		OnlineConfigScript.RANKED_MATCHMAKER_MODE,
		min_rating,
		max_rating,
	]


static func rating_range_for_elapsed_seconds(elapsed_seconds: int) -> int:
	var safe_elapsed := maxi(elapsed_seconds, 0)
	var expansion_steps := safe_elapsed / OnlineConfigScript.RANKED_RANGE_EXPAND_INTERVAL_SECONDS
	return mini(
		OnlineConfigScript.RANKED_INITIAL_RATING_RANGE
			+ expansion_steps * OnlineConfigScript.RANKED_RATING_RANGE_STEP,
		OnlineConfigScript.RANKED_MAX_RATING_RANGE
	)


static func is_prolonged_wait(elapsed_seconds: int) -> bool:
	return elapsed_seconds >= OnlineConfigScript.RANKED_PROLONGED_WAIT_SECONDS
