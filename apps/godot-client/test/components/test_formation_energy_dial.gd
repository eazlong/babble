extends GutTest

## FormationEnergyDial 组件测试（ADR 0003 #12：阵法能量 0–8）。
##
## 原则同 test_letter_spirit.gd：**只断言状态与几何，不断言帧时序**。
## 演出（余辉衰减、冲击波、爆光）用显式喂 delta 的方式推进，不依赖真实帧率。

const DialScript = preload("res://assets/scripts/components/FormationEnergyDial.gd")

func _make_dial(in_tree: bool = true) -> Control:
	var dial: Control = DialScript.new()
	dial.size = Vector2(140, 140)
	if in_tree:
		add_child(dial)
	return dial

# ── 构造 ────────────────────────────────────────────────────────────

func test_ready_builds_readout_and_aura() -> void:
	var dial = _make_dial()
	assert_not_null(dial.get_node_or_null("Readout"), "应有 N/8 读数 Label")
	assert_not_null(dial.get_node_or_null("Aura"), "应有阵纹氛围层")
	assert_eq(dial.energy, 0, "初始能量应为 0")
	assert_eq(dial.max_energy, 8, "默认上限应为 8（ADR 0003 #12）")
	dial.free()

func test_aura_draws_behind_segments() -> void:
	# 阵纹若画在父节点 _draw() 之上，会盖住能量弧段——这是本组件唯一的层级陷阱。
	var dial = _make_dial()
	var aura: TextureRect = dial.get_node("Aura")
	assert_true(aura.show_behind_parent, "阵纹必须在弧段之下（show_behind_parent = true）")
	dial.free()

func test_runs_headless_without_ring_texture() -> void:
	# 贴图缺失时不应报错，也不应把 _draw() 打挂（阵位盘不依赖贴图，只有氛围层没了）。
	var dial = _make_dial()
	dial.set_energy(3, 8, false)
	assert_eq(dial.energy, 3, "无贴图也应正常记录能量")
	dial.free()

# ── 阵位几何 ────────────────────────────────────────────────────────

func test_slot_angles_are_evenly_spaced_from_top() -> void:
	# 底图那 8 个节点是手绘的（实测间隔 31.7°–58.3°），代码必须自己保证均匀，
	# 所以这条断言是"别再回头去贴合美术"的护栏。
	var dial = _make_dial()
	dial.set_energy(0, 8, false)
	var first: float = dial._slot_angle(0)
	assert_almost_eq(rad_to_deg(first), -90.0, 0.001, "第 0 个阵位应在正上方")
	for i in range(1, 8):
		var step: float = rad_to_deg(dial._slot_angle(i) - dial._slot_angle(i - 1))
		assert_almost_eq(step, 45.0, 0.001, "阵位 %d 与上一个的间隔应为 45°" % i)
	dial.free()

func test_slot_angles_follow_max_energy() -> void:
	var dial = _make_dial()
	dial.set_energy(0, 5, false)
	var step: float = rad_to_deg(dial._slot_angle(1) - dial._slot_angle(0))
	assert_almost_eq(step, 72.0, 0.001, "5 格时进度间隔应为 360/5")
	dial.free()

func test_socket_disc_covers_artwork_node() -> void:
	# 底图节点盘半径是半宽的 0.089；阵位盘必须更大才盖得住手绘误差。
	var dial = _make_dial()
	assert_true(DialScript.AURA_SOCKET_RADIUS_FRAC > 0.089,
		"阵位盘比例 %f 必须大于底图节点盘 0.089" % DialScript.AURA_SOCKET_RADIUS_FRAC)
	assert_true(dial._socket_radius() > dial._half() * 0.089, "换算成像素也要盖得住")
	dial.free()

func test_socket_fits_inside_control_width() -> void:
	# 阵位盘不能溢出控件：溢出的部分会被父节点裁掉或压到相邻 UI 上。
	var dial = _make_dial()
	var outer: float = dial._slot_radius() + dial._socket_radius()
	assert_true(outer <= dial._half() + 0.001,
		"阵位外缘 %f 不应超过半宽 %f" % [outer, dial._half()])
	dial.free()

# ── 读数与钳制 ──────────────────────────────────────────────────────

func test_readout_tracks_energy() -> void:
	var dial = _make_dial()
	dial.set_energy(5, 8, false)
	var readout: Label = dial.get_node("Readout")
	assert_eq(readout.text, "5/8", "读数应为当前/上限")
	dial.free()

func test_set_energy_clamps_out_of_range() -> void:
	var dial = _make_dial()
	dial.set_energy(99, 8, false)
	assert_eq(dial.energy, 8, "超出上限应钳到上限")
	dial.set_energy(-3, 8, false)
	assert_eq(dial.energy, 0, "负值应钳到 0")
	dial.free()

