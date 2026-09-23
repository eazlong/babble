extends Control

## 睁眼过场 —— 序章开场：全屏黑遮罩上**两只眼睛睁开**（每只上下两片眼睑，上睑主导），
## 睁到最大后**闪一记白光**，再**整层淡出**，露出主人房。
##
## 时间轴：眼睑分开 1.4s → 停顿 0.7s → **白光 1.0s 渐渐铺成全屏白**（停住，不衰减）
## → **从全白整层淡出 1.2s**，世界从白光里浮出来。
##
## 淡出时**闪光层与眼睑层一起淡**：只淡眼睑的话，白光褪掉会先露出
## "两个眼洞 + 黑口罩"再淡一次，就变成两截动作了。
##
## ## 为什么单独做成组件
##
## 它是纯表现、零业务依赖（不读 GameManager、不碰语音链路），所以 GUT 可以把它**单独**
## 挂到树上跑完整条时间轴。塞在 `BeginningFPController` 里就做不到：整个序章场景进树会
## 触发 TTS / ASR / 存档，测试里不能那么干（与 FormationEnergyDial / SpellingSlotBar 同理）。
##
## ## 画面上有什么（全部是代码画的，没有任何静态图片资源）
##
## **两片眼睑**（上睑 + 下睑）从同一条闭合线分开，形状由 `wake_eye_open.gdshader`
## 里的两条边缘曲线决定；缝隙内 alpha=0 → 直接露出后面的世界，缝隙外是黑色眼睑。
## 这里负责"每条眼睑什么时候走到哪里"：
## - `lid_upper_y_at()` —— 上眼睑：开头 18% 先把睫毛裂开一条缝，然后 ease-out 抬到屏幕外。
## - `lid_lower_y_at()` —— 下眼睑：从同一条线往下落，但**慢半拍**（`LOWER_LAG`）。
##   两片一起动、还动得一样多，就又变回"一个窗口在放大"了。
## - `corner_y_at()`    —— 眼角线随视线略微上移，像头抬起来、视线落定。
## - `lid_shade_at()`   —— 眼眶阴影：刚睁开时贴着眼睑边缘的一圈压暗，全开后淡掉。
## - `upper_travel_at()` / `lower_travel_at()` —— 两片各自走了多少（用来验"上睑主导"）。
##
## 全是**纯静态函数**，测试直接断言端点、单调性和两片的差异，不需要渲染器。
##
## ## 用户报的"过场只是一张静态图片"是怎么来的
##
## `wake_eye_open.gdshader` 当时每行注释都以 `#` 开头，而 Godot 4 把 `#` 当预处理指令
## → 整份 shader **静默编译失败**。材质仍然存在、`set_shader_parameter()` 也不报错，
## 只是全部石沉大海：黑遮罩一直是全黑，三段式 tween 全都在"演给空气看"，
## 于是过场就成了一帧静止黑图。
##
## 这里的第一道防线是 `wake_material()`：**uniform 列表为空 = shader 没编译成功**，
## 直接判为"不可用"并走纯代码淡出（`_fade_out`），保证过场一定有运动；
## 第二道防线是 `test/core/test_shader_sources.gd`，它扫全项目的 shader，
## 禁止再出现 `#` 开头的行。

const RenderCapabilitiesScript = preload("res://assets/scripts/core/render_capabilities.gd")

const SHADER_PATH: String = "res://assets/resources/shaders/effects/wake_eye_open.gdshader"

# ── 时间轴（三段式）─────────────────────────────────────────────
## 第一段：眼睑分开，露出世界。
const REVEAL_DURATION: float = 1.4
## 第二段：睁眼后停顿一拍（不能省：没有停顿，睁眼会读成"闪一下"）。
const HOLD_DURATION: float = 0.7
## 第三段：白光**渐渐变白**，1 秒内铺满整个屏幕（叠加混合，睁到最大之后），停在白上不衰减。
##
## 1.0s 是用户指定的节奏：第一版 0.15s 冲上去太快，看不出"渐渐变白"。
const FLASH_RISE_DURATION: float = 1.0
## 闪光峰值：1.0 = 全屏纯白（叠加后每个像素都到 255）。
const FLASH_PEAK: float = 1.0
## 闪光颜色：纯白。**不能用暖白**：叠加是把值加出去，暖白只能把四个角加到
## (255, 245, 224)，那就不叫"全屏白"了，淡出时会看出一点黄。
const FLASH_COLOR: Color = Color(1.0, 1.0, 1.0)
## 第四段：从全白整层淡出，世界从白光里浮出来。
##
## 眼睑层要**先**化掉（`LID_DISSOLVE_DURATION`，很短）：它藏在全白下面，等白光开始
## 褪的时候眼睑必须已经没了 —— 否则两只眼形的轮廓会跟着白光一起"浮"出来，
## 变成"两个亮眼睛 + 暗四周"，而不是干净的全白淡出。只要眼睑在白光还很亮时化完，
## 后面就只是一层纯白在变淡。
const LID_DISSOLVE_DURATION: float = 0.25
const FADE_DURATION: float = 1.2

