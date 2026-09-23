# SaveSystem单元测试（最简版 - 使用autoload）
extends GutTest

# SaveSystem是autoload，直接使用实例

func before_all():
	# SaveSystem已在autoload中初始化
	await wait_seconds(0.1)

# ── 初始化测试 ──

func test_save_system_exists():
	assert_not_null(SaveSystem, "SaveSystem autoload应存在")

func test_initialize_sets_idle_state():
	assert_eq(SaveSystem.current_state, SaveSystem.State.IDLE, "初始状态应为IDLE")

func test_get_save_path_returns_valid_path():
	var path1 = SaveSystem.get_save_path(1)
	assert_eq(path1, "user://saves/save_slot_1.json", "路径格式正确")

	var path_invalid = SaveSystem.get_save_path(0)
	assert_eq(path_invalid, "", "无效slot应返回空字符串")

func test_get_all_slot_statuses_returns_dict():
	var statuses = SaveSystem.get_all_slot_statuses()
	assert_eq(statuses.size(), 3, "应返回3个slot状态")

func test_max_save_slots():
	assert_eq(SaveSystem.MAX_SAVE_SLOTS, 3, "最大slot数应为3")

func test_save_dir_constant():
	assert_eq(SaveSystem.SAVE_DIR, "user://saves/", "保存目录常量正确")

func test_delete_invalid_slot_emits_save_delete_failed_not_save_failed() -> void:
	watch_signals(SaveSystem)

	for invalid_slot in [0, -1, SaveSystem.MAX_SAVE_SLOTS + 1]:
		SaveSystem.delete(invalid_slot)
		assert_signal_emitted_with_parameters(
			SaveSystem,
			"save_delete_failed",
			[invalid_slot, "Invalid slot ID: %d. Must be 1..%d" % [invalid_slot, SaveSystem.MAX_SAVE_SLOTS]]
		)

	assert_signal_not_emitted(SaveSystem, "save_failed", "Invalid slot must not emit save_failed")

	# Restore state so later tests are not affected.
	SaveSystem.current_state = SaveSystem.State.IDLE
