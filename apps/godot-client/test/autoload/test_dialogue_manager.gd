# DialogueManager集成测试（最简版 - 使用autoload）
extends GutTest

# DialogueManager是autoload，直接使用实例

func before_all():
	await wait_seconds(0.1)

# ── Wake请求检测测试 ──

func test_is_wake_request_detects_help():
	var result = DialogueManager._is_wake_request("help me please")
	assert_true(result, "help应检测")

func test_is_wake_request_detects_chinese():
	var result = DialogueManager._is_wake_request("帮帮我")
	assert_true(result, "中文帮助应检测")

func test_is_wake_request_rejects_normal_text():
	var result = DialogueManager._is_wake_request("hello world")
	assert_false(result, "正常文本不应检测")

# ── 对话状态测试 ──

func test_dialogue_manager_exists():
	assert_not_null(DialogueManager, "DialogueManager autoload应存在")

func test_initial_state():
	assert_eq(DialogueManager.dialogue_state, "idle", "初始状态应为idle")

func test_silence_timer_exists():
	assert_not_null(DialogueManager.silence_timer, "静音计时器应存在")

func test_silence_timer_wait_time():
	assert_eq(DialogueManager.silence_timer.wait_time, 15.0, "等待时间应为15秒")