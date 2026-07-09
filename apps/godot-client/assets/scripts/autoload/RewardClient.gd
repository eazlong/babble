extends Node
## RewardClient — HTTP client for the reward-service.
## Handles XP, badges, area unlocks, quest completion, and achievements.

const REWARD_SERVICE_URL = "http://localhost:8307"

signal xp_granted(result: Dictionary)
signal badge_granted(result: Dictionary)
signal area_unlocked(result: Dictionary)
signal quest_completed(result: Dictionary)
signal achievement_unlocked(achievement: Dictionary)
signal reward_error(error: String)
signal user_state_updated(state: Dictionary)

var _http: HTTPRequest
var _pending_requests: Dictionary  # request_id -> callback

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

func get_user_state(user_id: String) -> void:
	var url = REWARD_SERVICE_URL + "/api/v1/rewards/state/" + user_id
	_http.request(url, [], HTTPClient.METHOD_GET)

func grant_xp(user_id: String, amount: int, source: String = "gameplay") -> void:
	var body = JSON.stringify({
		"user_id": user_id,
		"amount": amount,
		"source": source
	})
	var headers = ["Content-Type: application/json"]
	_http.request(
		REWARD_SERVICE_URL + "/api/v1/rewards/grant-xp",
		headers,
		HTTPClient.METHOD_POST,
		body
	)

func grant_badge(user_id: String, badge_id: String, badge_name: String = "", source: String = "gameplay") -> void:
	var body = JSON.stringify({
		"user_id": user_id,
		"badge_id": badge_id,
		"badge_name": badge_name,
		"source": source
	})
	var headers = ["Content-Type: application/json"]
	_http.request(
		REWARD_SERVICE_URL + "/api/v1/rewards/grant-badge",
		headers,
		HTTPClient.METHOD_POST,
		body
	)

func unlock_area(user_id: String, area_id: String, area_name: String = "", source: String = "gameplay") -> void:
	var body = JSON.stringify({
		"user_id": user_id,
		"area_id": area_id,
		"area_name": area_name,
		"source": source
	})
	var headers = ["Content-Type: application/json"]
	_http.request(
		REWARD_SERVICE_URL + "/api/v1/rewards/unlock-area",
		headers,
		HTTPClient.METHOD_POST,
		body
	)

func complete_quest(user_id: String, quest_id: String, quest_type: String, cefr_level: String = "A1") -> void:
	var body = JSON.stringify({
		"user_id": user_id,
		"quest_id": quest_id,
		"quest_type": quest_type,
		"cefr_level": cefr_level
	})
	var headers = ["Content-Type: application/json"]
	_http.request(
		REWARD_SERVICE_URL + "/api/v1/rewards/quest-complete",
		headers,
		HTTPClient.METHOD_POST,
		body
	)

func get_achievements(user_id: String) -> void:
	var url = REWARD_SERVICE_URL + "/api/v1/achievements/" + user_id
	_http.request(url, [], HTTPClient.METHOD_GET)

func get_achievement_stats(user_id: String) -> void:
	var url = REWARD_SERVICE_URL + "/api/v1/achievements/stats/" + user_id
	_http.request(url, [], HTTPClient.METHOD_GET)

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		reward_error.emit("Request failed: " + str(result))
		return

	if response_code >= 400:
		reward_error.emit("HTTP error: " + str(response_code))
		return

	var json = JSON.new()
	var parse_err = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		reward_error.emit("JSON parse error")
		return

	var data = json.data
	if data == null:
		return

	# Emit specific signals based on response structure
	if data.has("user_state"):
		user_state_updated.emit(data.user_state)

		# Check for XP result
		if data.has("xp_result") and data.xp_result is Dictionary:
			xp_granted.emit(data)

		# Check for quest completion
		if data.has("drop"):
			quest_completed.emit(data)

	# Check for badge grant
	if data.has("is_new_badge"):
		badge_granted.emit(data)

	# Check for area unlock
	if data.has("is_new_area"):
		area_unlocked.emit(data)

	# Check for achievement unlocks
	if data.has("achievements_unlocked") and data.achievements_unlocked is Array:
		for ach in data.achievements_unlocked:
			achievement_unlocked.emit(ach)
