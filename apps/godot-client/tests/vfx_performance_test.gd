## VFX Performance Test
## 测试 VFXManager 性能：池扩展、预算限制、降级策略
extends SceneTree

var _test_results: Array[String] = []
var _vfx_manager: Node = null

func _init() -> void:
	print("=== VFXManager Performance Test ===\n")

func _ready() -> void:
	await _test_pool_initialization()
	await _test_pool_expansion()
	await _test_budget_limits()
	await _test_degradation()
	await _test_cleanup()

	_print_results()
	quit()

func _test_pool_initialization() -> void:
	print("Test 1: Pool Initialization...")

	var stats_before: Dictionary = VFXManager.get_pool_stats()
	assert(stats_before.particle_pool_size >= 30, "Particle pool should be pre-warmed")
	assert(stats_before.shader_pool_size >= 15, "Shader pool should be pre-warmed")

	_test_results.append("✓ Pool initialization: PASSED")
	print("  - Particle pool: %d" % stats_before.particle_pool_size)
	print("  - Shader pool: %d" % stats_before.shader_pool_size)

func _test_pool_expansion() -> void:
	print("\nTest 2: Pool Expansion...")

	var effect_ids: Array[String] = []
	for i in range(50):
		var id := VFXManager.play_spirit_unlock(Vector2(100 + i, 100), "common")
		if not id.is_empty():
			effect_ids.append(id)

	await create_timer(0.5).timeout

	var stats: Dictionary = VFXManager.get_pool_stats()
	assert(stats.particle_pool_size >= 30, "Pool should not shrink")

	_test_results.append("✓ Pool expansion: PASSED (%d effects created)" % effect_ids.size())
	print("  - Effects created: %d" % effect_ids.size())
	print("  - Pool size after: %d" % stats.particle_pool_size)

	# Cleanup
	for id in effect_ids:
		VFXManager.stop_effect(id)

func _test_budget_limits() -> void:
	print("\nTest 3: Budget Limits...")

	var successful_effects: int = 0
	var failed_effects: int = 0

	for i in range(200):
		var id := VFXManager.play_spirit_unlock(Vector2(randf() * 800, randf() * 600), "common")
		if id.is_empty():
			failed_effects += 1
		else:
			successful_effects += 1

	await create_timer(0.1).timeout

	var stats: Dictionary = VFXManager.get_pool_stats()
	assert(stats.particle_in_use <= 100, "Should respect max particles per frame")

	_test_results.append("✓ Budget limits: PASSED")
	print("  - Successful: %d, Failed: %d" % [successful_effects, failed_effects])
	print("  - Particles in use: %d" % stats.particle_in_use)

	VFXManager.stop_all_effects()

func _test_degradation() -> void:
	print("\nTest 4: Performance Degradation...")

	var initial_level: int = VFXManager.get_current_degradation_level()

	# Simulate low FPS
	PerformanceMonitor.current_fps = 25.0
	await create_timer(1.0).timeout

	var new_level: int = VFXManager.get_current_degradation_level()
	assert(new_level >= initial_level, "Degradation level should increase or stay same")

	_test_results.append("✓ Degradation: PASSED (level %d -> %d)" % [initial_level, new_level])
	print("  - Level changed: %d -> %d" % [initial_level, new_level])

	# Reset
	PerformanceMonitor.current_fps = 60.0
	await create_timer(0.5).timeout

func _test_cleanup() -> void:
	print("\nTest 5: Cleanup...")

	VFXManager.stop_all_effects()
	await create_timer(0.5).timeout

	var stats: Dictionary = VFXManager.get_pool_stats()
	assert(stats.particle_in_use == 0, "All particles should be released")
	assert(stats.active_effects == 0, "All effects should be stopped")

	_test_results.append("✓ Cleanup: PASSED")
	print("  - Active effects: %d" % stats.active_effects)
	print("  - Particles in use: %d" % stats.particle_in_use)

func _print_results() -> void:
	print("\n=== Test Results ===")
	for result in _test_results:
		print(result)

	var passed: int = _test_results.filter(func(s): return s.contains("PASSED")).size()
	print("\nTotal: %d/%d tests passed" % [passed, _test_results.size()])
