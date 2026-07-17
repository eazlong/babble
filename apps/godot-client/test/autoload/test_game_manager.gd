extends GutTest

func test_magic_echo_save_data_exports_manager_state() -> void:
	var magic_echo_manager: Node = get_node_or_null("/root/MagicEchoManager")
	assert_not_null(magic_echo_manager, "测试需要MagicEchoManager autoload")
	if magic_echo_manager == null:
		return

	magic_echo_manager.call("enter_learning_scene", "SpellLibrary", "child-1")
	var save_data: Dictionary = GameManager.call("_magic_echo_save_data")

	assert_true(save_data.has("game_sessions"), "GameManager应导出MagicEchoManager的game_sessions")
	assert_true(save_data.has("prompt_turns"), "GameManager应导出MagicEchoManager的prompt_turns")
	assert_true(save_data.has("interaction_attempts"), "GameManager应导出MagicEchoManager的interaction_attempts")
	assert_true(save_data.has("recording_envelopes"), "GameManager应导出录音pending envelope")
	assert_true(save_data.has("pending_uploads"), "GameManager应导出待补传队列")