# ── 眼睛：两片眼睑各自的位置（与 shader 的 uniform 一一对应）──────────
#
# 上下眼睑是两条**独立的边缘曲线**，在眼角交汇。闭合时两片贴在**同一条线**
# （`LID_CLOSED_Y`）上 → 缝隙为 0 → 整个屏幕是眼睑（全黑）；睁开时各走各的。
#
# 为什么不是"一个居中的窗口在放大"：那读起来像光圈/镜头开合，不像眼皮。
# **两只眼睛**各有两片眼睑，要它读起来是"一双眼睛"，靠四处，缺一就不像：
#   1. **左右各一只**：中心 0.26 / 0.74，单眼半宽 < 中心间距 → 中间留出鼻梁；
#   2. **眼睑留在屏幕内**（睁满停在 0.28 / 0.72）→ 开口始终是横长的眼形；
#   3. **两片眼睑不同**：闭合线偏下（上睑行程更长）、弧度不同（上拱下浅）、
#      时机不同（上睑先动，下睑慢半拍 `LOWER_LAG`）；
#   4. **两只眼不同步**：右眼进度推迟 `EYE_PHASE_RIGHT` 并在终点追平。
## 闭合时上下眼睑贴合的那条线（UV y，1 = 屏幕底）。**必须与眼角线不同的位置**：
## 贴合线偏下，上眼睑才有更长的行程可以走。
const LID_CLOSED_Y: float = 0.54
## 睁满时上眼睑停在的位置（UV）。**刻意留在屏幕内**：两只眼睛要一直是"眼形"，
## 眼睑跑到屏幕外就变成两条竖缝，读不出是眼睛了。剩下的黑边交给淡出处理。
##
## 上睑抬 0.26、下睑落 0.18（相对眼角线 0.50）：**上弧要比下弧深**。
## 两条振幅相同的弧在眼角是对称的，看着像镜片；振幅不同才会交出一个眼角尖。
## 参考图（用户给的图标）就是这个关系：上眼睑一道大弧，下眼睑浅得多。
const LID_UPPER_OPEN_Y: float = 0.24
## 睁满时下眼睑停在的位置（UV）。
const LID_LOWER_OPEN_Y: float = 0.68
## 眼角（左右两侧两片眼睑交汇处）的 y。睁眼过程里随视线一起略微上移。
const LID_CORNER_Y_OPEN: float = 0.5

# ── 两只眼睛的水平排布 ──────────────────────────────────────────
## 每只眼睛中心到屏幕中线的距离（UV x）。左右眼对称。
const EYE_SPACING: float = 0.24
const EYE_CENTER_LEFT: float = 0.5 - EYE_SPACING
const EYE_CENTER_RIGHT: float = 0.5 + EYE_SPACING
## 单只眼睛的水平半宽。**必须小于 EYE_SPACING**，否则两只眼会连成一片、
## 看起来又是一个形状（GUT 钉住了这条）。
const EYE_HALF_WIDTH: float = 0.22
## 屏幕宽高比，只用来断言"眼睛是横长形"（眼形 = 宽 > 高）。
const VIEW_ASPECT: float = 16.0 / 9.0
## 眼角轮廓指数：1.0 = 抛物线 → 两端尖（像眼睛）；< 1 会把两端磨圆（像眼镜片）。
## 它与 shader 的 `eye_profile_power` 是同一个旋钮，这里再写一份是为了让"形状"这件事
## 和别的几何常量放在一起，并且能被 GUT 断言（shader 里的曲线 GPU 侧才算得出来）。
const EYE_PROFILE_POWER: float = 1.0