func test_segment_count_follows_max_energy() -> void:
	# 段数由数据决定，不写死 8：充能上限将来可能改。
	var dial = _make_dial()
	dial.set_energy(2, 5, false)
	assert_eq(dial.max_energy, 5, "段数应跟随上限")
	assert_eq(dial.get_segment_pulse(5), 0.0, "越界查询应安全返回 0")
	dial.free()

# ── 点亮演出 ────────────────────────────────────────────────────────

func test_gain_pulses_only_new_segments() -> void:
	var dial = _make_dial()
	dial.set_energy(2, 8, false)
	assert_eq(dial.get_segment_pulse(0), 0.0, "静默推进不应留余辉")

	dial.set_energy(3, 8)
	assert_eq(dial.get_segment_pulse(2), 1.0, "新增的第 3 格应满余辉")
	assert_eq(dial.get_segment_pulse(0), 0.0, "旧格不应被重新点亮")
	assert_eq(dial.get_segment_pulse(3), 0.0, "未充能的格不应有余辉")
	dial.free()

func test_multi_step_gain_pulses_every_skipped_segment() -> void:
	var dial = _make_dial()
	dial.set_energy(1, 8, false)
	dial.set_energy(4, 8)
	for i in range(1, 4):
		assert_eq(dial.get_segment_pulse(i), 1.0, "一次跳多格时每格都应点亮 (index %d)" % i)
	dial.free()

func test_animate_false_suppresses_pulse() -> void:
	var dial = _make_dial()
	dial.set_energy(6, 8, false)
	assert_eq(dial.get_segment_pulse(5), 0.0, "读档恢复不应播点亮演出")
	dial.free()

func test_pulse_decays_to_zero() -> void:
	var dial = _make_dial()
	dial.set_energy(1, 8)
	assert_eq(dial.get_segment_pulse(0), 1.0, "前置：第 1 格应刚点亮")
	dial._process(DialScript.PULSE_DECAY_S * 0.5)
	var mid: float = dial.get_segment_pulse(0)
	assert_true(mid > 0.0 and mid < 1.0, "半衰期后余辉应在 0 与 1 之间，实测 %f" % mid)
	dial._process(DialScript.PULSE_DECAY_S)
	assert_eq(dial.get_segment_pulse(0), 0.0, "余辉应最终归零")
	dial.free()

func test_energy_loss_does_not_pulse() -> void:
	# 扣能量（重置/失败回退）不该给"充能成功"的正反馈。
	var dial = _make_dial()
	dial.set_energy(4, 8, false)
	dial.set_energy(1, 8)
	assert_eq(dial.energy, 1, "能量应下降")
	assert_eq(dial.get_segment_pulse(0), 0.0, "降档不应产生余辉")
	dial.free()

# ── 攒满 ────────────────────────────────────────────────────────────

func test_is_full_only_at_max() -> void:
	var dial = _make_dial()
	dial.set_energy(7, 8, false)
	assert_false(dial.is_full(), "7/8 不应算满")
	dial.set_energy(8, 8, false)
	assert_true(dial.is_full(), "8/8 应算满")
	dial.free()

func test_reaching_full_triggers_burst() -> void:
	var dial = _make_dial()
	dial.set_energy(8, 8, false)
	assert_eq(dial._burst, 0.0, "静默到满不应爆光（读档场景）")
	dial.set_energy(7, 8, false)
	dial.set_energy(8, 8)
	assert_true(dial._burst > 0.0, "攒满那一刻应爆光")
	dial.free()

func test_burst_decays_and_full_stays_lit() -> void:
	var dial = _make_dial()
	dial.set_energy(7, 8, false)
	dial.set_energy(8, 8)
	dial._process(10.0)
	assert_eq(dial._burst, 0.0, "爆光应衰减干净")
	assert_true(dial.is_full(), "爆光结束后仍应是满格状态")
	dial.free()

func test_spin_is_faster_when_full() -> void:
	# 扫光转速是"满了"的第二个可观察信号（不依赖颜色）。
	var idle = _make_dial()
	idle.set_energy(3, 8, false)
	idle._process(1.0)
	var idle_speed: float = idle.get_sweep_angle()
	idle.free()

	var full = _make_dial()
	full.set_energy(8, 8, false)
	full._process(1.0)
	assert_true(full.get_sweep_angle() > idle_speed,
		"满格扫光应快于未满（满 %f vs 未满 %f）" % [full.get_sweep_angle(), idle_speed])
	full.free()

func test_sweep_wraps_and_aura_stays_put() -> void:
	var dial = _make_dial()
	dial._process(120.0)
	var angle: float = dial.get_sweep_angle()
	assert_true(angle >= 0.0 and angle < 360.0, "扫光角应回绕到 [0,360)，实测 %f" % angle)
	# 底图必须**不转**：一转阵位就和环带上的阵纹对不上了。
	var aura: TextureRect = dial.get_node("Aura")
	assert_almost_eq(aura.rotation_degrees, 0.0, 0.001, "阵纹底图不应旋转")
	dial.free()
