class_name FormationEnergyDial
extends Control

## 阵法能量环 —— ADR 0003「阵法能量 0–8」的表层表示。
##
## 为什么不是 8 枚平铺光点：门控的叙事外壳是**阵法**，一排等距圆点读起来像进度条，
## 不像"法阵在蓄能"。这里改成环形法阵盘：外圈是取自 `formation_ring.png` 的
## 金色阵纹带（符文 + 环带 + 深色盘心），带上均匀排布 8 个**阵位**，
## 每完成一次复习点亮一个；攒满时整盘转快、爆一次光。
##
## 几何以代码为准，美术只做装饰——原图那 8 个节点是手绘的，实测角度间隔在
## 31.7°–58.3° 之间（不是 45°），节点盘心距半宽 0.639、盘半径 0.089。
## 所以代码按**自己的均匀 45°** 排 8 个阵位，并用略大的阵位盘（半宽的 0.138）
## 盖住原图节点：错位就看不见了。想换底图时只改 `AURA_TEXTURE`，
## 并用 `tmp/asset-gen/dial/make_formation_aura.py` 重新导出（脚本会打印新比例）。
##
## 设计约束：
## - **阵位数由 `max_energy` 决定**，不写死 8：ADR 说当前是 0–8，但充能上限属于
##   GameManager 的数据，UI 不该比数据更早假定它永远是 8。
## - 能量只由外部 `set_energy()` 推入，组件不自己读 GameManager（CLAUDE.md §12：
##   UI 只反映状态，不持有业务状态）。

## 阵纹底图（由 make_formation_aura.py 从 formation_ring.png 抠出：环带 + 符文 + 盘心）。
const AURA_TEXTURE: String = "res://assets/textures/ui/archive_formation_aura.png"

## 贴图里环带/节点的几何比例（半宽为 1），与导出脚本打印的 stats 对齐。
const AURA_SLOT_RADIUS_FRAC: float = 0.639
## 阵位盘半径。必须**大于**原图节点盘（0.089）才盖得住手绘误差；1.55 倍留够了余量。
const AURA_SOCKET_RADIUS_FRAC: float = 0.138

const COLOR_SOCKET: Color = Color(0.045, 0.042, 0.075, 0.94)
## 已点亮阵位底下的深色领圈。
const COLOR_GEM_BASE: Color = Color(0.070, 0.048, 0.040, 0.95)
const COLOR_SOCKET_RIM: Color = Color(0.62, 0.50, 0.24, 0.85)
const COLOR_LIT: Color = Color(1.00, 0.73, 0.16, 1.00)
const COLOR_LIT_CORE: Color = Color(1.00, 0.95, 0.70, 1.00)
const COLOR_LIT_GLOW: Color = Color(1.00, 0.64, 0.10, 0.20)
const COLOR_FULL: Color = Color(1.00, 0.85, 0.36, 1.00)
const COLOR_FLOW: Color = Color(1.00, 0.72, 0.22, 0.58)
const COLOR_SWEEP: Color = Color(1.00, 0.88, 0.52, 1.00)
const COLOR_SHOCK: Color = Color(1.00, 0.92, 0.58, 1.00)
## 盘心说明文字：比读数暗一档，避免与 `N/8` 抢注意力。
const COLOR_CAPTION: Color = Color(0.86, 0.78, 0.55, 0.92)

## 盘心深色底的半径（半宽为 1）。与 `make_formation_aura.py` 的
## `BAND_INNER_FRAC` 对齐——盘心底比它再大就会盖住阵位盘的内缘。
const AURA_PLATE_RADIUS_FRAC: float = 0.50

const SWEEP_SPAN_DEG: float = 26.0
const SWEEP_ARC_RADIUS_FRAC: float = 1.20
const SPIN_IDLE_DEG_PER_S: float = 20.0
const SPIN_FULL_DEG_PER_S: float = 78.0
## 单个阵位点亮的余辉衰减时长（秒）。
const PULSE_DECAY_S: float = 0.55
## 一次充能冲击波的扩散时长（秒）。
const SHOCK_DURATION_S: float = 0.65