# ── 两只眼不同步 ────────────────────────────────────────────────
## 右眼比左眼慢的相位（占整段进度的比例）。两只眼完全同步会显得像机械开合。
const EYE_PHASE_RIGHT: float = 0.06

## 睁开曲线里"睫毛先裂开一条缝"占的比例。
const CRACK_FRACTION: float = 0.18
## 那条缝的总开口量（UV 高度），按下面的比例分给上下眼睑。
const CRACK_GAP: float = 0.05
## 裂缝里上眼睑占的比例（其余给下眼睑）。
const CRACK_UPPER_SHARE: float = 0.6
## 下眼睑比上眼睑慢的比例（相对整段进度）。真实眼皮是上睑主导。
const LOWER_LAG: float = 0.12

## 刚睁开时眼眶阴影强度，睁满后淡到 0。
const LID_SHADE_REST: float = 0.6
const LID_SHADE_OPEN: float = 0.0

## 整条时间轴跑完（遮罩已隐藏）。调用方 await 这个信号或 `play()`。
signal finished

## 全屏黑色眼睑（窗口外的部分）。**没有 shader 时它就是一块纯黑遮罩** ——
## 这正是降级路径想要的画面，所以它必须在，且必须是黑色（不是白）。
var lid: ColorRect
## 眼睛材质。shader 不可用时为 null（见 `wake_material()`）。
## 名字不能叫 `material`：`CanvasItem` 已经有这个属性，重定义会编译失败。
var eye_material: ShaderMaterial
## 闪光层：一片**叠加混合的白**，画在眼睑之上（所以连眼睑的黑边也一起被照亮）。
## 它自己不带 shader，所以直接改自己的 `color:a` 即可（片元 shader 覆写 COLOR 的坑与它无关）。
var flash: ColorRect


func _init() -> void:
	# anchors 必须在**进树之前**设好。实测（tmp/wake_harness/size_probe.gd）：
	# Control 直接挂在 CanvasLayer 下时，只有进树那一刻的布局会按 anchors 算出视口尺寸；
	# 进了树再 `set_anchors_preset()` **不会重算**，控件就停在 0×0 —— 而且是静默的：
	# 遮罩一切正常（visible、材质、参数都在动），只是永远占 0 像素，屏幕上什么都看不见。
	# 这正是"过场只剩一张静态图"的第二层原因（第一层是 shader 没编译）。
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_layers()


## 建两层：眼睑（下）+ 闪光（上）。**顺序有意义**：闪光在眼睑之上，
## 峰值时把眼睑的黑边也一起照亮，否则闪的只是两个眼洞里透出来的世界。
func _build_layers() -> void:
	if lid != null:
		return
	lid = ColorRect.new()
	lid.name = "Lid"
	lid.color = Color.BLACK
	lid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lid.set_anchors_preset(Control.PRESET_FULL_RECT)
	eye_material = _create_material()
	if eye_material != null:
		lid.material = eye_material
	add_child(lid)

	flash = ColorRect.new()
	flash.name = "Flash"
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	var flash_material := CanvasItemMaterial.new()
	flash_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	flash.material = flash_material
	flash.color = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, 0.0)
	add_child(flash)


## 可用的眼睛材质；**null 表示必须走纯代码降级路径**。
##
## `get_shader_uniform_list()` 为空 = 这份 shader 没编译成功（语法错误、或者 headless 的
## Dummy 渲染器）。这种情况下材质和参数都还在，但画面完全不响应 —— 正是"静止黑图"的成因，
## 所以这里要显式判空，而不是相信 `material != null`。
func wake_material() -> ShaderMaterial:
	if eye_material == null or eye_material.shader == null:
		return null
	if eye_material.shader.get_shader_uniform_list().is_empty():
		return null
	return eye_material


## 当前两只眼睛的缝隙高度 Vector2(左眼, 右眼)（下眼睑 y − 上眼睑 y，UV）。
## ≤ 0 表示该眼两片眼睑贴在一起（全黑）。没有可用材质时返回 null（headless 降级路径）。
func get_lid_gap() -> Variant:
	var mat := wake_material()
	if mat == null:
		return null
	var left: float = float(mat.get_shader_parameter("lid_lower_y")) - float(mat.get_shader_parameter("lid_upper_y"))
	var right: float = float(mat.get_shader_parameter("lid_lower_y_right")) - float(mat.get_shader_parameter("lid_upper_y_right"))
	return Vector2(left, right)


