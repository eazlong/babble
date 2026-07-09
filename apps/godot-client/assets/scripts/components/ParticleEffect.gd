## ParticleEffect.gd
## 粒子效果组件 — 封装 GPUParticles2D，集成 VFXManager 对象池
## Godot 4.6, GDScript static typing
class_name ParticleEffect
extends GPUParticles2D

# ── Enums ───────────────────────────────────────────────────────────────────
enum EffectType {
    SPIRIT_UNLOCK_COMMON,
    SPIRIT_UNLOCK_RARE,
    SPIRIT_UNLOCK_LEGENDARY,
    MAGIC_ACTIVATION,
    WEATHER_RAIN,
    WEATHER_SNOW,
    AMBIENT_FLOAT
}

# ── Constants ──────────────────────────────────────────────────────────────
const PRESET_PATHS: Dictionary = {
    EffectType.SPIRIT_UNLOCK_COMMON: "res://assets/resources/vfx_presets/spirit_unlock_common.tres",
    EffectType.SPIRIT_UNLOCK_RARE: "res://assets/resources/vfx_presets/spirit_unlock_rare.tres",
    EffectType.SPIRIT_UNLOCK_LEGENDARY: "res://assets/resources/vfx_presets/spirit_unlock_legendary.tres",
    EffectType.MAGIC_ACTIVATION: "res://assets/resources/vfx_presets/magic_activation.tres",
    EffectType.AMBIENT_FLOAT: "res://assets/resources/vfx_presets/ambient_float.tres"
}

const DEFAULT_COLORS: Dictionary = {
    EffectType.SPIRIT_UNLOCK_COMMON: Color(0.9, 0.9, 0.95, 0.8),
    EffectType.SPIRIT_UNLOCK_RARE: Color(0.3, 0.6, 1.0, 0.8),
    EffectType.SPIRIT_UNLOCK_LEGENDARY: Color(1.0, 0.8, 0.2, 0.9),
    EffectType.MAGIC_ACTIVATION: Color(0.8, 0.4, 1.0, 0.8),
    EffectType.WEATHER_RAIN: Color(0.6, 0.7, 0.9, 0.6),
    EffectType.WEATHER_SNOW: Color(0.95, 0.95, 1.0, 0.7),
    EffectType.AMBIENT_FLOAT: Color(0.8, 0.9, 1.0, 0.5)
}

const DEFAULT_AMOUNTS: Dictionary = {
    EffectType.SPIRIT_UNLOCK_COMMON: 15,
    EffectType.SPIRIT_UNLOCK_RARE: 30,
    EffectType.SPIRIT_UNLOCK_LEGENDARY: 60,
    EffectType.MAGIC_ACTIVATION: 20,
    EffectType.WEATHER_RAIN: 100,
    EffectType.WEATHER_SNOW: 80,
    EffectType.AMBIENT_FLOAT: 5
}

# ── Exported Variables ─────────────────────────────────────────────────────
@export var effect_type: EffectType = EffectType.SPIRIT_UNLOCK_COMMON
@export var auto_play: bool = false
@export var one_shot: bool = true
@export var lifetime_override: float = 0.0

# ── Internal State ─────────────────────────────────────────────────────────
var _is_from_pool: bool = false
var _default_lifetime: float = 1.0
var _stop_scheduled: bool = false

# ── Lifecycle ──────────────────────────────────────────────────────────────
func _ready() -> void:
    _default_lifetime = lifetime
    _apply_preset()
    _configure_for_effect_type()

    if one_shot:
        self.one_shot = true

    if auto_play:
        play()

func _exit_tree() -> void:
    if _is_from_pool and emitting:
        _return_to_pool()

# ── Public API ──────────────────────────────────────────────────────────────
func play() -> void:
    if emitting:
        restart()
    else:
        emitting = true

    _stop_scheduled = false

    if one_shot:
        _schedule_stop()

func stop() -> void:
    emitting = false
    _stop_scheduled = false

func restart() -> void:
    emitting = false
    await get_tree().process_frame
    emitting = true

    if one_shot:
        _schedule_stop()

func set_effect_type(new_type: EffectType) -> void:
    effect_type = new_type
    _apply_preset()
    _configure_for_effect_type()

func mark_as_pooled() -> void:
    _is_from_pool = true

func is_from_pool() -> bool:
    return _is_from_pool

# ── Private Methods ──────────────────────────────────────────────────────────
func _apply_preset() -> void:
    if PRESET_PATHS.has(effect_type):
        var preset_path: String = PRESET_PATHS[effect_type]
        if ResourceLoader.exists(preset_path):
            var preset: Resource = load(preset_path)
            if preset is ParticleProcessMaterial:
                process_material = preset
                return

    _apply_fallback_config()

func _configure_for_effect_type() -> void:
    match effect_type:
        EffectType.SPIRIT_UNLOCK_COMMON, EffectType.SPIRIT_UNLOCK_RARE, EffectType.SPIRIT_UNLOCK_LEGENDARY:
            explosiveness = 1.0
            randomness = 0.3
        EffectType.MAGIC_ACTIVATION:
            explosiveness = 0.8
            randomness = 0.2
        EffectType.WEATHER_RAIN, EffectType.WEATHER_SNOW:
            one_shot = false
            self.one_shot = false
            explosiveness = 0.0
        EffectType.AMBIENT_FLOAT:
            one_shot = false
            self.one_shot = false
            explosiveness = 0.0
            amount = DEFAULT_AMOUNTS.get(effect_type, 5)

    if lifetime_override > 0.0:
        lifetime = lifetime_override

func _apply_fallback_config() -> void:
    if process_material == null:
        process_material = ParticleProcessMaterial.new()

    var material: ParticleProcessMaterial = process_material as ParticleProcessMaterial
    if material == null:
        return

    material.particle_flag_disable_z = true
    material.direction = Vector3(0.0, -1.0, 0.0)
    material.spread = 45.0
    material.initial_velocity_min = 50.0
    material.initial_velocity_max = 100.0
    material.gravity = Vector3(0.0, 98.0, 0.0)
    material.scale_min = 0.5
    material.scale_max = 1.5

    if DEFAULT_COLORS.has(effect_type):
        material.color = DEFAULT_COLORS[effect_type]

    if DEFAULT_AMOUNTS.has(effect_type):
        amount = DEFAULT_AMOUNTS[effect_type]

func _schedule_stop() -> void:
    if _stop_scheduled:
        return

    _stop_scheduled = true
    var delay: float = lifetime_override if lifetime_override > 0.0 else lifetime

    var timer: SceneTreeTimer = get_tree().create_timer(delay)
    timer.timeout.connect(_on_lifetime_complete)

func _on_lifetime_complete() -> void:
    emitting = false
    _stop_scheduled = false

    if _is_from_pool:
        _return_to_pool()

func _return_to_pool() -> void:
    if VFXManager.has_method("return_particle_to_pool"):
        VFXManager.return_particle_to_pool(self)
    else:
        queue_free()
