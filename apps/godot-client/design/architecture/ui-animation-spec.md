# UI动画规范文档

**版本**: 1.0
**日期**: 2026-06-24
**引擎**: Godot 4.6
**语言**: GDScript (static typing)

---

## 1. 设计目标

- **流畅体验**: 所有动画60 FPS，无明显卡顿
- **性能可控**: 并发Tween数量限制50个，内存安全
- **一致性**: 统一时间曲线和缓动函数
- **可维护**: 动画定义标准化，易于复用

---

## 2. 过渡效果库

### 2.1 时间曲线定义

```gdscript
## ui_animation_presets.gd
## 动画预设库 - 统一时间曲线和缓动函数

class_name UIAnimationPresets

# ============================================================
# 缓动函数 (Easing Functions)
# ============================================================

## 标准缓动
const EASE_DEFAULT = Tween.EASE_IN_OUT
const EASE_IN = Tween.EASE_IN
const EASE_OUT = Tween.EASE_OUT

## 特殊缓动
const EASE_BACK = Tween.EASE_OUT          # 回弹效果 (用于精灵)
const EASE_ELASTIC = Tween.EASE_OUT       # 弹性效果 (用于弹跳)
const EASE_BOUNCE = Tween.EASE_OUT        # 弹跳效果 (用于掉落)

# ============================================================
# 过渡类型 (Trans Types)
# ============================================================

const TRANS_LINEAR = Tween.TRANS_LINEAR       # 匀速
const TRANS_QUAD = Tween.TRANS_QUAD           # 二次方 (默认UI)
const TRANS_CUBIC = Tween.TRANS_CUBIC         # 三次方 (页面切换)
const TRANS_SINE = Tween.TRANS_SINE           # 正弦 (呼吸动画)
const TRANS_BACK = Tween.TRANS_BACK           # 回弹 (按钮点击)
const TRANS_ELASTIC = Tween.TRANS_ELASTIC     # 弹性 (庆祝)
const TRANS_EXPO = Tween.TRANS_EXPO           # 指数 (快速)

# ============================================================
# 预设动画配置
# ============================================================

## 页面Push动画 (Layer 1→)
class PagePush:
    const DURATION: float = 0.3
    const TRANS = Tween.TRANS_CUBIC
    const EASE = Tween.EASE_OUT
    const START_OFFSET: float = 1920.0      # 从屏幕右侧外开始

## 页面Pop动画 (→Layer 1)
class PagePop:
    const DURATION: float = 0.25
    const TRANS = Tween.TRANS_CUBIC
    const EASE = Tween.EASE_IN
    const END_OFFSET: float = 1920.0        # 向屏幕右侧移出

## 淡入动画
class FadeIn:
    const DURATION: float = 0.2
    const TRANS = Tween.TRANS_QUAD
    const EASE = Tween.EASE_OUT

## 淡出动画
class FadeOut:
    const DURATION: float = 0.15
    const TRANS = Tween.TRANS_QUAD
    const EASE = Tween.EASE_IN

## 缩放弹出 (Badge解锁等)
class ScalePop:
    const DURATION: float = 0.4
    const TRANS = Tween.TRANS_BACK
    const EASE = Tween.EASE_OUT
    const START_SCALE: float = 0.5
    const END_SCALE: float = 1.0
    const OVERSHOOT: float = 1.15           # 回弹过头量

## 星星收集动画
class StarCollect:
    const FLY_DURATION: float = 0.6
    const FLY_TRANS = Tween.TRANS_QUAD
    const FLY_EASE = Tween.EASE_OUT
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
    const TRANS = Tween.TRANS_QUAD
    const SHOW_EASE = Tween.EASE_OUT
    const HIDE_EASE = Tween.EASE_IN
    const START_SCALE: float = 0.9
```

### 2.2 缓动函数选择指南