## 跑完整条过场。`speed_scale` 只给测试用（把 3.3s 压到几十毫秒），默认原速。
func play(speed_scale: float = 1.0) -> void:
	if lid == null:
		_build_layers()
	visible = true
	modulate.a = 1.0
	var scale_factor: float = maxf(speed_scale, 0.001)

	var mat := wake_material()
	if mat == null:
		# 降级：没有可用的眼睛 shader。**不能**只是"什么都不做地等"——
		# 那就是用户看到的静止黑图。用整层淡出把世界揭出来。
		push_warning("[WakeEyeTransition] 眼睛 shader 不可用，降级为「闪一下再淡出」：%s" % SHADER_PATH)
		# 降级路径靠 modulate 淡出（那时眼睑就是一块普通黑 ColorRect）；
		# 闪光与 shader 无关，照常给一记白光。
		var fallback_flash := create_tween()
		fallback_flash.tween_method(_apply_flash, 0.0, 1.0, FLASH_RISE_DURATION * scale_factor) \
			.set_trans(Tween.TRANS_LINEAR)
		await get_tree().create_timer(
			(REVEAL_DURATION + HOLD_DURATION + FLASH_RISE_DURATION) * scale_factor
		).timeout
		await _fade_out(scale_factor, null)
		finished.emit()
		return

	mat.set_shader_parameter("overlay_alpha", 1.0)
	_apply_progress(mat, 0.0)

	# 第一段：眼睑分开。
	var reveal := create_tween()
	reveal.tween_method(
		func(p: float): _apply_progress(mat, p),
		0.0, 1.0, REVEAL_DURATION * scale_factor
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await reveal.finished

	# 第二段：睁着眼停一拍。
	await get_tree().create_timer(HOLD_DURATION * scale_factor).timeout

	# 第三段：一记白光冲到全屏白，**停在白上**（不衰减）。
	var flash_tween := create_tween()
	flash_tween.tween_method(_apply_flash, 0.0, 1.0, FLASH_RISE_DURATION * scale_factor) \
		.set_trans(Tween.TRANS_LINEAR)
	await flash_tween.finished

	# 第四段：从全白整层淡出。闪光层与眼睑层**同时**淡 —— 只淡眼睑的话，
	# 白光褪掉会先露出"两只眼洞 + 黑口罩"，再淡一次，就是两截动作了。
	await _fade_out(scale_factor, mat)
	finished.emit()


## 收尾：把遮罩淡掉。
##
## **有材质时淡的是 shader 的 `overlay_alpha`，不是 `modulate:a`**：
## 片元 shader 会整个覆写 `COLOR`，挂在它上面的 `modulate` 就失效了 —— 实测遮罩会一直
## 挂在那儿（四角永远黑的），"睁眼"变成"开完就停"。没有材质时（降级路径）才用 modulate，
## 那时它就是一个普通黑色 ColorRect，modulate 正常生效。
func _fade_out(scale_factor: float, mat: ShaderMaterial) -> void:
	var fade := create_tween()
	fade.set_parallel(true)
	if mat != null:
		# 眼睑层：**先**化掉（藏在白光下面，看不见），淡 shader 的 overlay_alpha
		# （modulate 会被片元 shader 覆写，无效）。
		fade.tween_method(
			func(v: float): mat.set_shader_parameter("overlay_alpha", v),
			1.0, 0.0, LID_DISSOLVE_DURATION * scale_factor
		).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		# 白光层：随后（与上句并行、但时长久得多）从全白褪到透明。
		fade.tween_property(flash, "color:a", 0.0, FADE_DURATION * scale_factor) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	else:
		# 降级路径没有眼睛（遮罩就是一块全屏黑），父层 modulate 一淡就把两个子层
		# 一起带走，世界均匀地浮出来，不存在眼形轮廓问题。
		fade.tween_property(self, "modulate:a", 0.0, FADE_DURATION * scale_factor) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await fade.finished
	visible = false
	# 收尾归零：不管走哪条路径，过场结束后组件都要回到"干净"状态
	# （闪光停在 1.0 = 全屏白的话，下一段演出会被一层白蒙住）。
	_apply_flash(0.0)


func _apply_flash(t: float) -> void:
	if flash == null:
		return
	flash.color = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, flash_intensity_at(t))


## 当前闪光强度（0~FLASH_PEAK）。没有闪光层时返回 null。
func get_flash_intensity() -> Variant:
	if flash == null:
		return null
	return flash.color.a


