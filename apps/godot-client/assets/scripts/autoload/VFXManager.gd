## VFXManager.gd
## Visual Effects Manager — 对象池化的特效管理系统
## 设计目标：性能优先，支持降级策略，确保儿童游戏流畅 60 FPS
## Godot 4.6, GDScript static typing
extends Node

# ── Signals ────────────────────────────────────────────────────────────────
signal effect_played(effect_id: String, effect_type: String)
signal effect_stopped(effect_id: String)
signal performance_degraded(new_level: int, reason: String)
signal performance_recovered(previous_level: int)
signal pool_exhausted(pool_type: String)
signal pool_expanded(pool_type: String, new_size: int)

# ── Performance Budget Constants ───────────────────────────────────────────
const MAX_PARTICLES_PER_FRAME: int = 100
const MAX_ACTIVE_TWEENS: int = 50
const MAX_SHADERS_ANIMATED: int = 20
const EFFECT_COOLDOWN_MS: int = 100
const POOL_EXPANSION_FACTOR: float = 1.5

# ── Pool Size Constants ──────────────────────────────────────────────────
const INITIAL_PARTICLE_POOL_SIZE: int = 30
const INITIAL_SHADER_POOL_SIZE: int = 15
const INITIAL_TWEEN_POOL_SIZE: int = 20
const MAX_PARTICLE_POOL_SIZE: int = 100
const MAX_SHADER_POOL_SIZE: int = 50
const MAX_TWEEN_POOL_SIZE: int = 80

# ── Degradation Level Enum ───────────────────────────────────────────────
enum DegradationLevel {
	NONE = 0,
	LEVEL_1_REDUCE_PARTICLES = 1,
	LEVEL_2_DISABLE_SHADERS = 2,
	LEVEL_3_SIMPLIFY_TWEENS = 3
}

# ── Internal State ─────────────────────────────────────────────────────────
var _current_degradation: DegradationLevel = DegradationLevel.NONE
var _frame_particle_count: int = 0
var _active_tween_count: int = 0
var _active_shader_count: int = 0
var _effect_cooldowns: Dictionary[String, int] = {}
var _active_effects: Dictionary[String, Node] = {}
var _effect_id_counter: int = 0

# ── Object Pools ──────────────────────────────────────────────────────────
var _particle_pool: Array[GPUParticles2D] = []
var _particle_in_use: Array[bool] = []
var _shader_pool: Array[ShaderMaterial] = []
var _shader_in_use: Array[bool] = []
var _tween_pool: Array[Tween] = []
var _tween_in_use: Array[bool] = []

# ── Performance Monitor Reference ─────────────────────────────────────────
var _performance_monitor: Node = null

# ── Lifecycle ─────────────────────────────────────────────────────────────
func _ready() -> void:
	_initialize_pools()
	_performance_monitor = get_node("/root/PerformanceMonitor")

func _process(_delta: float) -> void:
	_frame_particle_count = 0
	_update_cooldowns()
	_check_performance_degradation()

func _exit_tree() -> void:
	stop_all_effects()
	_clear_pools()

# ── Pool Initialization ──────────────────────────────────────────────────
func _initialize_pools() -> void:
	_particle_pool.clear()
	_particle_in_use.clear()
	_shader_pool.clear()
	_shader_in_use.clear()
	_tween_pool.clear()
	_tween_in_use.clear()

	# Pre-warm particle pool
	for i in range(INITIAL_PARTICLE_POOL_SIZE):
		var particle := _create_particle_node()
		_particle_pool.append(particle)
		_particle_in_use.append(false)

	# Pre-warm shader pool
	for i in range(INITIAL_SHADER_POOL_SIZE):
		var shader := _create_shader_material()
		_shader_pool.append(shader)
		_shader_in_use.append(false)

	# Note: Tween pool is created on-demand due to Tween requiring a node

func _clear_pools() -> void:
	for particle in _particle_pool:
		if particle and particle.is_inside_tree():
			particle.queue_free()
	_particle_pool.clear()
	_particle_in_use.clear()
	_shader_pool.clear()
	_shader_in_use.clear()
	_tween_pool.clear()
	_tween_in_use.clear()

