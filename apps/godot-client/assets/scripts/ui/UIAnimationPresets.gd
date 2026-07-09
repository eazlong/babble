## UIAnimationPresets.gd
## UI动画预设库 — 统一时间曲线和缓动函数
## 设计目标：标准化动画配置，易于复用
## Godot 4.6, GDScript static typing

class_name UIAnimationPresets
extends RefCounted

## ============================================================
## 缓动函数 (Easing Functions)
## ============================================================

## 标准缓动
const EASE_DEFAULT: int = Tween.EASE_IN_OUT
const EASE_IN: int = Tween.EASE_IN
const EASE_OUT: int = Tween.EASE_OUT

## 特殊缓动
const EASE_BACK: int = Tween.EASE_OUT          # 回弹效果 (用于精灵)
const EASE_ELASTIC: int = Tween.EASE_OUT       # 弹性效果 (用于弹跳)
const EASE_BOUNCE: int = Tween.EASE_OUT        # 弹跳效果 (用于掉落)

## ============================================================
## 过渡类型 (Trans Types)
## ============================================================

const TRANS_LINEAR: int = Tween.TRANS_LINEAR       # 匀速
const TRANS_QUAD: int = Tween.TRANS_QUAD           # 二次方 (默认UI)
const TRANS_CUBIC: int = Tween.TRANS_CUBIC         # 三次方 (页面切换)
const TRANS_SINE: int = Tween.TRANS_SINE           # 正弦 (呼吸动画)
const TRANS_BACK: int = Tween.TRANS_BACK           # 回弹 (按钮点击)
const TRANS_BOUNCE: int = Tween.TRANS_BOUNCE       # 弹跳 (掉落/失败)
const TRANS_ELASTIC: int = Tween.TRANS_ELASTIC     # 弹性 (庆祝)
const TRANS_EXPO: int = Tween.TRANS_EXPO           # 指数 (快速)

## ============================================================
## 预设动画配置类
## ============================================================

## 页面Push动画 (Layer 1→)
class PagePush:
	const DURATION: float = 0.3
	const TRANS: int = Tween.TRANS_CUBIC
	const EASE: int = Tween.EASE_OUT
	const START_OFFSET: float = 1920.0      # 从屏幕右侧外开始

## 页面Pop动画 (→Layer 1)
class PagePop:
	const DURATION: float = 0.25
	const TRANS: int = Tween.TRANS_CUBIC
	const EASE: int = Tween.EASE_IN
	const END_OFFSET: float = 1920.0        # 向屏幕右侧移出

## 淡入动画
class FadeIn:
	const DURATION: float = 0.2
	const TRANS: int = Tween.TRANS_QUAD
	const EASE: int = Tween.EASE_OUT

## 淡出动画
class FadeOut:
	const DURATION: float = 0.15
	const TRANS: int = Tween.TRANS_QUAD
	const EASE: int = Tween.EASE_IN

## 缩放弹出 (Badge解锁等)
class ScalePop:
	const DURATION: float = 0.4
	const TRANS: int = Tween.TRANS_BACK
	const EASE: int = Tween.EASE_OUT
	const START_SCALE: float = 0.5
	const END_SCALE: float = 1.0
	const OVERSHOOT: float = 1.15           # 回弹过头量

## 星星收集动画
class StarCollect:
	const FLY_DURATION: float = 0.6
	const FLY_TRANS: int = Tween.TRANS_QUAD
	const FLY_EASE: int = Tween.EASE_OUT
	const SCALE_DURATION: float = 0.3
	const ROTATION: float = 720.0            # 旋转两圈

## Spark动画
class SparkAnim:
	const FLY_IN_DURATION: float = 0.5
	const FLY_OUT_DURATION: float = 0.4
	const IDLE_FLOAT_AMP: float = 6.0      # 浮动幅度(px)
	const IDLE_FLOAT_PERIOD: float = 4.0   # 浮动周期(s)
	const BREATHE_SCALE: float = 1.04      # 呼吸缩放
	const BREATHE_PERIOD: float = 4.0      # 呼吸周期(s)

## 气泡显示/隐藏
class BubbleAnim:
	const SHOW_DURATION: float = 0.3
	const HIDE_DURATION: float = 0.25
	const TRANS: int = Tween.TRANS_QUAD
	const SHOW_EASE: int = Tween.EASE_OUT
	const HIDE_EASE: int = Tween.EASE_IN
	const START_SCALE: float = 0.9

## ============================================================
## 缓动函数选择指南
## ============================================================

static func get_easing_guide() -> Dictionary:
	return {
		"页面切换": {"trans": TRANS_CUBIC, "ease": EASE_OUT, "reason": "平滑开始，快速结束"},
		"元素弹出": {"trans": TRANS_BACK, "ease": EASE_OUT, "reason": "回弹感，有生命力"},
		"呼吸动画": {"trans": TRANS_SINE, "ease": EASE_DEFAULT, "reason": "自然呼吸节奏"},
		"按钮点击": {"trans": TRANS_QUAD, "ease": EASE_OUT, "reason": "快速响应"},
		"掉落/失败": {"trans": TRANS_BOUNCE, "ease": EASE_OUT, "reason": "弹跳感"},
		"庆祝/成功": {"trans": TRANS_ELASTIC, "ease": EASE_OUT, "reason": "弹性庆祝"},
		"线性移动": {"trans": TRANS_LINEAR, "ease": EASE_DEFAULT, "reason": "匀速机械运动"}
	}

## ============================================================
## 快速创建Tween配置
## ============================================================

static func apply_preset(tween: Tween, preset_class: Object) -> void:
	if preset_class.has("TRANS"):
		tween.set_trans(preset_class.TRANS)
	if preset_class.has("EASE"):
		tween.set_ease(preset_class.EASE)