var energy: int = 0
var max_energy: int = 8
## 盘心读数上方的说明文字（如"阵法能量"）。留空则整条不占位。
## 说明文字归组件自己管：它的落点取决于**盘心深色底的半径**，让调用方在场景里
## 另摆一个 Label，换底图时就会飘到阵纹带上（金色字压在金色符文上，对比度全丢）。
var caption: String = "":
	set(value):
		caption = value
		_refresh_caption()

## 每个阵位的余辉强度 0–1，新点亮的阵位从 1 衰减到 0。
var _pulse: PackedFloat32Array = PackedFloat32Array()
## 冲击波进度；<0 表示没有在播。
var _shock: float = -1.0
## 攒满时的爆光强度，衰减到 0 后维持"满格常亮"。
var _burst: float = 0.0
## 巡环光点角度（度）。底图不转（转了阵位就对不上了），转动的是这道扫光。
var _spin_deg: float = 0.0

var _aura: TextureRect
var _readout: Label
var _caption_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_children()
	_sync_segments()
	_refresh_readout()
	queue_redraw()


func _ensure_children() -> void:
	if _aura == null:
		_aura = TextureRect.new()
		_aura.name = "Aura"
		_aura.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_aura.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 阵纹必须画在本组件 _draw() 的阵位**之下**，否则会盖住点亮的阵位。
		_aura.show_behind_parent = true
		if ResourceLoader.exists(AURA_TEXTURE):
			_aura.texture = load(AURA_TEXTURE)
		add_child(_aura)
	if _readout == null:
		_readout = Label.new()
		_readout.name = "Readout"
		# **不用 PRESET_FULL_RECT**：满屏锚点会和 _layout_children 里的 size 赋值打架，
		# Godot 会报 "Nodes with non-equal opposite anchors will have their size
		# overridden after _ready()"（在 GUT 里表现为整片测试因 unexpected error 失败）。
		# 位置与尺寸全由 _layout_children 显式给出。
		_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_readout)
	if _caption_label == null:
		_caption_label = Label.new()
		_caption_label.name = "Caption"
		_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_caption_label.add_theme_color_override("font_color", COLOR_CAPTION)
		_caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_caption_label)
	_layout_children()
	_refresh_caption()
	_refresh_readout()


func _layout_children() -> void:
	if _aura != null:
		# 贴图整张铺满控件：环带比例是相对半宽定义的，所以贴图直径 == 控件宽。
		_aura.size = size
		_aura.position = Vector2.ZERO
		_aura.pivot_offset = size * 0.5
	# 读数与说明都排在**盘心深色底**里，两行的总高必须小于盘心直径，
	# 否则字会压到金色阵纹带上（见 AURA_PLATE_RADIUS_FRAC）。
	var plate_r: float = _half() * AURA_PLATE_RADIUS_FRAC
	var center: Vector2 = size * 0.5
	if _caption_label != null:
		var cap_h: float = maxf(_half() * 0.20, 12.0)
		_caption_label.add_theme_font_size_override("font_size", int(maxf(_half() * 0.15, 10.0)))
		_caption_label.size = Vector2(plate_r * 1.55, cap_h)
		_caption_label.position = Vector2(
			center.x - plate_r * 0.775, center.y - plate_r * 0.62
		)
	if _readout != null:
		_readout.add_theme_font_size_override("font_size", int(maxf(_half() * 0.32, 16.0)))
		# 有说明文字时读数下沉一行（盒子上沿下移），没说明时盒子占满盘心 → 自动垂直居中。
		var box_top: float = center.y - plate_r * (0.06 if not caption.is_empty() else 1.0)
		_readout.position = Vector2(center.x - plate_r, box_top)
		_readout.size = Vector2(plate_r * 2.0, center.y + plate_r - box_top)


func _half() -> float:
	return maxf(minf(size.x, size.y) * 0.5, 8.0)


## 阵位盘心到圆心的距离（像素）。
func _slot_radius() -> float:
	return _half() * AURA_SLOT_RADIUS_FRAC


