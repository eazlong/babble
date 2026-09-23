extends GutTest

## 睁眼过场（序章开场）：
## - 运动曲线是纯函数，直接断言端点/单调性；
## - 过场本体单独挂到树上跑一遍完整时间轴（这正是把它做成组件的原因：
##   整个 BeginningFP 进树会触发 TTS/ASR/存档）。

const TransitionScript = preload("res://assets/scripts/components/WakeEyeTransition.gd")
const RenderCapabilitiesScript = preload("res://assets/scripts/core/render_capabilities.gd")

## 测试用的时间缩放：3.3s 的过场压到几十毫秒。
const FAST: float = 0.02


## 读眼睛 shader 的源码（眼角轮廓只能在源码层面断言：曲线在 GPU 上算，
## headless 拿不到编译结果，真机上也没法把"形状"变成数字）。
func _shader_source() -> String:
	var file := FileAccess.open(TransitionScript.SHADER_PATH, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


func _make() -> Control:
	var transition: Control = TransitionScript.new()
	add_child_autofree(transition)
	return transition


# ── 两片眼睑的运动曲线 ────────────────────────────────────────

func test_both_lids_start_on_the_same_closed_line() -> void:
	# p=0 时两片必须**贴在同一条线**上：缝隙为 0，屏幕全黑（眼睛是闭着的）。
	assert_eq(TransitionScript.lid_upper_y_at(0.0), TransitionScript.LID_CLOSED_Y,
		"闭合时上眼睑应停在闭合线上")
	assert_eq(TransitionScript.lid_lower_y_at(0.0), TransitionScript.LID_CLOSED_Y,
		"闭合时下眼睑应停在同一条闭合线上")
	assert_eq(TransitionScript.lid_upper_y_at(0.0), TransitionScript.lid_lower_y_at(0.0),
		"两片眼睑闭合时必须重合（否则会漏出一条缝）")


func test_open_lids_form_an_eye_shaped_aperture() -> void:
	# 睁满后**不能**把眼睑送到屏幕外：那样开口就变成两条竖缝，读不出是眼睛。
	# 眼形 = 开口留在屏幕内，而且是**横长**的（宽 > 高）。
	var top: float = TransitionScript.lid_upper_y_at(1.0)
	var bottom: float = TransitionScript.lid_lower_y_at(1.0)
	assert_true(top > 0.0, "睁满时上眼睑应留在屏幕内（实际 y=%.3f）" % top)
	assert_true(bottom < 1.0, "睁满时下眼睑应留在屏幕内（实际 y=%.3f）" % bottom)
	assert_true(top < bottom, "两片眼睑不能交叉（上睑必须在下睑之上）")
	var width_in_screen: float = TransitionScript.EYE_HALF_WIDTH * 2.0 * TransitionScript.VIEW_ASPECT
	assert_true(width_in_screen > TransitionScript.aperture_height(),
		"单只眼睛应是横长形：宽 %.3f > 高 %.3f（屏幕坐标）" % [
			width_in_screen, TransitionScript.aperture_height()])


func test_eye_shape_has_pointed_corners_not_glasses_lenses() -> void:
	# 用户反馈"像眼镜，要两端尖中间大"。超椭圆轮廓 (1-|sx|^n)^(1/n) 在眼角切线趋近竖直
	# → 两端被磨圆（镜片）；抛物线 (1-sx²) 斜率有限 → 两端是尖的。
	# 曲线在 GPU 侧算，headless 拿不到，所以这条查源码；下面的夹角断言查几何。
	var source := _shader_source()
	assert_true(source.contains("1.0 - sx * sx"),
		"眼角轮廓必须是抛物线（1 - sx²）—— 换成超椭圆两端就会被磨圆，看着像眼镜片")
	assert_false(source.contains("pow(abs(scaled.x)"),
		"不要再用超椭圆轮廓（那是「眼镜片」版本的写法）")
	assert_true(TransitionScript.EYE_PROFILE_POWER == 1.0,
		"轮廓指数必须留在抛物线（1.0）：小于 1 会把两端磨圆（实际 %.2f）" % TransitionScript.EYE_PROFILE_POWER)


func test_upper_arc_is_deeper_than_the_lower_arc() -> void:
	# 两条振幅相同的弧在眼角是对称的（像镜片）；上下振幅不同才交得出眼角尖。
	# 参考图里上眼睑是一道大弧、下眼睑浅得多。
	var upper: float = TransitionScript.upper_arc_amplitude()
	var lower: float = TransitionScript.lower_arc_amplitude()
	assert_true(upper > lower,
		"上眼睑弧（%.3f）必须比下眼睑弧（%.3f）深" % [upper, lower])
	assert_true(upper / lower >= 1.25,
		"上弧至少要比下弧深 25%%，否则眼角交不出明显的尖（实际比值 %.2f）" % (upper / lower))


func test_corner_angle_stays_in_the_eye_range() -> void:
	# 夹角太小 = 两端圆钝（镜片），太大 = 眼睛被压成细缝。真眼形落在 70°~110°。
	var angle: float = TransitionScript.corner_angle_degrees()
	assert_true(angle >= 70.0 and angle <= 110.0,
		"眼角夹角 %.1f° 不在眼形区间（70°~110°）：偏小是圆钝、偏大是细缝" % angle)


func test_two_eyes_are_side_by_side_and_do_not_merge() -> void:
	# 两只眼必须分开：中心左右对称，而且**半宽小于中心间距**——否则两条开口连成一片，
	# 又会读成"一个形状"（这次是横长的一条）。
	assert_almost_eq(TransitionScript.EYE_CENTER_LEFT + TransitionScript.EYE_CENTER_RIGHT, 1.0, 0.0001,
		"两只眼应关于屏幕中线对称")
	assert_true(TransitionScript.EYE_CENTER_LEFT > 0.0 and TransitionScript.EYE_CENTER_RIGHT < 1.0,
		"两只眼的中心都应在屏幕内")
	assert_true(TransitionScript.EYE_HALF_WIDTH < TransitionScript.EYE_SPACING,
		"单只眼的半宽（%.3f）必须小于中心间距（%.3f），否则两只眼会连成一片" % [
			TransitionScript.EYE_HALF_WIDTH, TransitionScript.EYE_SPACING])
	var left_right_edge: float = TransitionScript.EYE_CENTER_LEFT + TransitionScript.EYE_HALF_WIDTH
	var right_left_edge: float = TransitionScript.EYE_CENTER_RIGHT - TransitionScript.EYE_HALF_WIDTH
	assert_true(left_right_edge < right_left_edge,
		"左眼右缘（%.3f）应落在右眼左缘（%.3f）之左，中间留出鼻梁" % [left_right_edge, right_left_edge])


func test_right_eye_lags_the_left_eye() -> void:
	# 两只眼完全同步会像机械开合：右眼整体慢一个相位。
	for p in [0.25, 0.4, 0.6, 0.8]:
		assert_true(TransitionScript.lid_upper_y_right_at(p) >= TransitionScript.lid_upper_y_at(p),
			"p=%.2f 时右眼上睑不应比左眼抬得更高（右=%.4f 左=%.4f）" % [
				p, TransitionScript.lid_upper_y_right_at(p), TransitionScript.lid_upper_y_at(p)])
		assert_true(TransitionScript.lid_lower_y_right_at(p) <= TransitionScript.lid_lower_y_at(p),
			"p=%.2f 时右眼下睑不应比左眼落得更低" % p)
	# 起手式不能有例外：p=0 两只眼都必须是闭合的。
	assert_eq(TransitionScript.lid_upper_y_right_at(0.0), TransitionScript.LID_CLOSED_Y,
		"p=0 时右眼也必须是闭合的（相位差不能让它漏缝）")
	assert_eq(TransitionScript.lid_lower_y_right_at(0.0), TransitionScript.LID_CLOSED_Y,
		"p=0 时右眼也必须是闭合的")
	# 但也不能慢到"最后还没睁开"：相位差必须重标定，两个端点与左眼严格对齐。
	assert_eq(TransitionScript.lid_upper_y_right_at(1.0), TransitionScript.LID_UPPER_OPEN_Y,
		"p=1 时右眼也必须睁满（相位差要在终点追平，否则右眼永远差 6%）")
	assert_eq(TransitionScript.lid_lower_y_right_at(1.0), TransitionScript.LID_LOWER_OPEN_Y,
		"p=1 时右眼下睑也必须落到位")
	assert_eq(TransitionScript.right_progress(1.0), 1.0, "p=1 时右眼进度必须追平")


func test_lids_clamp_out_of_range_progress() -> void:
	assert_eq(TransitionScript.lid_upper_y_at(-5.0), TransitionScript.LID_CLOSED_Y, "负进度应夹到闭合")
	assert_eq(TransitionScript.lid_lower_y_at(-5.0), TransitionScript.LID_CLOSED_Y, "负进度应夹到闭合")
	assert_eq(TransitionScript.lid_upper_y_at(9.0), TransitionScript.LID_UPPER_OPEN_Y, "超范围应夹到全开")
	assert_eq(TransitionScript.lid_lower_y_at(9.0), TransitionScript.LID_LOWER_OPEN_Y, "超范围应夹到全开")


func test_each_lid_moves_monotonically() -> void:
	# 上睑只往上（y 单调不增），下睑只往下（y 单调不减）—— 眼皮不会回弹。
	var previous_upper := 2.0
	var previous_lower := -1.0
	for i in range(0, 101):
		var p: float = float(i) / 100.0
		var upper: float = TransitionScript.lid_upper_y_at(p)
		var lower: float = TransitionScript.lid_lower_y_at(p)
		assert_true(upper <= previous_upper, "上眼睑在 p=%.2f 处回弹了（%.4f > %.4f）" % [p, upper, previous_upper])
		assert_true(lower >= previous_lower, "下眼睑在 p=%.2f 处回弹了（%.4f < %.4f）" % [p, lower, previous_lower])
		previous_upper = upper
		previous_lower = lower


func test_crack_phase_opens_a_thin_slit_and_keeps_the_lids_apart() -> void:
	# 开头 18% 只是"睫毛裂开一条缝"：够小（不是直接睁满），但不为 0（有动静）。
	var p: float = TransitionScript.CRACK_FRACTION
	var gap: float = TransitionScript.lid_lower_y_at(p) - TransitionScript.lid_upper_y_at(p)
	assert_almost_eq(gap, TransitionScript.CRACK_GAP, 0.0001, "裂缝阶段的缝隙应等于 CRACK_GAP")
	assert_true(gap > 0.0 and gap < 0.2, "裂缝开口 %.3f 应落在 (0, 0.2)：太小看不见，太大就不像'裂一条缝'" % gap)


func test_upper_lid_leads_the_lower_lid() -> void:
	# 这是"两片眼睑"和"一个窗口在放大"的分界线：上睑必须走在前面（真实眼皮是上睑主导）。
	for p in [0.3, 0.4, 0.5, 0.6, 0.7]:
		var upper: float = TransitionScript.upper_travel_at(p)
		var lower: float = TransitionScript.lower_travel_at(p)
		assert_true(upper > lower,
			"p=%.1f 时上眼睑应走得更多（上=%.3f 下=%.3f）" % [p, upper, lower])
	# 上眼睑的行程也更长：闭合线偏下，它到屏幕上沿的距离大于下睑到屏幕下沿的距离。
	assert_true(TransitionScript.LID_CLOSED_Y > TransitionScript.LID_CORNER_Y_OPEN,
		"闭合线应在眼角线之下（上睑才有更长行程可走）")


func test_lids_never_cross_at_any_progress() -> void:
	for i in range(0, 101):
		var p: float = float(i) / 100.0
		assert_true(TransitionScript.lid_upper_y_at(p) <= TransitionScript.lid_lower_y_at(p),
			"p=%.2f 处左眼两片眼睑交叉了" % p)
		assert_true(TransitionScript.lid_upper_y_right_at(p) <= TransitionScript.lid_lower_y_right_at(p),
			"p=%.2f 处右眼两片眼睑交叉了" % p)


func test_corner_line_rises_with_the_gaze() -> void:
	assert_eq(TransitionScript.corner_y_at(0.0), TransitionScript.LID_CLOSED_Y,
		"闭合时眼角线应与闭合线重合（否则闭眼时四角会漏光）")
	assert_eq(TransitionScript.corner_y_at(1.0), TransitionScript.LID_CORNER_Y_OPEN,
		"睁满时眼角线应落在睁眼位")
	assert_true(TransitionScript.corner_y_at(0.0) > TransitionScript.corner_y_at(1.0),
		"眼角线应随视线略微上移")


func test_lid_shade_fades_out_as_the_eye_opens() -> void:
	assert_eq(TransitionScript.lid_shade_at(0.0), TransitionScript.LID_SHADE_REST, "刚睁眼时阴影最重")
	assert_eq(TransitionScript.lid_shade_at(1.0), TransitionScript.LID_SHADE_OPEN, "睁满后阴影应淡光")
	assert_true(TransitionScript.LID_SHADE_REST > 0.0, "不设阴影就等于没有眼眶")


# ── 闪光 ──────────────────────────────────────────────────

func test_flash_envelope_starts_at_zero_and_stops_at_full_white() -> void:
	# 起手不能自己亮一下；冲到峰值后**保持在全白**（没有衰减段——衰减交给整层淡出）。
	assert_eq(TransitionScript.flash_intensity_at(0.0), 0.0, "闪光起点应为 0")
	assert_eq(TransitionScript.flash_intensity_at(-1.0), 0.0, "负进度应夹到 0")
	assert_eq(TransitionScript.flash_intensity_at(1.0), TransitionScript.FLASH_PEAK, "上升段结束应到峰值")
	assert_eq(TransitionScript.flash_intensity_at(2.0), TransitionScript.FLASH_PEAK,
		"峰值之后必须保持不降（这一步就是要停在白上等淡出）")
	# 起手的一小步也要很小：变白是"渐渐"的，不能第一步就跳一大截。
	assert_true(TransitionScript.flash_intensity_at(0.05) < 0.02,
		"起手 5%% 时间内的亮度应几乎为 0（实际 %.4f）" % TransitionScript.flash_intensity_at(0.05))


func test_flash_peak_is_full_white() -> void:
	# 用户要的是"闪成全屏白色"：叠加白必须到 1.0，而且颜色必须是**纯白**。
	# 暖白叠加只能把四角加到 (255,245,224)，那就不是全屏白了。
	assert_eq(TransitionScript.FLASH_PEAK, 1.0, "闪光峰值必须是全白")
	assert_eq(TransitionScript.FLASH_COLOR, Color(1.0, 1.0, 1.0),
		"闪光颜色必须是纯白（叠加混合下暖白加不出纯白）")


func test_flash_rises_monotonically_and_never_decays() -> void:
	var previous := -1.0
	for i in range(0, 101):
		var t: float = float(i) / 100.0
		var value: float = TransitionScript.flash_intensity_at(t)
		assert_true(value >= previous - 0.0001, "闪光在 t=%.2f 处回落了（这一版不应该有衰减段）" % t)
		previous = value
	assert_eq(TransitionScript.flash_intensity_at(1.0), TransitionScript.FLASH_PEAK,
		"上升段结束时必须正好在全白")


func test_whitening_takes_about_one_second() -> void:
	# 用户指定"1s 内渐渐变白"（第一版 0.15s 太快）。这里钉住量级，防止又被改回瞬闪。
	assert_true(TransitionScript.FLASH_RISE_DURATION >= 0.8
		and TransitionScript.FLASH_RISE_DURATION <= 1.5,
		"变白时长应在 1s 量级（实际 %.2fs）" % TransitionScript.FLASH_RISE_DURATION)


func test_whitening_is_gradual_not_front_loaded() -> void:
	# "渐渐变白"的实质：开头不能一下冲上去。四分之一的时间点只应亮一点点，
	# 一半时间点约一半，末尾才收满 —— 前段冲太快就又变回"闪一下"了。
	var quarter: float = TransitionScript.flash_intensity_at(0.25)
	var half: float = TransitionScript.flash_intensity_at(0.5)
	var end: float = TransitionScript.flash_intensity_at(1.0)
	assert_true(quarter < 0.30,
		"前 1/4 时间只应变亮不到三成（实际 %.3f）—— 更大就是前段冲太快" % quarter)
	assert_almost_eq(half, 0.5, 0.08, "一半时间点应约亮一半")
	assert_true(end > half and half > quarter, "亮度必须一路递增")
	# 曲线要平滑：相邻采样点的增量不该出现尖峰（smoothstep 的最大斜率在中点）。
	var max_step := 0.0
	var prev: float = TransitionScript.flash_intensity_at(0.0)
	for i in range(1, 21):
		var value: float = TransitionScript.flash_intensity_at(float(i) / 20.0)
		max_step = maxf(max_step, value - prev)
		prev = value
	assert_true(max_step < 0.25,
		"单步最大增量 %.3f 过大，曲线不够平滑（会被读成突然变白）" % max_step)


func test_lid_dissolves_before_the_white_starts_fading() -> void:
	# 关键不变量（截图里真出现过）：眼睑必须比白光先化掉。两者同速淡的话，白光褪到
	# 一半时两只眼形的轮廓会从白里浮出来，变成"两个亮眼睛 + 暗四周"，
	# 而不是干净的全白淡出。
	assert_true(TransitionScript.LID_DISSOLVE_DURATION < TransitionScript.FADE_DURATION,
		"眼睑化掉（%.2fs）必须快于白光褪去（%.2fs）" % [
			TransitionScript.LID_DISSOLVE_DURATION, TransitionScript.FADE_DURATION])
	assert_true(TransitionScript.LID_DISSOLVE_DURATION <= 0.3,
		"眼睑要化得够快，才能在白光还很亮时就消失（实际 %.2fs）" % TransitionScript.LID_DISSOLVE_DURATION)


func test_flash_layer_exists_above_the_lid_and_starts_invisible() -> void:
	var transition = _make()
	assert_not_null(transition.flash, "应建出闪光层")
	assert_eq(transition.flash.color.a, 0.0, "闪光层起手必须是全透明的")
	assert_eq(transition.flash.mouse_filter, Control.MOUSE_FILTER_IGNORE, "闪光层不能吃掉点击")
	assert_eq(transition.flash.anchor_right, 1.0, "闪光层应横向铺满")
	assert_eq(transition.flash.anchor_bottom, 1.0, "闪光层应纵向铺满")
	# 顺序：眼睑在下、闪光在上 —— 否则闪的只是两个眼洞里透出来的世界，眼睑黑边不会亮。
	assert_true(transition.flash.get_index() > transition.lid.get_index(),
		"闪光层必须排在眼睑之后（画在上面）")
	var flash_material := transition.flash.material as CanvasItemMaterial
	assert_not_null(flash_material, "闪光层需要 CanvasItemMaterial 才能做叠加混合")
	assert_eq(flash_material.blend_mode, CanvasItemMaterial.BLEND_MODE_ADD,
		"闪光要用叠加混合（加光），不是普通 alpha 蒙一层白")


func test_apply_flash_writes_the_envelope_onto_the_layer() -> void:
	var transition = _make()
	transition._apply_flash(0.0)
	assert_eq(transition.get_flash_intensity(), 0.0, "t=0 闪光应为 0")
	transition._apply_flash(1.0)
	assert_almost_eq(float(transition.get_flash_intensity()), TransitionScript.FLASH_PEAK, 0.0001,
		"上升段结束应写到全白")
	transition._apply_flash(0.5)
	assert_true(float(transition.get_flash_intensity()) > 0.0
		and float(transition.get_flash_intensity()) < TransitionScript.FLASH_PEAK,
		"中途应是 0 与全白之间的过渡值")


func test_play_leaves_the_flash_off_at_the_end() -> void:
	# 这一版闪光会停在**全屏白**上等淡出，所以"淡完必须归零"比之前更要紧：
	# 漏了这一步，过场结束后玩家看到的就是一片白。
	var transition = _make()
	transition.play(FAST)
	await transition.finished
	await get_tree().process_frame
	assert_eq(float(transition.get_flash_intensity()), 0.0, "过场结束时闪光必须已经回到 0")


# ── 组件构造 ────────────────────────────────────────────────

func test_component_builds_an_opaque_black_lid() -> void:
	# 没有 shader 时这块黑遮罩就是降级画面本身，**必须存在且必须是黑的**
	# （白色 ColorRect 会糊满整屏 —— 归卷厅提亮层踩过这个坑）。
	var transition = _make()
	assert_not_null(transition.lid, "应建出全屏眼睑")
	assert_eq(transition.lid.color, Color.BLACK, "眼睑必须是纯黑")
	assert_eq(transition.lid.mouse_filter, Control.MOUSE_FILTER_IGNORE, "遮罩不能吃掉点击")
	assert_eq(transition.lid.anchor_right, 1.0, "眼睑应横向铺满")
	assert_eq(transition.lid.anchor_bottom, 1.0, "眼睑应纵向铺满")


func test_material_is_absent_in_headless() -> void:
	# headless 挂 shader 会 push 引擎错误 → GUT 判失败，所以组件不建材质。
	# 真机上这条断言会走另一支：材质存在且 uniform 列表非空。
	var transition = _make()
	if RenderCapabilitiesScript.supports_shaders():
		assert_not_null(transition.wake_material(), "真渲染器下应拿到可用的眼睛材质")
	else:
		assert_null(transition.wake_material(), "headless 下不应有可用材质（走降级淡出）")


# ── 完整时间轴 ───────────────────────────────────────────────

func test_play_finishes_and_leaves_nothing_covering_the_screen() -> void:
	# 用户报的"过场只是一张静态图片"= shader 静默失败后黑遮罩一直挂着不动。
	# 这条测试钉住底线：**过场一定会结束，结束时不留下任何遮挡**。
	var transition = _make()
	transition.play(FAST)
	await transition.finished
	# 等一帧让 finished.emit() 返回后再断言：否则 GUT 的 autofree 会在组件还在自己的
	# 信号回调里时把它 free 掉，报 "Object is locked and can't be freed"。
	await get_tree().process_frame
	assert_false(transition.visible, "过场跑完后遮罩必须隐藏（否则世界被永久挡住）")


func test_component_actually_covers_the_viewport() -> void:
	# 真回归点：Control 直接挂在 CanvasLayer 下时，只有**进树那一刻**的布局会按 anchors
	# 算出视口尺寸。anchors 若在 `_ready()` 里才设，控件会静默停在 0×0 —— 遮罩照样
	# visible、材质和参数照样在动，只是永远占 0 像素，屏幕上什么都看不见。
	# 所以尺寸必须在 `_init()` 里就定好，这两条断言钉住它。
	var transition = _make()
	await get_tree().process_frame
	assert_gt(transition.size.x, 0.0, "遮罩宽度不能是 0（否则整条过场不可见）")
	assert_gt(transition.size.y, 0.0, "遮罩高度不能是 0（否则整条过场不可见）")
	assert_gt(transition.lid.size.x, 0.0, "眼睑宽度不能是 0")
	assert_gt(transition.lid.size.y, 0.0, "眼睑高度不能是 0")


func test_play_emits_finished_exactly_once() -> void:
	var transition = _make()
	var count := [0]
	transition.finished.connect(func(): count[0] += 1)
	transition.play(FAST)
	await transition.finished
	await get_tree().create_timer(0.1).timeout
	assert_eq(count[0], 1, "finished 只应发一次")


func test_play_is_safe_without_being_in_the_tree() -> void:
	# 防御：控制器在 _ready 里建组件，万一 play() 早于进树被调用，不能崩。
	var transition: Control = TransitionScript.new()
	assert_not_null(transition, "组件应能独立构造")
	transition.free()
