extends GutTest

## Boot resume: player must interact with feifei in the owner room before
## the saved story scene is entered.

const BeginningFPControllerScript = preload("res://assets/scripts/scenes/BeginningFPController.gd")
const StoryContinueMarkersScript = preload("res://assets/scripts/core/story_continue_markers.gd")

const ZH_DEPART: String = "出发"
const ZH_CONTINUE: String = "继续"


func test_continue_markers_cover_resume_and_hub_phrases() -> void:
	assert_true(StoryContinueMarkersScript.matches("lets go"), "english depart phrase should match")
	assert_true(StoryContinueMarkersScript.matches(ZH_DEPART), "chinese depart phrase should match")
	assert_true(StoryContinueMarkersScript.matches(ZH_CONTINUE), "continue phrase should match")
	assert_false(StoryContinueMarkersScript.matches("bookshelf"), "bookshelf should not resume")
	assert_false(StoryContinueMarkersScript.matches(""), "empty phrase should not match")


func test_beginning_resume_matcher_accepts_resume_phrases() -> void:
	var controller = BeginningFPControllerScript.new()
	assert_true(controller._is_resume_call("lets go"), "resume should accept english depart phrase")
	assert_true(controller._is_resume_call(ZH_DEPART), "resume should accept chinese depart phrase")
	assert_true(controller._is_resume_call(ZH_CONTINUE), "resume should accept continue phrase")
	assert_false(controller._is_resume_call("i do not know"), "unrelated answer should not resume")
	controller.free()


func test_resume_asr_context_is_keyword_closed_set() -> void:
	var controller = BeginningFPControllerScript.new()
	controller.state = controller.PrologueState.AWAIT_RESUME_CONFIRM
	var context: Dictionary = controller._build_asr_context_for_state()
	assert_eq(context.get("expected_answer_type", ""), "keyword", "resume prompt should be a keyword slot")
	assert_eq(context.get("scene_id", ""), "mirage_inn_owner_room", "resume voice command must not attach to the saved learning scene")
	var candidates: Array = context.get("candidate_answers", [])
	assert_true(candidates.has(ZH_DEPART), "candidates should include chinese depart")
	assert_true(candidates.has("lets go"), "candidates should include english depart")
	assert_true(candidates.has(ZH_CONTINUE), "candidates should include continue")
	assert_true(candidates.has("continue"), "candidates should include continue english")
	controller.free()


func test_boot_room_resume_predicate_requires_valid_saved_scene() -> void:
	var original_loaded: bool = GameManager.save_loaded
	var original_scene: String = GameManager.current_scene
	GameManager.save_loaded = true
	GameManager.current_scene = "MirageInnHub"
	assert_true(GameManager.should_resume_to_scene("BeginningFP"), "valid saved scene should resume")
	GameManager.current_scene = "BeginningFP"
	assert_false(GameManager.should_resume_to_scene("BeginningFP"), "boot scene itself should not resume")
	GameManager.current_scene = "MainMenu"
	assert_false(GameManager.should_resume_to_scene("BeginningFP"), "missing scene file should not resume")
	GameManager.save_loaded = false
	GameManager.current_scene = "MirageInnHub"
	assert_false(GameManager.should_resume_to_scene("BeginningFP"), "unsaved session should not resume")
	GameManager.save_loaded = original_loaded
	GameManager.current_scene = original_scene


func test_beginning_ready_no_longer_auto_changes_to_saved_scene() -> void:
	var file: FileAccess = FileAccess.open("res://assets/scripts/scenes/BeginningFPController.gd", FileAccess.READ)
	assert_not_null(file, "BeginningFPController source should be readable")
	if file == null:
		return
	var source: String = file.get_as_text()
	assert_false(source.contains("_resume_to_saved_scene"), "boot branch must not auto change scene")
	assert_true(source.contains("_start_resume_room"), "boot branch must enter owner-room resume interaction")
	assert_false(source.contains("_unhandled_input"), "resume must be dialogue-driven, not pointer input")
	assert_false(source.contains("InputEventScreenTouch"), "resume must not use direct touch events")
	assert_false(source.contains("_is_feifei_tap_position"), "resume must not define a tap hotzone")