func _apply_progress(mat: ShaderMaterial, p: float) -> void:
	# 左眼（基准）。
	mat.set_shader_parameter("lid_upper_y", lid_upper_y_at(p))
	mat.set_shader_parameter("lid_lower_y", lid_lower_y_at(p))
	mat.set_shader_parameter("lid_corner_y", corner_y_at(p))
	# 右眼（慢半拍）。
	mat.set_shader_parameter("lid_upper_y_right", lid_upper_y_right_at(p))
	mat.set_shader_parameter("lid_lower_y_right", lid_lower_y_right_at(p))
	mat.set_shader_parameter("lid_corner_y_right", corner_y_right_at(p))
	mat.set_shader_parameter("lid_shade", lid_shade_at(p))


func _create_material() -> ShaderMaterial:
	# headless（Dummy 渲染器）下挂 shader 会 push 引擎错误 → GUT 判失败，直接不建。
	if not RenderCapabilitiesScript.supports_shaders():
		return null
	if not ResourceLoader.exists(SHADER_PATH):
		return null
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		return null
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("eye_center_left", EYE_CENTER_LEFT)
	mat.set_shader_parameter("eye_center_right", EYE_CENTER_RIGHT)
	mat.set_shader_parameter("eye_half_width", EYE_HALF_WIDTH)
	mat.set_shader_parameter("eye_profile_power", EYE_PROFILE_POWER)
	mat.set_shader_parameter("overlay_alpha", 1.0)
	_apply_progress(mat, 0.0)
	return mat


# ── 两片眼睑的运动曲线（纯函数，测试直接断言）──────────────────────
#
# 下面这组是**左眼**的曲线（两只眼形状相同，右眼只是把进度整体推迟
# `EYE_PHASE_RIGHT`，见 `lid_*_right_at()`）。

## 上眼睑在眼睛中央的 y：从闭合线一路抬到屏幕外。单调不增。
static func lid_upper_y_at(p: float) -> float:
	var t: float = clampf(p, 0.0, 1.0)
	if t <= 0.0:
		return LID_CLOSED_Y
	if t >= 1.0:
		return LID_UPPER_OPEN_Y
	var crack: float = LID_CLOSED_Y - CRACK_GAP * CRACK_UPPER_SHARE
	if t < CRACK_FRACTION:
		return lerpf(LID_CLOSED_Y, crack, t / CRACK_FRACTION)
	var k: float = (t - CRACK_FRACTION) / (1.0 - CRACK_FRACTION)
	return lerpf(crack, LID_UPPER_OPEN_Y, _ease_out_cubic(k))


## 下眼睑在眼睛中央的 y：从同一条闭合线往下落，但**慢半拍**。单调不减。
static func lid_lower_y_at(p: float) -> float:
	var t: float = clampf(p, 0.0, 1.0)
	if t <= 0.0:
		return LID_CLOSED_Y
	if t >= 1.0:
		return LID_LOWER_OPEN_Y
	var crack: float = LID_CLOSED_Y + CRACK_GAP * (1.0 - CRACK_UPPER_SHARE)
	if t < CRACK_FRACTION:
		return lerpf(LID_CLOSED_Y, crack, t / CRACK_FRACTION)
	var span: float = 1.0 - CRACK_FRACTION - LOWER_LAG
	var k: float = clampf((t - CRACK_FRACTION - LOWER_LAG) / span, 0.0, 1.0)
	return lerpf(crack, LID_LOWER_OPEN_Y, _ease_out_cubic(k))


## 白光包络（纯函数）：t 是**变白段的进度**（0 → 1）。
## t=0 时 0（起手不能自己亮），t=1 时到 `FLASH_PEAK` = 全屏白，之后**保持不降**。
##
## **缓动只在这一处**：曲线用 smoothstep（慢起 → 中段加速 → 收到白上），不是 ease-out。
## 用户反馈"变白太快"，要的是 1 秒里渐渐变白，开头那一下就冲上去的话看不出过程。
## 对应的 tween 用 TRANS_LINEAR —— 缓动放两份（tween 一份、函数一份）会叠成更冲的曲线，
## 而且测试断言的就不是真实运动了。
##
## **没有衰减段**：变到全白就停住，由第四段把整层（白 + 眼睑）一起淡掉。
static func flash_intensity_at(t: float) -> float:
	var x: float = clampf(t, 0.0, 1.0)
	if x <= 0.0:
		return 0.0
	return FLASH_PEAK * smoothstep(0.0, 1.0, x)