## 单个阵位盘的半径（像素）。
func _socket_radius() -> float:
	return _half() * AURA_SOCKET_RADIUS_FRAC


## 第 index 个阵位的角度（弧度）。第 0 个在正上方，顺时针排布，与底图节点一致。
func _slot_angle(index: int) -> float:
	return -PI * 0.5 + TAU * float(index) / float(max_energy)


## 推入能量。`animate` 为假时只改数字不播演出（进场恢复存档用，避免一进场就爆光）。
func set_energy(current: int, maximum: int, animate: bool = true) -> void:
	var new_max: int = maxi(maximum, 1)
	var new_energy: int = clampi(current, 0, new_max)
	var was_max: int = max_energy
	max_energy = new_max
	if max_energy != was_max:
		_sync_segments()
	var previous: int = energy
	energy = new_energy
	_refresh_readout()
	if animate:
		if energy > previous:
			# 只点亮新增的阵位；一次充能 +1 是常态，但契约上允许一次跳多格。
			for i in range(previous, energy):
				if i >= 0 and i < _pulse.size():
					_pulse[i] = 1.0
			_shock = 0.0
		if energy >= max_energy and previous < max_energy:
			_burst = 1.0
	queue_redraw()


func is_full() -> bool:
	return energy >= max_energy


## 给测试与控制器观察用：第 index 个阵位的余辉强度。
func get_segment_pulse(index: int) -> float:
	if index < 0 or index >= _pulse.size():
		return 0.0
	return _pulse[index]


## 巡环扫光的当前角度（度），测试用来验证"满了转更快"。
func get_sweep_angle() -> float:
	return _spin_deg


func _sync_segments() -> void:
	var next := PackedFloat32Array()
	next.resize(max_energy)
	for i in range(max_energy):
		next[i] = _pulse[i] if i < _pulse.size() else 0.0
	_pulse = next


func _refresh_readout() -> void:
	if _readout != null:
		_readout.text = "%d/%d" % [energy, max_energy]
		_readout.add_theme_color_override("font_color", COLOR_FULL if is_full() else COLOR_LIT)
	if _aura != null:
		# 满格时底图整体提亮一点，让"阵成"与"阵未成"隔着屏幕也能分辨。
		_aura.modulate = Color(1.06, 1.01, 0.93, 1.0) if is_full() else Color(0.84, 0.82, 0.88, 1.0)


func _refresh_caption() -> void:
	if _caption_label == null:
		return
	_caption_label.text = caption
	_caption_label.visible = not caption.is_empty()
	# 有／无说明文字会改变读数的落点，所以顺带重排一次。
	if is_inside_tree():
		_layout_children()


func _process(delta: float) -> void:
	var sweep_speed: float = SPIN_FULL_DEG_PER_S if is_full() else SPIN_IDLE_DEG_PER_S
	_spin_deg = fmod(_spin_deg + sweep_speed * delta, 360.0)
	for i in range(_pulse.size()):
		if _pulse[i] > 0.0:
			_pulse[i] = maxf(_pulse[i] - delta / PULSE_DECAY_S, 0.0)
	if _shock >= 0.0:
		_shock += delta / SHOCK_DURATION_S
		if _shock >= 1.0:
			_shock = -1.0
	if _burst > 0.0:
		_burst = maxf(_burst - delta / (SHOCK_DURATION_S * 1.6), 0.0)
	# 扫光一直在转，所以每帧都要重绘。盘上只有 ~20 条 draw_arc/draw_circle，
	# 而且只有一个这样的控件，代价可以忽略。
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_children()
		queue_redraw()


func _draw() -> void:
	var center: Vector2 = size * 0.5
	var slot_r: float = _slot_radius()
	var sock_r: float = _socket_radius()

	_draw_sweep(center, slot_r)
	_draw_flow(center, slot_r, sock_r)
	for i in range(max_energy):
		_draw_socket(center, i, slot_r, sock_r)
	_draw_burst(center, slot_r)
	if is_full():
		# 阵成：盘心补一圈常亮微光，把"满"和"没满"在第一眼就分开。
		var inner: Color = COLOR_FULL
		inner.a = 0.20 + _burst * 0.32
		draw_arc(center, slot_r * 0.52, 0.0, TAU, 80, inner, 2.0, true)


