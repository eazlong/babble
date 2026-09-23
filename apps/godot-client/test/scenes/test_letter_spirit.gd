extends GutTest

## LetterSpirit 组件测试（v0.3 §5.2.1）。
##
## 原则：**只断言几何与状态，不断言帧时序**。这个仓库已经有几个时序型测试
## （star flight / typing animation）在基线就是红的，不再添同类。

const LetterSpiritScript = preload("res://assets/scripts/components/LetterSpirit.gd")

func _make_spirit(in_tree: bool = false) -> Control:
	var spirit: Control = LetterSpiritScript.new()
	if in_tree:
		add_child(spirit)
	return spirit

func _make_texture() -> ImageTexture:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.8, 0.7, 1.0))
	return ImageTexture.create_from_image(image)

# ── 构造与字形叠加 ──────────────────────────────────────────────────

func test_setup_builds_body_and_glyph_children() -> void:
	var spirit = _make_spirit(true)
	spirit.setup("A")
	assert_not_null(spirit.get_node_or_null("Body"), "应有精灵体子节点")
	assert_not_null(spirit.get_node_or_null("Glyph"), "应有字形子节点")
	assert_eq(spirit._glyph.text, "A", "字形应显示字母")
	spirit.free()

func test_programmatic_rune_when_texture_missing() -> void:
	# 贴图留空是有意为之：走程序化符文，等真美术落地后零代码改动切换
	var spirit = _make_spirit(true)
	spirit.setup("B")
	assert_null(spirit.body_texture, "未给贴图时 body_texture 应为空")
	assert_false(spirit._body.visible, "无贴图时不应显示精灵体贴图（改由 _draw 画符文）")
	spirit.free()

func test_texture_switches_to_sprite_path_without_code_change() -> void:
	var spirit = _make_spirit(true)
	spirit.setup("C", _make_texture())
	assert_not_null(spirit.body_texture, "给了贴图就应持有它")
	assert_true(spirit._body.visible, "有贴图时应显示精灵体")
	assert_eq(spirit._body.texture, spirit.body_texture, "精灵体应使用同一张贴图")
	spirit.free()

func test_size_defaults_to_component_default() -> void:
	var spirit = _make_spirit(true)
	spirit.setup("D")
	assert_eq(spirit.custom_minimum_size, LetterSpiritScript.DEFAULT_SIZE, "默认尺寸应为组件常量")
	spirit.free()

# ── 休眠态 ──────────────────────────────────────────────────────────

func test_settle_at_home_enters_dormant_state() -> void:
	var spirit = _make_spirit(true)
	spirit.setup("E")
	spirit.settle_at_home(Vector2(120, 40))
	assert_eq(spirit.state, LetterSpiritScript.State.DORMANT, "回位后应是休眠态")
	assert_eq(spirit.position, Vector2(120, 40), "位置应等于原位")
	assert_eq(spirit.home_position, Vector2(120, 40), "应记住原位")
	assert_true(spirit.visible, "休眠态仍应可见")
	spirit.free()

func test_breath_offsets_do_not_move_the_spirit() -> void:
	# 呼吸只改亮度/光环，绝不能改 position——否则岩壁会整体漂移
	var spirit = _make_spirit(true)
	spirit.setup("F")
	spirit.settle_at_home(Vector2(200, 50))
	spirit._set_breath(1.0)
	assert_eq(spirit.position, Vector2(200, 50), "呼吸不应改变位置")
	spirit.free()

# ── 飞行几何（纯数学，不依赖帧）───────────────────────────────────

func test_fly_arc_starts_at_origin_and_ends_at_target() -> void:
	var spirit = _make_spirit(false)
	spirit.setup("G")
	spirit.size = LetterSpiritScript.DEFAULT_SIZE
	spirit.position = Vector2(0, 0)
	spirit.fly_to(Vector2(400, 300), 200, 90.0)
	# 不在树里 → 直接落位
	assert_eq(spirit.position, Vector2(400, 300) - LetterSpiritScript.DEFAULT_SIZE * 0.5, "落位应为中心减去半个尺寸")
	spirit.free()

func test_apply_flight_arc_is_parabola() -> void:
	var spirit = _make_spirit(false)
	spirit.setup("H")
	spirit.size = LetterSpiritScript.DEFAULT_SIZE
	spirit._flight_from = Vector2(0, 0)
	spirit._flight_to = Vector2(100, 100)
	spirit._flight_arc = 40.0
	spirit._apply_flight(0.0)
	assert_eq(spirit.position, Vector2(0, 0), "t=0 应在出发点")
	spirit._apply_flight(1.0)
	assert_eq(spirit.position, Vector2(100, 100), "t=1 应在槽位")
	spirit._apply_flight(0.5)
	# 中点：直线插值是 (50,50)，抛物线应在它上方 40px（y 更小）
	assert_almost_eq(spirit.position.x, 50.0, 0.001, "中点 x 应是直线中点")
	assert_almost_eq(spirit.position.y, 10.0, 0.001, "中点 y 应抬高一个 arc")
	spirit.free()

