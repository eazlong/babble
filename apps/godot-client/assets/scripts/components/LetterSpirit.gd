class_name LetterSpirit
extends Control

## 字母精灵（场景文档 v0.3 §5.2.1 / §5.2 五态）。
##
## 一个"符文精灵体"+ 叠在其上的字母字形 = 一个字母精灵。26 个 A–Z 共用同一张
## 精灵体贴图，靠字形区分；重复字母（apple 的两个 P）天然靠克隆第二个精灵解决。
##
## `body_texture` 为空时走程序化符文（_draw 画菱形符文 + 呼吸光环）。贴上真美术后
## **零代码改动**：只管给 `body_texture` 赋值，两条路径共用同一组状态与 Tween。
##
## 使用约束（很重要）：
## - 精灵必须挂在一个**不受容器布局管理**的父节点下（Container 会覆写 position，
##   精灵就飞不起来了）。控制器把所有精灵放进 visual_root 下的 SpiritLayer。
## - 同一时刻只允许**一个动作 Tween**（_action_tween）；呼吸 Tween 独立，可共存。
##   每次起飞/散落前都会 _kill_action()，避免两段 Tween 抢同一个 position。

signal flight_finished(letter: String)
signal merge_finished(letter: String)
signal scatter_finished(letter: String)

enum State {
	DORMANT,     ## 休眠态：岩壁上低亮度呼吸
	SUMMONED,    ## 召唤态：被叫到名字，亮起
	FLYING,      ## 飞行态：弧线飞向槽位
	SLOTTED,     ## 入槽态：停在槽位上（随后融入槽位字形）
	SCATTERING,  ## 散落态：抛物线回位（墨影，轻柔不刺眼）
	INSCRIBED,   ## 刻印态：已融入石碑铭文
}

const DEFAULT_SIZE: Vector2 = Vector2(64, 64)

## 休眠态的透明度。符文绝大部分时间都停在这个状态（`settle_at_home()` 直接进休眠），
## 所以这个值基本决定了"玩家能不能看清字母"。
## 原值 0.55 把本来就只占精灵体画布约 15% 的符文再砍掉一半亮度——实测游戏内
## 符文峰值亮度被压到比岩壁还低，"字母/符文徽章太暗、不突出"。
## 现在 0.82：仍然明显低于召唤态（1.0 + 暖色 RGB 增益 + 弹一下 + 闪光），
## "睡着 / 醒了"的区分还在，但休眠时字母已经读得清。
const DORMANT_ALPHA: float = 0.82

## 字形配色。精灵体中心很亮——实测三版候选精灵体中心亮度 206–217，
## 而原来的暖浅字形亮度约 226：**字形会直接融进精灵体里读不出来**。
## 深墨字 + 暖浅描边两头都顾：亮精灵体上靠深字读，暗底/半透明时靠浅描边读。
const GLYPH_INK: Color = Color(0.09, 0.13, 0.12, 1.0)
const GLYPH_OUTLINE: Color = Color(0.96, 0.93, 0.78, 1.0)
const GLYPH_OUTLINE_SIZE: int = 4

## 精灵体贴图。留空 = 程序化符文。
@export var body_texture: Texture2D

var letter: String = ""
var state: State = State.DORMANT

## 岩壁上的原始位置（父节点坐标系）。散落回位回到这里。
var home_position: Vector2 = Vector2.ZERO

## 动作 Tween 是否在跑（供控制器与测试观察，不依赖引擎内部状态）。
var is_animating: bool = false

var _body: TextureRect
var _glyph: Label
var _action_tween: Tween
var _breath_tween: Tween
var _breath: float = 0.0
var _focus: float = 1.0
var _flight_from: Vector2 = Vector2.ZERO
var _flight_to: Vector2 = Vector2.ZERO
var _flight_arc: float = 0.0