| 场景 | 推荐缓动 | 原因 |
|------|---------|------|
| 页面切换 | CUBIC + EASE_OUT | 平滑开始，快速结束 |
| 元素弹出 | BACK + EASE_OUT | 回弹感，有生命力 |
| 呼吸动画 | SINE + EASE_IN_OUT | 自然呼吸节奏 |
| 按钮点击 | QUAD + EASE_OUT | 快速响应 |
| 掉落/失败 | BOUNCE + EASE_OUT | 弹跳感 |
| 庆祝/成功 | ELASTIC + EASE_OUT | 弹性庆祝 |
| 线性移动 | LINEAR | 匀速机械运动 |

---

## 3. 标准动画定义

### 3.1 淡入淡出 (Fade)

```gdscript
## 淡入实现
func fade_in(target: CanvasItem, duration: float = UIAnimationPresets.FadeIn.DURATION) -> Tween:
    target.modulate.a = 0.0
    target.visible = true

    var tween = target.create_tween()
    tween.set_trans(UIAnimationPresets.FadeIn.TRANS)
    tween.set_ease(UIAnimationPresets.FadeIn.EASE)
    tween.tween_property(target, "modulate:a", 1.0, duration)

    return tween

## 淡出实现
func fade_out(target: CanvasItem, duration: float = UIAnimationPresets.FadeOut.DURATION) -> Tween:
    var tween = target.create_tween()
    tween.set_trans(UIAnimationPresets.FadeOut.TRANS)
    tween.set_ease(UIAnimationPresets.FadeOut.EASE)
    tween.tween_property(target, "modulate:a", 0.0, duration)
    tween.tween_callback(func(): target.visible = false)

    return tween
```

### 3.2 滑入滑出 (Slide)

```gdscript
## 从右滑入
func slide_in_from_right(target: Control, duration: float = UIAnimationPresets.PagePush.DURATION) -> Tween:
    var viewport_width = target.get_viewport().get_visible_rect().size.x
    target.position.x = viewport_width
    target.visible = true

    var tween = target.create_tween()
    tween.set_trans(UIAnimationPresets.PagePush.TRANS)
    tween.set_ease(UIAnimationPresets.PagePush.EASE)
    tween.tween_property(target, "position:x", 0.0, duration)

    return tween

## 向左滑出
func slide_out_to_left(target: Control, duration: float = UIAnimationPresets.PagePop.DURATION) -> Tween:
    var viewport_width = target.get_viewport().get_visible_rect().size.x

    var tween = target.create_tween()
    tween.set_trans(UIAnimationPresets.PagePop.TRANS)
    tween.set_ease(UIAnimationPresets.PagePop.EASE)
    tween.tween_property(target, "position:x", -viewport_width, duration)
    tween.tween_callback(func(): target.visible = false)

    return tween
```

### 3.3 缩放动画 (Scale)

```gdscript
## 弹出缩放 (带回弹)
func scale_pop(target: Control, callback: Callable = Callable()) -> Tween:
    target.scale = Vector2(UIAnimationPresets.ScalePop.START_SCALE,
                           UIAnimationPresets.ScalePop.START_SCALE)
    target.visible = true

    var tween = target.create_tween()
    tween.set_trans(UIAnimationPresets.ScalePop.TRANS)
    tween.set_ease(UIAnimationPresets.ScalePop.EASE)

    # 先弹过头
    tween.tween_property(target, "scale",
        Vector2(UIAnimationPresets.ScalePop.OVERSHOOT, UIAnimationPresets.ScalePop.OVERSHOOT),
        UIAnimationPresets.ScalePop.DURATION * 0.6)

    # 再回到正常
    tween.tween_property(target, "scale",
        Vector2(UIAnimationPresets.ScalePop.END_SCALE, UIAnimationPresets.ScalePop.END_SCALE),
        UIAnimationPresets.ScalePop.DURATION * 0.4)

    if callback.is_valid():
        tween.tween_callback(callback)

    return tween
```

---

## 4. 星星飞行动画详细实现

### 4.1 动画流程

```
评分显示 (0-0.3s)
    ↓
星星飞向星星条 (0.3-0.9s)
    ├─ 位置插值 (贝塞尔曲线)
    ├─ 旋转 (720°)
    ├─ 缩放脉冲
    ↓
星星条增长 (0.9-1.0s)
    ↓
完成回调 (触发Spark反馈)
```