func _create_particle_node() -> GPUParticles2D:
	var particle := GPUParticles2D.new()
	particle.emitting = false
	particle.one_shot = true
	particle.explosiveness = 1.0
	return particle

func _create_shader_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	return material

# ── Public API: Effect Playing ─────────────────────────────────────────────
func play_spirit_unlock(position: Vector2, rarity: String) -> String:
	if not _can_play_effect("spirit_unlock"):
		return ""

	var effect_id := _generate_effect_id()

	match _current_degradation:
		DegradationLevel.LEVEL_3_SIMPLIFY_TWEENS, DegradationLevel.LEVEL_2_DISABLE_SHADERS:
			_play_simple_glow(position, effect_id)
		_:
			_play_spirit_unlock_particles(position, rarity, effect_id)

	effect_played.emit(effect_id, "spirit_unlock")
	return effect_id

func play_magic_activation(position: Vector2, effect_type: String) -> String:
	if not _can_play_effect("magic_activation"):
		return ""

	var effect_id := _generate_effect_id()

	match _current_degradation:
		DegradationLevel.LEVEL_3_SIMPLIFY_TWEENS:
			_play_simple_scale(position, effect_id)
		_:
			_play_magic_particles(position, effect_type, effect_id)

	effect_played.emit(effect_id, "magic_activation")
	return effect_id

func play_shader_effect(target_node: Node2D, shader_type: String, params: Dictionary) -> String:
	if not _can_play_effect("shader"):
		return ""

	if _current_degradation >= DegradationLevel.LEVEL_2_DISABLE_SHADERS:
		return _play_fallback_effect(target_node, params)

	if _active_shader_count >= MAX_SHADERS_ANIMATED:
		return _play_fallback_effect(target_node, params)

	var effect_id := _generate_effect_id()
	var shader := _acquire_shader()

	if shader == null:
		return _play_fallback_effect(target_node, params)

	_apply_shader_to_target(shader, target_node, shader_type, params)
	_active_effects[effect_id] = target_node
	_active_shader_count += 1

	effect_played.emit(effect_id, "shader")
	return effect_id

func play_ambient_float(parent_node: Node, count: int) -> Array[String]:
	if parent_node == null or not parent_node.is_inside_tree():
		return []

	var effect_ids: Array[String] = []
	var actual_count: int = count

	match _current_degradation:
		DegradationLevel.LEVEL_1_REDUCE_PARTICLES:
			actual_count = int(count * 0.5)
		DegradationLevel.LEVEL_2_DISABLE_SHADERS, DegradationLevel.LEVEL_3_SIMPLIFY_TWEENS:
			actual_count = int(count * 0.25)

	for i in range(actual_count):
		var effect_id := _generate_effect_id()
		var particle := _acquire_particle()

		if particle == null:
			break

		_setup_ambient_particle(particle, parent_node)
		_active_effects[effect_id] = particle
		effect_ids.append(effect_id)

	effect_played.emit("ambient_" + str(effect_ids.size()), "ambient_float")
	return effect_ids

func stop_effect(effect_id: String) -> void:
	if not _active_effects.has(effect_id):
		return

	var node := _active_effects[effect_id]
	_active_effects.erase(effect_id)

	if node is GPUParticles2D:
		_release_particle(node)
	elif node is Node2D and node.material is ShaderMaterial:
		_active_shader_count = maxi(_active_shader_count - 1, 0)
		_release_shader(node.material)

	effect_stopped.emit(effect_id)

func stop_all_effects() -> void:
	for effect_id in _active_effects.keys():
		stop_effect(effect_id)

# ── Private Effect Implementations ────────────────────────────────────────
func _play_spirit_unlock_particles(position: Vector2, rarity: String, effect_id: String) -> void:
	var particle := _acquire_particle()
	if particle == null:
		return

	particle.global_position = position
	particle.amount = _get_rarity_particle_count(rarity)
	particle.modulate = _get_rarity_color(rarity)
	particle.emitting = true

	_frame_particle_count += particle.amount
	_active_effects[effect_id] = particle

	# Auto-release after emission
	var timer := get_tree().create_timer(3.0)
	timer.timeout.connect(func(): stop_effect(effect_id))

