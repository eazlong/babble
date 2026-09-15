extends GutTest

const FORMATION_MAX: int = 8

var _saved_energy: int
var _saved_active: String
var _saved_next: String
var _saved_scene: String
var _saved_completed: Array[String]
var _saved_vocab: Array[String]

func before_each() -> void:
	_saved_energy = GameManager.formation_energy
	_saved_active = GameManager.formation_active_episode
	_saved_next = GameManager.next_lesson_id
	_saved_scene = GameManager.current_scene
	_saved_completed = GameManager.completed_dialogues.duplicate()
	_saved_vocab = GameManager.vocabulary_learned.duplicate()

func after_each() -> void:
	GameManager.formation_energy = _saved_energy
	GameManager.formation_active_episode = _saved_active
	GameManager.next_lesson_id = _saved_next
	GameManager.current_scene = _saved_scene
	GameManager.completed_dialogues = _saved_completed
	GameManager.vocabulary_learned = _saved_vocab

func _reset_state() -> void:
	GameManager.formation_energy = FORMATION_MAX
	GameManager.formation_active_episode = ""
	GameManager.next_lesson_id = ""
	GameManager.current_scene = "MirageInnHub"

func test_add_formation_energy_reports_newly_full() -> void:
	_reset_state()
	GameManager.formation_energy = FORMATION_MAX - 1
	assert_true(GameManager.add_formation_energy(1), "7 to 8 should report newly full")
	assert_eq(GameManager.get_formation_energy(), FORMATION_MAX)
	assert_false(GameManager.add_formation_energy(1), "already full should not report newly full")
	assert_eq(GameManager.get_formation_energy(), FORMATION_MAX)

func test_start_formation_trip_requires_full_charge() -> void:
	_reset_state()
	GameManager.formation_energy = FORMATION_MAX - 1
	assert_false(GameManager.start_formation_trip("ChangAnMarket"))
	GameManager.formation_energy = FORMATION_MAX
	assert_true(GameManager.start_formation_trip("ChangAnMarket"))
	assert_eq(GameManager.get_formation_energy(), 0)
	assert_eq(GameManager.get_formation_active_episode(), "ChangAnMarket")

func test_complete_mainline_episode_clears_paid_trip_and_requires_charge() -> void:
	_reset_state()
	GameManager.formation_active_episode = "ChangAnMarket"
	GameManager.formation_energy = 0
	GameManager.complete_mainline_episode("ChangAnMarketLesson02")
	assert_eq(GameManager.get_formation_active_episode(), "")
	assert_eq(GameManager.get_formation_energy(), 0)

func test_complete_mainline_episode_without_next_does_not_gate() -> void:
	_reset_state()
	GameManager.formation_energy = 5
	GameManager.complete_mainline_episode("ChangAnMarketLesson03")
	assert_eq(GameManager.get_formation_active_episode(), "")
	assert_eq(GameManager.get_formation_energy(), 5)

func test_should_recharge_before_departure() -> void:
	_reset_state()
	GameManager.next_lesson_id = "ChangAnMarketLesson02"
	GameManager.formation_energy = 7
	assert_true(GameManager.should_recharge_before_departure())
	GameManager.formation_energy = FORMATION_MAX
	assert_false(GameManager.should_recharge_before_departure())
	GameManager.next_lesson_id = "ChangAnMarketLesson03"
	GameManager.formation_energy = 0
	assert_false(GameManager.should_recharge_before_departure())

func test_has_playable_lesson_uses_registered_scene_paths() -> void:
	assert_true(GameManager.has_playable_lesson("ChangAnMarket"))
	assert_true(GameManager.has_playable_lesson("ChangAnMarketLesson02"))
	assert_false(GameManager.has_playable_lesson("ChangAnMarketLesson03"))
	assert_false(GameManager.has_playable_lesson("NotARealScene"))

func test_legacy_save_mid_episode_is_marked_paid() -> void:
	_reset_state()
	GameManager._restore_from_save_data({
		"current_scene_id": "ChangAnMarket",
		"next_lesson_id": "",
		"completed_dialogues": [],
		"vocabulary_learned": [],
	})
	assert_eq(GameManager.get_formation_energy(), 0)
	assert_eq(GameManager.get_formation_active_episode(), "ChangAnMarket")

func test_legacy_save_after_episode_requires_charge() -> void:
	_reset_state()
	GameManager._restore_from_save_data({
		"current_scene_id": "MirageInnHub",
		"next_lesson_id": "ChangAnMarketLesson02",
		"completed_dialogues": ["changan_gate_01_complete"],
		"vocabulary_learned": [],
	})
	assert_eq(GameManager.get_formation_energy(), 0)
	assert_eq(GameManager.get_formation_active_episode(), "")

func test_legacy_save_without_playable_next_is_not_gated() -> void:
	_reset_state()
	GameManager._restore_from_save_data({
		"current_scene_id": "MirageInnHub",
		"next_lesson_id": "ChangAnMarketLesson03",
		"completed_dialogues": ["changan_eaves_02_complete"],
		"vocabulary_learned": [],
	})
	assert_eq(GameManager.get_formation_energy(), FORMATION_MAX)
	assert_eq(GameManager.get_formation_active_episode(), "")

func test_saved_formation_fields_restore_exactly() -> void:
	_reset_state()
	GameManager._restore_from_save_data({
		"current_scene_id": "MirageInnHub",
		"next_lesson_id": "ChangAnMarketLesson02",
		"formation_energy": 3,
		"formation_active_episode": "ChangAnMarketLesson02",
		"completed_dialogues": [],
		"vocabulary_learned": [],
	})
	assert_eq(GameManager.get_formation_energy(), 3)
	assert_eq(GameManager.get_formation_active_episode(), "ChangAnMarketLesson02")


func test_legacy_save_before_first_mainline_is_full() -> void:
	_reset_state()
	GameManager._restore_from_save_data({
		"current_scene_id": "MirageInnHub",
		"next_lesson_id": "ChangAnMarket",
		"completed_dialogues": ["beginning_prologue_complete", "mirage_inn_introduction_complete"],
		"vocabulary_learned": [],
	})
	assert_eq(GameManager.get_formation_energy(), FORMATION_MAX)
	assert_eq(GameManager.get_formation_active_episode(), "")