### 4.2 贝塞尔曲线实现

```gdscript
## 二次贝塞尔曲线计算
func _quadratic_bezier(p0: Vector2, p1: Vector2, p2: Vector2, t: float) -> Vector2:
    var u = 1.0 - t
    return u * u * p0 + 2.0 * u * t * p1 + t * t * p2
```

---

## 5. CoachOverlay气泡动画规范

### 5.1 气泡显示动画

```gdscript
## 显示气泡 (带弹性回弹)
func show_bubble(bubble: Panel, text_label: RichTextLabel, text: String) -> Tween:
    # 设置文本
    text_label.text = text
    bubble.visible = true

    # 初始状态
    bubble.modulate.a = 0.0
    bubble.scale = Vector2(0.9, 0.9)

    var tween = bubble.create_tween()
    tween.set_trans(UIAnimationPresets.BubbleAnim.TRANS)
    tween.set_parallel(true)

    # 淡入
    tween.tween_property(bubble, "modulate:a",
        1.0,
        UIAnimationPresets.BubbleAnim.SHOW_DURATION)

    # 缩放 (先回弹再稳定)
    tween.tween_property(bubble, "scale",
        Vector2(1.05, 1.05),
        UIAnimationPresets.BubbleAnim.SHOW_DURATION * 0.6)

    tween.set_parallel(false)
    tween.tween_property(bubble, "scale",
        Vector2(1.0, 1.0),
        UIAnimationPresets.BubbleAnim.SHOW_DURATION * 0.4)

    return tween
```

### 5.2 Spark呼吸动画

```gdscript
## Spark呼吸浮动动画 (无限循环)
func start_idle_breathing(sprite: AnimatedSprite2D, base_position: Vector2) -> Array[Tween]:
    var tweens: Array[Tween] = []

    # 垂直浮动
    var float_tween = sprite.create_tween()
    float_tween.set_loops()
    float_tween.set_trans(Tween.TRANS_SINE)
    float_tween.set_ease(Tween.EASE_IN_OUT)
    float_tween.tween_property(sprite, "position:y",
        base_position.y - UIAnimationPresets.SparkAnim.IDLE_FLOAT_AMP,
        UIAnimationPresets.SparkAnim.IDLE_FLOAT_PERIOD / 2.0)
    float_tween.tween_property(sprite, "position:y",
        base_position.y + UIAnimationPresets.SparkAnim.IDLE_FLOAT_AMP,
        UIAnimationPresets.SparkAnim.IDLE_FLOAT_PERIOD / 2.0)
    tweens.append(float_tween)

    # 呼吸缩放
    var breathe_tween = sprite.create_tween()
    breathe_tween.set_loops()
    breathe_tween.set_trans(Tween.TRANS_SINE)
    breathe_tween.set_ease(Tween.EASE_IN_OUT)
    breathe_tween.tween_property(sprite, "scale",
        Vector2(UIAnimationPresets.SparkAnim.BREATHE_SCALE, UIAnimationPresets.SparkAnim.BREATHE_SCALE),
        UIAnimationPresets.SparkAnim.BREATHE_PERIOD / 2.0)
    breathe_tween.tween_property(sprite, "scale",
        Vector2(1.0, 1.0),
        UIAnimationPresets.SparkAnim.BREATHE_PERIOD / 2.0)
    tweens.append(breathe_tween)

    return tweens
```

---

## 6. Tween生命周期管理

### 6.1 UITweenManager 实现