func test_apply_flight_clamps_out_of_range_t() -> void:
	var spirit = _make_spirit(false)
	spirit.setup("I")
	spirit._flight_from = Vector2(0, 0)
	spirit._flight_to = Vector2(50, 50)
	spirit._flight_arc = 10.0
	spirit._apply_flight(2.0)
	assert_eq(spirit.position, Vector2(50, 50), "t>1 应夹到终点，不能飞过头")
	spirit._apply_flight(-1.0)
	assert_eq(spirit.position, Vector2(0, 0), "t<0 应夹到起点")
	spirit.free()

# ── 状态机与信号（离树路径，确定性）───────────────────────────────

func test_fly_to_emits_flight_finished_and_enters_slotted() -> void:
	var spirit = _make_spirit(false)
	spirit.setup("J")
	spirit.size = LetterSpiritScript.DEFAULT_SIZE
	watch_signals(spirit)
	spirit.fly_to(Vector2(300, 200), 150)
	assert_eq(spirit.state, LetterSpiritScript.State.SLOTTED, "落位后应进入入槽态")
	assert_false(spirit.is_animating, "落位后动作标记应清空")
	assert_signal_emitted(spirit, "flight_finished")
	spirit.free()

func test_scatter_home_emits_and_returns_to_dormant() -> void:
	var spirit = _make_spirit(false)
	spirit.setup("K")
	spirit.home_position = Vector2(64, 32)
	spirit.position = Vector2(500, 500)
	watch_signals(spirit)
	spirit.scatter_home(200)
	assert_eq(spirit.position, Vector2(64, 32), "散落应回到岩壁原位")
	assert_eq(spirit.state, LetterSpiritScript.State.DORMANT, "散落后回到休眠态")
	assert_signal_emitted(spirit, "scatter_finished")
	spirit.free()

func test_merge_into_slot_hides_spirit() -> void:
	var spirit = _make_spirit(false)
	spirit.setup("L")
	watch_signals(spirit)
	spirit.merge_into_slot()
	assert_false(spirit.visible, "融入槽位后精灵应隐去（字形交给槽位条）")
	assert_signal_emitted(spirit, "merge_finished")
	spirit.free()

func test_inscribe_into_stele_hides_spirit() -> void:
	# 刻印态不飞回原位，而是融入石碑铭文（§5.2 刻印态）
	var spirit = _make_spirit(false)
	spirit.setup("M")
	spirit.inscribe_into_stele(Vector2(800, 500), 100)
	assert_false(spirit.visible, "刻印后精灵应隐去")
	assert_eq(spirit.state, LetterSpiritScript.State.INSCRIBED, "应是刻印态")
	spirit.free()

func test_kill_action_clears_animating_flag() -> void:
	var spirit = _make_spirit(false)
	spirit.setup("N")
	spirit.is_animating = true
	spirit.kill_action()
	assert_false(spirit.is_animating, "打断动作后不应仍标记为动画中")
	spirit.free()

# ── 焦点高亮 ────────────────────────────────────────────────────────

func test_set_focus_clamps_negative_and_reports() -> void:
	var spirit = _make_spirit(true)
	spirit.setup("O")
	spirit.set_focus(1.6)
	assert_almost_eq(spirit.get_focus(), 1.6, 0.001, "泛光值应被记住")
	spirit.set_focus(-3.0)
	assert_eq(spirit.get_focus(), 0.0, "负值应夹到 0，不能变负亮度")
	spirit.free()

func test_focus_does_not_change_state() -> void:
	var spirit = _make_spirit(true)
	spirit.setup("P")
	spirit.settle_at_home(Vector2(10, 10))
	spirit.set_focus(0.3)
	assert_eq(spirit.state, LetterSpiritScript.State.DORMANT, "焦点高亮是表现层，不该改状态机")
	spirit.free()

# ── 沉睡 / 现身（演出拍 8）──────────────────────────────────────────

func test_revealed_defaults_to_true_for_a_fresh_spirit() -> void:
	# 直接构造的精灵默认现身；沉睡是归卷厅进场时的特殊设置
	var spirit = _make_spirit(false)
	spirit.setup("Q")
	assert_true(spirit.revealed, "默认应已现身")
	assert_false(spirit.is_sleeping(), "默认不在沉睡")
	spirit.free()

func test_sleeping_spirit_has_zero_alpha() -> void:
	var spirit = _make_spirit(true)
	spirit.setup("R")
	spirit.settle_at_home(Vector2(10, 10))
	spirit.set_revealed(false)
	assert_true(spirit.is_sleeping(), "应处于沉睡")
	assert_eq(spirit.modulate.a, 0.0, "沉睡的符文必须完全透明")
	spirit.free()

