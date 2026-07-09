## RewardAnimation.gd
## 奖励展示动画 — Badge解锁仪式 + 粒子爆发 + 音效同步
## 设计目标：震撼的奖励反馈，视觉+听觉双重刺激
## Godot 4.6, GDScript static typing

class_name RewardAnimation
extends Control

## ============================================================
## 配置参数
## ============================================================

## Badge解锁动画参数
const BADGE_UNLOCK_DURATION: float = 0.6
const BADGE_SCALE_OVERSHOOT: float = 1.2
const PARTICLE_BURST_COUNT: int = 50

## ============================================================
## Node引用
## ============================================================

@onready var badge_container: Control = $BadgeContainer
@onready var badge_icon: TextureRect = $BadgeContainer/BadgeIcon
@onready var badge_label: Label = $BadgeContainer/BadgeLabel
@onready var particle_spawn_point: Marker2D = $ParticleSpawnPoint

## ============================================================
## 外部系统引用
## ============================================================

var _vfx_manager: VFXManager
var _audio_manager: AudioManager
var _tween_manager: UITweenManager

## ============================================================
## 初始化
## ============================================================

func _ready() -> void:
	# 获取全局系统引用
	_vfx_manager = get_node_or_null("/root/VFXManager")
	_audio_manager = get_node_or_null("/root/AudioManager")
	_tween_manager = get_node_or_null("/root/UITweenManager")

	# 初始隐藏
	visible = false
	modulate.a = 0.0
	if badge_container:
		badge_container.scale = Vector2(0.0, 0.0)

## ============================================================
## Badge解锁仪式动画
## ============================================================

func play_badge_unlock(badge_name: String, badge_icon_path: String = "") -> void:
	# 设置Badge内容
	if badge_label:
		badge_label.text = badge_name
	if badge_icon and badge_icon_path != "":
		var texture = load(badge_icon_path)
		if texture:
			badge_icon.texture = texture

	# 激活UIFramework Overlay层
	var ui_framework = get_node("/root/UIFramework")
	ui_framework.activate_overlay()

	# 开始动画序列
	visible = true
	_play_badge_popup()
	_play_particle_burst()
	_play_badge_sound()

## ============================================================
## Badge弹出动画 (ScalePop)
## ============================================================

func _play_badge_popup() -> void:
	if not badge_container:
		return

	# 使用ScalePop预设
	badge_container.scale = Vector2(UIAnimationPresets.ScalePop.START_SCALE,
	                                UIAnimationPresets.ScalePop.START_SCALE)
	badge_container.visible = true

	var tween = badge_container.create_tween()
	tween.set_trans(UIAnimationPresets.ScalePop.TRANS)
	tween.set_ease(UIAnimationPresets.ScalePop.EASE)

	# 第一阶段：弹出（ overshoot）
	tween.tween_property(badge_container, "scale",
	                     Vector2(BADGE_SCALE_OVERSHOOT, BADGE_SCALE_OVERSHOOT),
	                     BADGE_UNLOCK_DURATION * 0.7)

	# 第二阶段：回弹
	tween.tween_property(badge_container, "scale",
	                     Vector2(UIAnimationPresets.ScalePop.END_SCALE,
	                             UIAnimationPresets.ScalePop.END_SCALE),
	                     BADGE_UNLOCK_DURATION * 0.3)

	# 淡入效果
	var fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 1.0, 0.2)

	# 注册到TweenManager（如果有）
	if _tween_manager:
		_tween_manager.register_tween("reward", tween)

	# 自动隐藏（3秒后）
	tween.tween_interval(3.0)
	tween.tween_callback(_on_badge_unlock_complete)

## ============================================================
## 粒子爆发效果
## ============================================================

func _play_particle_burst() -> void:
	if not _vfx_manager or not particle_spawn_point:
		return

	# 调用VFXManager播放粒子效果
	var spawn_pos = particle_spawn_point.global_position

	# 粒子参数
	var particle_config = {
		"type": "explosion",
		"count": PARTICLE_BURST_COUNT,
		"duration": 1.5,
		"color": Color(1.0, 0.9, 0.3, 1.0),  # 金色
		"speed_min": 100.0,
		"speed_max": 300.0,
		"layer": VFXManager.VFXLayer.UI  # Layer 2
	}

	# 通过VFXManager播放
	_vfx_manager.play_particle_effect_at_position(
		"reward_burst",
		spawn_pos,
		particle_config
	)

## ============================================================
## 音效同步
## ============================================================

func _play_badge_sound() -> void:
	if not _audio_manager:
		return

	# 播放Badge解锁音效
	_audio_manager.play_sfx("badge_unlock")

	# 可选：播放欢呼音效（延迟0.3秒）
	await get_tree().create_timer(0.3).timeout
	_audio_manager.play_sfx("celebration")

## ============================================================
## 动画完成回调
## ============================================================

func _on_badge_unlock_complete() -> void:
	# 淡出隐藏
	var fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 0.0, 0.5)
	fade_tween.tween_callback(func():
		visible = false
		var ui_framework = get_node("/root/UIFramework")
		ui_framework.deactivate_overlay()
	)

## ============================================================
## XP奖励动画 (简化版)
## ============================================================

func play_xp_reward(xp_amount: int, leveled_up: bool = false) -> void:
	if badge_label:
		if leveled_up:
			badge_label.text = "升级！"
		else:
			badge_label.text = "+" + str(xp_amount) + " XP"

	visible = true

	# 简单淡入淡出
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.tween_interval(2.0)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func(): visible = false)

## ============================================================
## 区域解锁动画
## ============================================================

func play_area_unlock(area_name: String) -> void:
	if badge_label:
		badge_label.text = "解锁区域：" + area_name

	visible = true

	# 区域解锁用ScalePop + 地图闪光
	_play_badge_popup()

	if _audio_manager:
		_audio_manager.play_sfx("area_unlock")