```gdscript
## ui_tween_manager.gd
## Tween生命周期管理 — 确保并发数量限制和内存安全

class_name UITweenManager
extends Node

## 最大并发Tween数量 (性能预算)
const MAX_ACTIVE_TWEENS: int = 50

## Tween注册表
var _active_tweens: Dictionary = {}      # String -> Tween
var _tween_counter: int = 0

## 信号
signal tween_started(tween_id: String)
signal tween_completed(tween_id: String)
signal tween_killed(tween_id: String)
signal pool_exhausted()

## 注册Tween
func register_tween(category: String, tween: Tween) -> String:
    # 检查并发限制
    if _active_tweens.size() >= MAX_ACTIVE_TWEENS:
        push_warning("[UITweenManager] Tween池已满 (%d/%d)，拒绝新动画" % [_active_tweens.size(), MAX_ACTIVE_TWEENS])
        pool_exhausted.emit()
        # 杀死最旧的非关键Tween
        _kill_oldest_non_critical()

    var tween_id = "%s_%d_%d" % [category, Time.get_ticks_msec(), _tween_counter]
    _tween_counter += 1

    _active_tweens[tween_id] = tween

    # 绑定完成回调
    tween.finished.connect(_on_tween_finished.bind(tween_id))

    tween_started.emit(tween_id)
    return tween_id

## 杀死指定Tween
func kill_tween(tween_id: String) -> void:
    if not _active_tweens.has(tween_id):
        return

    var tween: Tween = _active_tweens[tween_id]
    if tween and tween.is_valid():
        tween.kill()

    _active_tweens.erase(tween_id)
    tween_killed.emit(tween_id)

## 杀死所有Tween (场景切换用)
func kill_all() -> void:
    for tween_id in _active_tweens.keys():
        var tween: Tween = _active_tweens[tween_id]
        if tween and tween.is_valid():
            tween.kill()

    _active_tweens.clear()

## 获取活跃Tween数量
func get_active_count() -> int:
    return _active_tweens.size()

## 私有: Tween完成回调
func _on_tween_finished(tween_id: String) -> void:
    if _active_tweens.has(tween_id):
        _active_tweens.erase(tween_id)
        tween_completed.emit(tween_id)
```

---

## 7. 性能预算

### 7.1 并发Tween限制

| 类别 | 最大并发 | 优先级 | 说明 |
|------|---------|--------|------|
| 场景过渡 | 1 | 高 | 必须保证 |
| 对话动画 | 3 | 高 | 气泡+文字+头像 |
| UI反馈 | 10 | 中 | 按钮点击等 |
| 特效动画 | 20 | 中 | 星星飞行等 |
| 环境动画 | 16 | 低 | 可降级 |
| **总计** | **50** | - | 硬限制 |

### 7.2 单动画性能预算

| 动画类型 | 目标耗时 | 最大耗时 | 触发降级 |
|---------|---------|---------|---------|
| 淡入淡出 | 2ms | 5ms | >5ms |
| 滑入滑出 | 3ms | 8ms | >8ms |
| 缩放动画 | 2ms | 5ms | >5ms |
| 星星飞行 | 5ms | 10ms | >10ms |
| 粒子特效 | 3ms | 8ms | >8ms |

---

## 8. Tween安全模式 (防止内存泄漏)

### 8.1 正确使用示例

```gdscript
## 错误示范 ❌
func bad_example() -> void:
    # Tween没有保存引用，可能被GC
    create_tween().tween_property(sprite, "position", end_pos, 1.0)

## 正确示范 ✅
func good_example() -> void:
    var tween = create_tween()
    tween.tween_property(sprite, "position", end_pos, 1.0)

    # 保存到类成员或管理器
    _current_tween = tween
    # 或
    _tween_manager.register_tween("movement", tween)
```

---

## 9. 代码检查清单

### 9.1 Tween创建检查

- [ ] 总是保存Tween引用到变量
- [ ] 使用_tween_manager.register_tween()注册
- [ ] 设置trans和ease
- [ ] 绑定完成回调进行清理
- [ ] 检查并发数量限制

### 9.2 内存安全检查

- [ ] 节点释放前kill相关Tween
- [ ] 避免在循环中创建大量Tween
- [ ] 场景切换时调用kill_all()
- [ ] 定期调用cleanup()清理无效Tween

### 9.3 性能检查

- [ ] 单动画耗时 < 5ms
- [ ] 并发Tween < 50
- [ ] 使用简单缓动函数(避免复杂曲线)
- [ ] 移动端测试降级策略

---

**文档结束**