## 眼角线：随视线从中线偏下的闭合位抬到正中（像头抬起来、视线落定）。
static func corner_y_at(p: float) -> float:
	return lerpf(LID_CLOSED_Y, LID_CORNER_Y_OPEN, _ease_out_cubic(clampf(p, 0.0, 1.0)))


## 眼眶阴影：刚睁开最重，睁满后完全淡掉（0）。
static func lid_shade_at(p: float) -> float:
	return lerpf(LID_SHADE_REST, LID_SHADE_OPEN, clampf(p, 0.0, 1.0))


## 右眼的进度：整体推迟 `EYE_PHASE_RIGHT`，但**在 p=1 处重标定追平**。
##
## 不能简单地写成 `p - EYE_PHASE_RIGHT`：那样右眼到 p=1 只走到 0.94，最后这 6% 的行程
## 永远走不完 —— 睁眼结束时右眼睑比左眼睑低一截（GUT 的 endpoint 断言就是这么抓到的）。
## 重标定后两个端点仍然严格对齐（0 → 闭合、1 → 睁满），中间始终落后。
static func right_progress(p: float) -> float:
	var t: float = clampf(p, 0.0, 1.0)
	if t >= 1.0:
		return 1.0
	return clampf((t - EYE_PHASE_RIGHT) / (1.0 - EYE_PHASE_RIGHT), 0.0, 1.0)


## 右眼的两片眼睑 = 左眼曲线在 `right_progress()` 处的取值。
## 相位差是"活的"来源：两只眼一起睁、睁得一样多，就又变回一只眼了。
static func lid_upper_y_right_at(p: float) -> float:
	return lid_upper_y_at(right_progress(p))


static func lid_lower_y_right_at(p: float) -> float:
	return lid_lower_y_at(right_progress(p))


static func corner_y_right_at(p: float) -> float:
	return corner_y_at(right_progress(p))


## 睁满时单只眼睛的垂直开口（UV 高度）。
static func aperture_height() -> float:
	return LID_LOWER_OPEN_Y - LID_UPPER_OPEN_Y


## 上眼睑弧的振幅（相对眼角线抬高多少，UV）。
static func upper_arc_amplitude() -> float:
	return LID_CORNER_Y_OPEN - LID_UPPER_OPEN_Y


## 下眼睑弧的振幅。
static func lower_arc_amplitude() -> float:
	return LID_LOWER_OPEN_Y - LID_CORNER_Y_OPEN


## 眼角夹角（度）：上下两条眼睑边缘在眼角相交的角度。
##
## 抛物线轮廓下，边缘在眼角的斜率 = 2 × 振幅 / 半宽。它在 UV 里算，**要除以宽高比**
## 才是屏幕上的斜率（UV 的 dx 被屏宽拉伸、dy 被屏高拉伸，dy/dx 因此要乘 H/W = 1/宽高比）。
## 夹角越大越钝。**这条是"眼睛 vs 眼镜片"的可测代理**：眼镜片的轮廓在眼角被磨圆
## （切线趋近竖直），夹角会趋近 180°；真正的眼形落在 70°~110° 这一带
## （参考图那只见 95° 左右）。
static func corner_angle_degrees() -> float:
	var upper_slope: float = 2.0 * upper_arc_amplitude() / EYE_HALF_WIDTH / VIEW_ASPECT
	var lower_slope: float = 2.0 * lower_arc_amplitude() / EYE_HALF_WIDTH / VIEW_ASPECT
	return rad_to_deg(atan(upper_slope) + atan(lower_slope))


## 上眼睑走过的行程占整段的比例（0~1）。用来断言"上睑主导"。
static func upper_travel_at(p: float) -> float:
	return (LID_CLOSED_Y - lid_upper_y_at(p)) / (LID_CLOSED_Y - LID_UPPER_OPEN_Y)


## 下眼睑走过的行程占整段的比例（0~1）。
static func lower_travel_at(p: float) -> float:
	return (lid_lower_y_at(p) - LID_CLOSED_Y) / (LID_LOWER_OPEN_Y - LID_CLOSED_Y)


static func _ease_out_cubic(x: float) -> float:
	var inv: float = 1.0 - clampf(x, 0.0, 1.0)
	return 1.0 - inv * inv * inv