## 巡环扫光：一道短亮弧沿阵纹带绕圈，转速随能量状态变化。底图不转，
## "这东西是活的"全靠它。
func _draw_sweep(center: Vector2, slot_r: float) -> void:
	var radius: float = slot_r * SWEEP_ARC_RADIUS_FRAC
	var start: float = deg_to_rad(_spin_deg - 90.0 - SWEEP_SPAN_DEG * 0.5)
	var tail: Color = COLOR_SWEEP
	tail.a = 0.16
	var head: Color = COLOR_SWEEP
	head.a = 0.62 if is_full() else 0.44
	# 先画长而淡的尾巴，再叠短而亮的头，做出"扫过"的方向感。
	draw_arc(center, radius, start - 0.30, start + deg_to_rad(SWEEP_SPAN_DEG), 24, tail, 5.0, true)
	draw_arc(center, radius, start + 0.16, start + deg_to_rad(SWEEP_SPAN_DEG), 20, head, 3.0, true)


## 能量在相邻两个已点亮阵位之间导通。只连"两端都亮"的相邻对：
## 没点亮的格位不参与导通，一眼就能看出阵势连到了第几格。
func _draw_flow(center: Vector2, slot_r: float, sock_r: float) -> void:
	if energy < 2:
		return
	for i in range(max_energy):
		var j: int = (i + 1) % max_energy
		if i >= energy or j >= energy:
			continue
		var a0: float = _slot_angle(i)
		var a1: float = _slot_angle(j)
		if a1 <= a0:
			a1 += TAU
		# 弧段两端各缩掉一个阵位盘，避免导通弧压在阵位盘上。
		var inset: float = (sock_r * 0.72) / maxf(slot_r, 1.0)
		draw_arc(center, slot_r, a0 + inset, a1 - inset, 20, COLOR_FLOW, 2.2, true)


func _draw_socket(center: Vector2, index: int, slot_r: float, sock_r: float) -> void:
	var angle: float = _slot_angle(index)
	var pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * slot_r
	var lit: bool = index < energy
	var pulse: float = _pulse[index] if index < _pulse.size() else 0.0

	if lit:
		var glow: Color = COLOR_LIT_GLOW
		glow.a = minf(glow.a + pulse * 0.42 + _burst * 0.22, 0.80)
		draw_circle(pos, sock_r * (1.34 + pulse * 0.26), glow)
		# 深色领圈：既压掉底图手绘节点可能漏出来的残边，又把金色宝珠从
		# 明亮的墙面/烛台上"托"起来——没有它，金色在亮底上会糊成一片奶白。
		draw_circle(pos, sock_r * 1.10, COLOR_GEM_BASE)
		draw_circle(pos, sock_r, COLOR_FULL if is_full() else COLOR_LIT)
		# 中心高光：让阵位读起来是"珠子/宝石"而不是一块色斑。
		draw_circle(pos - Vector2(sock_r * 0.26, sock_r * 0.26), sock_r * 0.30, COLOR_LIT_CORE)
	else:
		# 未点亮的格位也要看得见轮廓，否则 0/8 时整盘是空的，玩家不知道能装几格。
		draw_circle(pos, sock_r, COLOR_SOCKET)
		draw_arc(pos, sock_r, 0.0, TAU, 28, COLOR_SOCKET_RIM, 1.6, true)


## 充能冲击波：从阵盘向外扩散并淡出的细环，是"这一格刚刚点亮"的即时反馈。
func _draw_burst(center: Vector2, slot_r: float) -> void:
	if _shock < 0.0:
		return
	var ring: Color = COLOR_SHOCK
	ring.a = (1.0 - _shock) * 0.72
	draw_arc(center, slot_r + _shock * slot_r * 0.62, 0.0, TAU, 96, ring, 2.6, true)