func _play_magic_particles(position: Vector2, effect_type: String, effect_id: String) -> void:
	var particle := _acquire_particle()
	if particle == null:
		return

	particle.global_position = position
	particle.amount = 20
	particle.modulate = Color(0.8, 0.4, 1.0, 0.8)
	particle.emitting = true

	_frame_particle_count += particle.amount
	_active_effects[effect_id] = particle

	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func(): stop_effect(effect_id))

func _play_simple_glow(position: Vector2, effect_id: String) -> void:
	var glow := ColorRect.new()
	glow.size = Vector2(64, 64)
	glow.position = position - glow.size / 2
	glow.color = Color(1.0, 1.0, 0.5, 0.3)
	get_tree().root.add_child(glow)

	_active_effects[effect_id] = glow

	var tween := create_tween()
	tween.tween_property(glow, "modulate:a", 0.0, 1.0)
	tween.tween_callback(func():
		if glow.is_inside_tree():
			glow.queue_free()
		stop_effect(effect_id)
	)

func _play_simple_scale(position: Vector2, effect_id: String) -> void:
	var pulse := ColorRect.new()
	pulse.size = Vector2(32, 32)
	pulse.position = position - pulse.size / 2
	pulse.color = Color(0.8, 0.4, 1.0, 0.5)
	get_tree().root.add_child(pulse)

	_active_effects[effect_id] = pulse

	var tween := create_tween()
	tween.tween_property(pulse, "scale", Vector2(1.5, 1.5), 0.3)
	tween.tween_property(pulse, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		if pulse.is_inside_tree():
			pulse.queue_free()
		stop_effect(effect_id)
	)

func _play_fallback_effect(target_node: Node2D, _params: Dictionary) -> String:
	var effect_id := _generate_effect_id()

	var tween := create_tween()
	tween.tween_property(target_node, "modulate", Color(1.2, 1.2, 0.8, 1.0), 0.2)
	tween.tween_property(target_node, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.3)

	_active_effects[effect_id] = target_node

	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(func(): stop_effect(effect_id))

	return effect_id

# ── Pool Management ───────────────────────────────────────────────────────
func _acquire_particle() -> GPUParticles2D:
	for i in range(_particle_pool.size()):
		if not _particle_in_use[i]:
			_particle_in_use[i] = true
			return _particle_pool[i]

	# Pool exhausted - try to expand
	if _particle_pool.size() < MAX_PARTICLE_POOL_SIZE:
		var new_size: int = int(_particle_pool.size() * POOL_EXPANSION_FACTOR)
		new_size = mini(new_size, MAX_PARTICLE_POOL_SIZE)

		for j in range(_particle_pool.size(), new_size):
			var particle := _create_particle_node()
			_particle_pool.append(particle)
			_particle_in_use.append(false)

		pool_expanded.emit("particle", new_size)

		# Try again
		for i in range(_particle_pool.size()):
			if not _particle_in_use[i]:
				_particle_in_use[i] = true
				return _particle_pool[i]

	pool_exhausted.emit("particle")
	return null

func _release_particle(particle: GPUParticles2D) -> void:
	particle.emitting = false

	var index := _particle_pool.find(particle)
	if index >= 0:
		_particle_in_use[index] = false

func _acquire_shader() -> ShaderMaterial:
	for i in range(_shader_pool.size()):
		if not _shader_in_use[i]:
			_shader_in_use[i] = true
			return _shader_pool[i]

	if _shader_pool.size() < MAX_SHADER_POOL_SIZE:
		var new_size: int = int(_shader_pool.size() * POOL_EXPANSION_FACTOR)
		new_size = mini(new_size, MAX_SHADER_POOL_SIZE)

		for j in range(_shader_pool.size(), new_size):
			var shader := _create_shader_material()
			_shader_pool.append(shader)
			_shader_in_use.append(false)

		pool_expanded.emit("shader", new_size)

		for i in range(_shader_pool.size()):
			if not _shader_in_use[i]:
				_shader_in_use[i] = true
				return _shader_pool[i]

	pool_exhausted.emit("shader")
	return null

