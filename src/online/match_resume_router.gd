extends RefCounted

const DESTINATION_NONE: String = "none"
const DESTINATION_BATTLE: String = "battle"
const DESTINATION_RANKED_RESULT: String = "ranked_result"
const DESTINATION_FRIEND_RESULT: String = "friend_result"


static func resolve(snapshot: Dictionary) -> String:
	if snapshot.is_empty():
		return DESTINATION_NONE

	if not bool(snapshot.get("match_finished", false)):
		return DESTINATION_BATTLE

	if str(snapshot.get("match_mode", "")) == "friend":
		return DESTINATION_FRIEND_RESULT

	if str(snapshot.get("match_mode", "")) == "ranked":
		return DESTINATION_RANKED_RESULT

	return DESTINATION_NONE