## 符文是否已现身（演出拍 8）。场景刚进入时 26 个符文都在沉睡（alpha 恒为 0），
## 唤醒守灵后才依次浮现。**"沉睡"与"焦点为 0"是两件事**：焦点高亮不能把沉睡的符文
## 点亮，所以这个开关由组件自己守，而不是指望控制器记得别去改 modulate。
var revealed: bool = true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = DEFAULT_SIZE
	if size == Vector2.ZERO:
		size = DEFAULT_SIZE
	_ensure_children()

func _ensure_children() -> void:
	if _body == null:
		_body = TextureRect.new()
		_body.name = "Body"
		_body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_body.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_body.set_anchors_preset(Control.PRESET_FULL_RECT)
		_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_body)
	if _glyph == null:
		_glyph = Label.new()
		_glyph.name = "Glyph"
		_glyph.set_anchors_preset(Control.PRESET_FULL_RECT)
		_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_glyph.add_theme_font_size_override("font_size", 32)
		_glyph.add_theme_color_override("font_color", GLYPH_INK)
		_glyph.add_theme_color_override("font_outline_color", GLYPH_OUTLINE)
		_glyph.add_theme_constant_override("outline_size", GLYPH_OUTLINE_SIZE)
		_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_glyph)
	_apply_body_texture()

func _apply_body_texture() -> void:
	if _body == null:
		return
	_body.texture = body_texture
	_body.visible = body_texture != null
	# 贴图与程序化符文互斥：有贴图画贴图，没贴图走 _draw
	queue_redraw()

## 初始化一个字母精灵。texture 为空则走程序化符文。
func setup(p_letter: String, texture: Texture2D = null) -> void:
	letter = p_letter
	body_texture = texture
	_ensure_children()
	if _glyph:
		_glyph.text = p_letter
	_apply_body_texture()

## 记录岩壁原位（父节点坐标系）并立即回到休眠态。
func settle_at_home(p_home: Vector2) -> void:
	home_position = p_home
	position = p_home
	visible = true
	scale = Vector2.ONE
	rotation = 0.0
	play_dormant()

# ── 沉睡 / 现身（演出拍 8）────────────────────────────────────────

## 场景刚进入时把 26 个符文设为沉睡。沉睡的符文 alpha 恒为 0，
## 且**任何** set_focus / play_dormant 都不会把它点亮。
func set_revealed(value: bool) -> void:
	revealed = value
	_update_modulate_alpha()

## 现身：从全透明淡入到"当前状态该有的亮度"，并轻微放大回弹。
func play_reveal(duration_ms: int = 250) -> void:
	revealed = true
	visible = true
	var target_alpha: float = _dormant_alpha() if state == State.DORMANT else 1.0
	var target: Color = Color(_focus, _focus, _focus, target_alpha)
	if not is_inside_tree():
		modulate = target
		return
	_kill_action()
	is_animating = true
	var dur: float = maxf(float(duration_ms), 1.0) / 1000.0
	modulate = Color(_focus, _focus, _focus, 0.0)
	_action_tween = create_tween()
	_action_tween.tween_property(self, "modulate", target, dur)
	_action_tween.parallel().tween_property(self, "scale", Vector2(1.14, 1.14), dur * 0.7)
	_action_tween.tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK)
	_action_tween.tween_callback(func() -> void: is_animating = false)

func is_sleeping() -> bool:
	return not revealed

func _dormant_alpha() -> float:
	if not revealed:
		return 0.0
	return DORMANT_ALPHA

## 唯一的 modulate 写入口：把"沉睡 / 焦点 / 状态"三件事合成一个 alpha。
func _update_modulate_alpha() -> void:
	var alpha: float = 1.0 if state != State.DORMANT else _dormant_alpha()
	if not revealed:
		alpha = 0.0
	modulate = Color(_focus, _focus, _focus, alpha)
	queue_redraw()

# ── 休眠态：呼吸 ─────────────────────────────────────────────────────