func _release_shader(shader: ShaderMaterial) -> void:
	var index := _shader_pool.find(shader)
	if index >= 0:
		_shader_in_use[index] = false

# ── Utility Methods ──────────────────────────────────────────────────────
func _generate_effect_id() -> String:
	_effect_id_counter += 1
	return "vfx_%d_%d" % [Time.get_ticks_msec(), _effect_id_counter]

func _can_play_effect(effect_type: String) -> bool:
	var now: int = Time.get_ticks_msec()
	var last_time: int = _effect_cooldowns.get(effect_type, 0)

	if now - last_time < EFFECT_COOLDOWN_MS:
		return false

	_effect_cooldowns[effect_type] = now
	return true

func _update_cooldowns() -> void:
	var now: int = Time.get_ticks_msec()
	var expired: Array[String] = []

	for effect_type in _effect_cooldowns.keys():
		if now - _effect_cooldowns[effect_type] > EFFECT_COOLDOWN_MS * 10:
			expired.append(effect_type)

	for effect_type in expired:
		_effect_cooldowns.erase(effect_type)

func _get_rarity_particle_count(rarity: String) -> int:
	match rarity:
		"common": return 15
		"rare": return 30
		"legendary": return 60
		_: return 15

func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color(0.9, 0.9, 0.9, 0.8)
		"rare": return Color(0.3, 0.6, 1.0, 0.8)
		"legendary": return Color(1.0, 0.8, 0.2, 0.9)
		_: return Color.WHITE

func _setup_ambient_particle(particle: GPUParticles2D, parent: Node) -> void:
	particle.amount = 1
	particle.lifetime = 3.0
	particle.one_shot = false
	particle.emitting = true

	if not particle.is_inside_tree():
		parent.add_child(particle)

func _apply_shader_to_target(shader: ShaderMaterial, target: Node2D, shader_type: String, params: Dictionary) -> void:
	shader.set_shader_parameter("type", shader_type)

	for param_name in params.keys():
		shader.set_shader_parameter(param_name, params[param_name])

	target.material = shader

# ── Performance Degradation ─────────────────────────────────────────────
func _check_performance_degradation() -> void:
	if _performance_monitor == null:
		return

	var fps: float = _performance_monitor.current_fps
	var new_level: DegradationLevel = _current_degradation

	if fps < 30.0:
		new_level = DegradationLevel.LEVEL_3_SIMPLIFY_TWEENS
	elif fps < 45.0:
		new_level = DegradationLevel.LEVEL_2_DISABLE_SHADERS
	elif fps < 55.0:
		new_level = DegradationLevel.LEVEL_1_REDUCE_PARTICLES
	elif fps > 55.0 and _current_degradation > DegradationLevel.NONE:
		# Recover one level at a time
		new_level = _current_degradation - 1

	if new_level != _current_degradation:
		var old_level: DegradationLevel = _current_degradation
		_current_degradation = new_level

		if new_level > old_level:
			performance_degraded.emit(new_level, "FPS: %.1f" % fps)
		else:
			performance_recovered.emit(old_level)

func get_current_degradation_level() -> int:
	return _current_degradation

func get_pool_stats() -> Dictionary:
	return {
		"particle_pool_size": _particle_pool.size(),
		"particle_in_use": _particle_in_use.count(true),
		"shader_pool_size": _shader_pool.size(),
		"shader_in_use": _shader_in_use.count(true),
		"active_effects": _active_effects.size()
	}

# ── Pool Return API for ParticleEffect ────────────────────────────────────
func return_particle_to_pool(particle: GPUParticles2D) -> void:
	if particle == null:
		return

	particle.emitting = false

	if particle.is_inside_tree() and particle.get_parent() != null:
		particle.get_parent().remove_child(particle)

	_release_particle(particle)