func test_focus_cannot_wake_a_sleeping_spirit() -> void:
	# "沉睡"与"焦点为 0"是两件事：焦点高亮不能把沉睡的符文点亮
	var spirit = _make_spirit(true)
	spirit.setup("S")
	spirit.set_revealed(false)
	spirit.set_focus(1.5)
	assert_eq(spirit.modulate.a, 0.0, "焦点再高也不能点亮沉睡的符文")
	assert_true(spirit.is_sleeping(), "焦点不应改变沉睡标记")
	assert_almost_eq(spirit.get_focus(), 1.5, 0.001, "焦点值本身仍应被记住")
	spirit.free()

func test_breathing_does_not_wake_a_sleeping_spirit() -> void:
	var spirit = _make_spirit(true)
	spirit.setup("T")
	spirit.set_revealed(false)
	spirit.play_dormant()
	assert_eq(spirit.modulate.a, 0.0, "呼吸不应把沉睡符文点亮")
	spirit.free()

func test_play_reveal_restores_dormant_brightness() -> void:
	var spirit = _make_spirit(false)
	spirit.setup("U")
	spirit.set_revealed(false)
	spirit.play_reveal(100)
	assert_true(spirit.revealed, "现身后应标记为已现身")
	assert_almost_eq(spirit.modulate.a, LetterSpirit.DORMANT_ALPHA, 0.001, "休眠态现身应回到休眠亮度")
	spirit.free()

func test_play_reveal_marks_animating_while_in_tree() -> void:
	var spirit = _make_spirit(true)
	spirit.setup("V")
	spirit.set_revealed(false)
	spirit.play_reveal(100)
	assert_true(spirit.is_animating, "树内现身应进入动画态（供控制器等待）")
	assert_true(spirit.revealed, "现身标记应立刻生效，不等动画结束")
	spirit.free()

func test_reveal_does_not_move_the_spirit() -> void:
	var spirit = _make_spirit(true)
	spirit.setup("W")
	spirit.settle_at_home(Vector2(77, 33))
	spirit.set_revealed(false)
	spirit.play_reveal(100)
	assert_eq(spirit.position, Vector2(77, 33), "现身只改亮度，不该挪动符文")
	spirit.free()

# ── 字形对比（美术落地后发现：精灵体中心很亮）────────────────────

## WCAG 相对亮度
func _rel_lum(c: Color) -> float:
	var out: Array[float] = []
	for v in [c.r, c.g, c.b]:
		var s: float = v
		out.append(s / 12.92 if s <= 0.03928 else pow((s + 0.055) / 1.055, 2.4))
	return 0.2126 * out[0] + 0.7152 * out[1] + 0.0722 * out[2]

func _contrast(a: Color, b: Color) -> float:
	var la: float = _rel_lum(a)
	var lb: float = _rel_lum(b)
	var hi: float = maxf(la, lb)
	var lo: float = minf(la, lb)
	return (hi + 0.05) / (lo + 0.05)

func test_glyph_is_dark_ink_not_light_gold() -> void:
	# 精灵体中心实测亮度 206–217（v1 216.8 / v2 206.1 / v3 207.9），
	# 原来的暖浅字形亮度约 226 —— 字形会融进精灵体里读不出来。
	var spirit = _make_spirit(true)
	spirit.setup("A")
	var glyph: Label = spirit.get_node("Glyph")
	var fill: Color = glyph.get_theme_color("font_color")
	var body_center: Color = Color(0.816, 0.816, 0.816)  # 实测亮度 ~208
	assert_true(
		_contrast(fill, body_center) >= 4.5,
		"字形实色与精灵体中心的对比度应达到 WCAG AA 4.5:1，实际 %.2f" % _contrast(fill, body_center)
	)
	spirit.free()

func test_glyph_has_a_light_outline_for_dark_backdrops() -> void:
	# 反过来，暗底/半透明（沉睡、散落）时靠浅描边读
	var spirit = _make_spirit(true)
	spirit.setup("B")
	var glyph: Label = spirit.get_node("Glyph")
	var outline: Color = glyph.get_theme_color("font_outline_color")
	assert_true(
		_contrast(outline, Color(0.078, 0.078, 0.078)) >= 4.5,
		"字形描边与深色底的对比度应达到 4.5:1"
	)
	assert_true(glyph.get_theme_constant("outline_size") > 0, "描边宽度应大于 0")
	spirit.free()

func test_glyph_ink_and_outline_are_different_colors() -> void:
	var spirit = _make_spirit(true)
	spirit.setup("C")
	var glyph: Label = spirit.get_node("Glyph")
	assert_ne(
		glyph.get_theme_color("font_color"),
		glyph.get_theme_color("font_outline_color"),
		"实色与描边必须不同色，否则描边没有分离作用"
	)
	spirit.free()