## 低亮度 + 呼吸光环（§5.2 休眠态）。呼吸 Tween 与动作 Tween 分离，可长期共存。
func play_dormant() -> void:
	state = State.DORMANT
	visible = true
	_update_modulate_alpha()
	if not is_inside_tree():
		return
	_kill_breath()
	_breath_tween = create_tween()
	_breath_tween.set_loops()
	_breath_tween.tween_method(_set_breath, 0.0, 1.0, 1.6).set_trans(Tween.TRANS_SINE)
	_breath_tween.tween_method(_set_breath, 1.0, 0.0, 1.6).set_trans(Tween.TRANS_SINE)

func _set_breath(value: float) -> void:
	_breath = clampf(value, 0.0, 1.0)
	queue_redraw()

# ── 召唤态：亮起（演出拍 1）──────────────────────────────────────────

## 被叫到名字 → 亮起并轻微弹一下（§5.2 召唤态）。
func play_summon_flash() -> void:
	state = State.SUMMONED
	visible = true
	modulate = Color(1.25, 1.2, 0.85, 1.0)
	_ensure_children()
	if not is_inside_tree():
		return
	_kill_action()
	_action_tween = create_tween()
	_action_tween.set_parallel(true)
	_action_tween.tween_property(self, "scale", Vector2(1.18, 1.18), 0.12).set_trans(Tween.TRANS_BACK)
	_action_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.18)

# ── 飞行态：弧线飞入槽位（演出拍 1 的后半）──────────────────────────

## 弧线飞向槽位中心。飞行过程中 scale 收到 1.0（消除召唤态的放大）。
func fly_to(target_center: Vector2, duration_ms: int, arc_height: float = 90.0) -> void:
	state = State.FLYING
	visible = true
	modulate = Color(1, 1, 1, 1)
	_flight_from = position
	_flight_to = target_center - size * 0.5
	_flight_arc = maxf(arc_height, 0.0)
	is_animating = true
	_ensure_children()
	if not is_inside_tree():
		# 不在场景树里（纯逻辑测试）：直接落位，不发 Tween
		position = _flight_to
		_finish_flight()
		return
	_kill_action()
	# 用 tween_method 而不是 tween_property：抛物线需要一个中间抬升的量
	_action_tween = create_tween()
	_action_tween.tween_method(_apply_flight, 0.0, 1.0, maxf(duration_ms, 1) / 1000.0) \
		.set_trans(Tween.TRANS_SINE)
	_action_tween.tween_callback(_finish_flight)
	_action_tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.12)

## 抛物线插值：t=0 在出发点，t=1 在槽位，t=0.5 抬到最高点。
## 单独暴露成方法是为了能在测试里直接验证几何，不依赖帧时序。
func _apply_flight(t: float) -> void:
	var clamped: float = clampf(t, 0.0, 1.0)
	var base: Vector2 = _flight_from.lerp(_flight_to, clamped)
	base.y -= _flight_arc * sin(PI * clamped)
	position = base

func _finish_flight() -> void:
	is_animating = false
	state = State.SLOTTED
	position = _flight_to
	flight_finished.emit(letter)

## 入槽：融进槽位字形，然后隐去自己（槽位条随后显示字形，避免双重描字）。
func merge_into_slot(duration_ms: int = 180) -> void:
	if not is_inside_tree():
		state = State.SLOTTED
		visible = false
		merge_finished.emit(letter)
		return
	_kill_action()
	is_animating = true
	_action_tween = create_tween()
	_action_tween.set_parallel(true)
	_action_tween.tween_property(self, "scale", Vector2(0.6, 0.6), maxf(duration_ms, 1) / 1000.0)
	_action_tween.tween_property(self, "modulate", Color(1, 1, 1, 0), maxf(duration_ms, 1) / 1000.0)
	_action_tween.chain().tween_callback(func() -> void:
		is_animating = false
		visible = false
		merge_finished.emit(letter)
	)

# ── 散落态：抛物线回位（演出拍 3）──────────────────────────────────

