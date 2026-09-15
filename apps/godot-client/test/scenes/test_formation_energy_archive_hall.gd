extends GutTest

const ControllerScript = preload("res://assets/scripts/scenes/WordSpiritLibraryArchiveHallController.gd")

var _saved_energy: int

func before_each() -> void:
	_saved_energy = GameManager.formation_energy

func after_each() -> void:
	GameManager.formation_energy = _saved_energy

func _make_controller() -> Node:
	var controller = ControllerScript.new()
	add_child(controller)
	return controller

func test_apply_review_unit_energy_adds_one() -> void:
	GameManager.formation_energy = 0
	var c = _make_controller()
	assert_false(c._apply_review_unit_energy())
	assert_eq(GameManager.formation_energy, 1)
	c.free()

func test_apply_review_unit_energy_reports_newly_full() -> void:
	GameManager.formation_energy = 7
	var c = _make_controller()
	assert_true(c._apply_review_unit_energy())
	assert_eq(GameManager.formation_energy, 8)
	c.free()

func test_apply_review_unit_energy_ignores_already_full() -> void:
	GameManager.formation_energy = 8
	var c = _make_controller()
	assert_false(c._apply_review_unit_energy())
	assert_eq(GameManager.formation_energy, 8)
	c.free()
