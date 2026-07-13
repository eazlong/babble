class_name CoachContextTracker
extends RefCounted

## Maintains a sliding window of the most recent player/NPC dialogue turns,
## formatted for the coach service's `recent_turns` field.
##
## 5 rounds (10 messages total) matches the backend's prompt budget assumption.

const MAX_TURNS: int = 5
const MAX_MESSAGES: int = MAX_TURNS * 2  # player + NPC per turn

var _messages: Array[Dictionary] = []


func add_turn(speaker: String, text: String) -> void:
	"""Record one dialogue turn. speaker is 'player' or 'npc'."""
	if text.is_empty():
		return
	_messages.append({"speaker": speaker, "text": text})
	# Trim to keep only the most recent MAX_MESSAGES entries
	if _messages.size() > MAX_MESSAGES:
		_messages = _messages.slice(_messages.size() - MAX_MESSAGES)


func get_recent_turns() -> Array[Dictionary]:
	"""Return a copy of the recent turns for serialization."""
	return _messages.duplicate()


func clear() -> void:
	"""Reset the tracker (e.g. when a dialogue session ends)."""
	_messages.clear()


func size() -> int:
	return _messages.size()
