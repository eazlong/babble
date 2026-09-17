extends GutTest

## 回归:存档系统不丢进度。
## 缺陷背景:project.godot 把 game/test_mode_skip_auto_load_save=true 提交为默认值,
## 导致 GameManager._ready() 永远跳过 load_progress(),存档文件正常写入但重启后从不读回,
## 表现为"存档系统没有正常保存进度"。CLAUDE.md §10 明确禁止该默认值。

const TEST_MODE_SKIP_AUTO_LOAD_SETTING: String = "game/test_mode_skip_auto_load_save"

func test_production_default_auto_load_save_must_not_be_skipped() -> void:
	# 生产默认必须自动读档(CLAUDE.md §10:不要默认关闭,测试用命令行/设置覆盖)。
	assert_false(
		bool(ProjectSettings.get_setting(TEST_MODE_SKIP_AUTO_LOAD_SETTING, false)),
		"生产默认必须自动读档(game/test_mode_skip_auto_load_save 应为 false)"
	)

func test_save_load_disk_round_trip_restores_archive_progress() -> void:
	# 隔离到临时目录,避免污染真实玩家存档。
	var original_save_dir: String = SaveSystem._test_save_dir
	var tmp_dir: String = "user://gut_save_roundtrip_%d/" % Time.get_ticks_usec()
	var dir_result: Error = DirAccess.make_dir_recursive_absolute(tmp_dir)
	assert_eq(dir_result, OK, "应能创建临时存档目录")
	SaveSystem._test_save_dir = tmp_dir

	var original_name: String = GameManager.player_name
	var original_age: int = GameManager.player_age
	var original_lxp: int = GameManager.lxp_score
	var original_progress: Dictionary = GameManager.get_archive_hall_progress()

	# 写档:玩家信息 + 归卷厅进度。
	GameManager.player_name = "回归测试玩家"
	GameManager.player_age = 8
	GameManager.lxp_score = 120
	GameManager.set_archive_hall_progress({"current_word_index": 3, "inscribed_count": 2})
	GameManager.save_progress()
	await wait_for_signal(SaveSystem.save_completed, 2.0)
	assert_true(FileAccess.file_exists(SaveSystem.get_save_path(1)), "save_slot_1.json 应落盘")

	# 模拟重启:状态回到默认。
	GameManager.player_name = ""
	GameManager.player_age = 0
	GameManager.lxp_score = 0
	GameManager.set_archive_hall_progress({})
	GameManager.save_loaded = false

	# 读回:必须恢复玩家信息与归卷厅进度。
	assert_true(GameManager.load_progress(), "存档文件存在且合法时应成功加载")
	assert_eq(GameManager.player_name, "回归测试玩家", "重启后应恢复 player_name")
	assert_eq(GameManager.lxp_score, 120, "重启后应恢复 lxp_score")
	var progress: Dictionary = GameManager.get_archive_hall_progress()
	assert_eq(progress.get("current_word_index", -1), 3, "重启后应恢复归卷厅 current_word_index")
	assert_eq(progress.get("inscribed_count", -1), 2, "重启后应恢复归卷厅 inscribed_count")

	# 清理:还原目录与 GameManager 状态,删除临时存档。
	GameManager.player_name = original_name
	GameManager.player_age = original_age
	GameManager.lxp_score = original_lxp
	GameManager.set_archive_hall_progress(original_progress)
	SaveSystem._test_save_dir = original_save_dir
	DirAccess.remove_absolute(tmp_dir + "save_slot_1.json")
	DirAccess.remove_absolute(tmp_dir)