## 从当前位置抛物线回岩壁原位，落回低亮度休眠态。用于墨影词牌——轻柔，不刺眼。
func scatter_home(duration_ms: int, arc_height: float = 70.0) -> void:
	state = State.SCATTERING
	visible = true
	modulate = Color(0.75, 0.72, 0.8, 1.0)
	_flight_from = position
	_flight_to = home_position
	_flight_arc = maxf(arc_height, 0.0)
	is_animating = true
	_ensure_children()
	if not is_inside_tree():
		position = home_position
		_finish_scatter()
		return
	_kill_action()
	_action_tween = create_tween()
	_action_tween.tween_method(_apply_flight, 0.0, 1.0, maxf(duration_ms, 1) / 1000.0) \
		.set_trans(Tween.TRANS_SINE)
	_action_tween.tween_callback(_finish_scatter)

func _finish_scatter() -> void:
	is_animating = false
	position = home_position
	scatter_finished.emit(letter)
	play_dormant()

# ── 刻印态：融入石碑（演出拍 2 的收尾）──────────────────────────────

## 刻印成功：不飞回原位，而是收缩融入石碑铭文（§5.2 刻印态）。
func inscribe_into_stele(target_center: Vector2, duration_ms: int = 320) -> void:
	state = State.INSCRIBED
	visible = true
	_flight_from = position
	_flight_to = target_center - size * 0.5
	_flight_arc = 20.0
	is_animating = true
	_ensure_children()
	if not is_inside_tree():
		position = _flight_to
		visible = false
		is_animating = false
		return
	_kill_action()
	_action_tween = create_tween()
	_action_tween.set_parallel(true)
	_action_tween.tween_method(_apply_flight, 0.0, 1.0, maxf(duration_ms, 1) / 1000.0)
	_action_tween.tween_property(self, "scale", Vector2(0.35, 0.35), maxf(duration_ms, 1) / 1000.0)
	_action_tween.tween_property(self, "modulate", Color(1, 0.95, 0.7, 0), maxf(duration_ms, 1) / 1000.0)
	_action_tween.chain().tween_callback(func() -> void:
		is_animating = false
		visible = false
	)

# ── 焦点高亮（演出拍 4–7）──────────────────────────────────────────

## level: 0 = 变暗退后，1 = 正常，>1 = 泛光聚焦。
## 沉睡中的符文不受焦点影响——唤醒之前它就该是看不见的（演出拍 8）。
func set_focus(level: float) -> void:
	_focus = maxf(level, 0.0)
	_update_modulate_alpha()

func get_focus() -> float:
	return _focus

# ── Tween 生命周期 ──────────────────────────────────────────────────

## 打断动作 Tween（重复召唤同一字母、或中途退出时用）。
func kill_action() -> void:
	_kill_action()
	is_animating = false

func _kill_action() -> void:
	if _action_tween != null and _action_tween.is_valid():
		_action_tween.kill()
	_action_tween = null

func _kill_breath() -> void:
	if _breath_tween != null and _breath_tween.is_valid():
		_breath_tween.kill()
	_breath_tween = null

func _exit_tree() -> void:
	_kill_action()
	_kill_breath()

# ── 程序化符文（body_texture 为空时的兜底绘制）─────────────────────

func _draw() -> void:
	if body_texture != null:
		return
	var center: Vector2 = size * 0.5
	var radius: float = minf(size.x, size.y) * 0.42
	var glow: float = 0.10 + 0.06 * _breath
	# 外圈光环
	draw_circle(center, radius * (1.06 + 0.06 * _breath), Color(0.45, 0.85, 0.78, glow))
	# 菱形符文体（共享精灵体的占位轮廓）
	var diamond := PackedVector2Array([
		center + Vector2(0, -radius),
		center + Vector2(radius * 0.72, 0),
		center + Vector2(0, radius),
		center + Vector2(-radius * 0.72, 0),
	])
	draw_colored_polygon(diamond, Color(0.16, 0.42, 0.38, 0.88 * _focus))
	# 内芯
	draw_circle(center, radius * 0.30, Color(1.0, 0.86, 0.42, 0.85 * _focus))
