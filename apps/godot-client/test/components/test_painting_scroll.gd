extends GutTest

## 墙上画卷（词灵书阁入口）的独立精灵：睡着 / 亮起来 / 飞向玩家 / 淡出。
##
## 这里守三条容易复发的错：
## 1. **口令没说完就亮** —— 亮起来必须由控制器挂在口令命中之后（那条守卫在
##    test/scenes/test_mirage_inn_scroll_awakening.gd）；
## 2. **切视图把正在飞的画按掉** —— 画在场景根下、不属于任何房间视图，控制器切视图时
##    只写"待机可见性"，表演中只记不兑现。画挂在房间视图里时，切到书阁那一帧它会在半空消失；
## 3. **飞完盖不满舞台** —— 盖不满就会在书阁淡入时露出墙，穿帮。
##
## 时间缩放 `speed_scale` 只给测试用（把 2.5s 的表演压到几十毫秒），默认原速。

const PaintingScenePath: String = "res://assets/scenes/components/PaintingScroll.tscn"
const PaintingScriptPath: String = "res://assets/scripts/components/PaintingScroll.gd"

## 把 0.85s / 1.15s / 0.5s 压到几十毫秒。
const FAST: float = 0.02
## 画卷在主人房里的落点（MirageInnIntroduction.tscn 的 WallPainting 实例坐标）。
## 组件场景自己的原点是 (0,0)，实例化时才被放到墙上 —— 这里照实例的做法摆一次，
## 好断言"演出前后画都回到墙上原位"。
const HOME_POSITION: Vector2 = Vector2(1001, 457.5)


func _make() -> Sprite2D:
	var packed: PackedScene = load(PaintingScenePath)
	assert_not_null(packed, "PaintingScroll.tscn 应能加载")
	if packed == null:
		return null
	var painting: Sprite2D = packed.instantiate()
	painting.position = HOME_POSITION
	add_child_autofree(painting)
	return painting


# ── 结构：独立精灵 + 四层（装裱 / 沉睡画心 / 光晕 / 苏醒画心）──────────

func test_scene_is_a_sprite_with_the_two_painting_states_and_a_glow() -> void:
	var painting := _make()
	if painting == null:
		return
	assert_true(painting is Sprite2D, "画卷本体必须是 Sprite2D（独立精灵）")
	assert_not_null(painting.texture, "沉睡态画心应有贴图")
	assert_true(
		painting.get_script().resource_path == PaintingScriptPath,
		"画卷应挂 PaintingScroll.gd，实际=%s" % str(painting.get_script())
	)
	var awake_art: Sprite2D = painting.get_node_or_null("AwakeArt")
	var wall_glow: Sprite2D = painting.get_node_or_null("WallGlow")
	assert_not_null(awake_art, "应有苏醒态画心 AwakeArt")
	assert_not_null(wall_glow, "应有暖光晕 WallGlow")
	if awake_art == null or wall_glow == null:
		return
	assert_ne(awake_art.texture, painting.texture, "苏醒态必须是另一张贴图（沉睡/苏醒两态）")


## 装裱（木杆 + 青绫 + 挂绳）跟着画心一起演：主人房底图已拆层，立轴只在这里画一次。
func test_mount_travels_with_the_painting_and_keeps_the_core_centered() -> void:
	var painting := _make()
	if painting == null:
		return
	var mount: Sprite2D = painting.get_node_or_null("MountArt")
	assert_not_null(mount, "应有装裱层 MountArt（分层底图里的立轴那一层）")
	if mount == null:
		return
	assert_not_null(mount.texture, "装裱层应有贴图")
	assert_ne(mount.texture, painting.texture, "装裱层不能用画心贴图")
	assert_true(
		mount.texture.get_size().x > painting.texture.get_size().x
		and mount.texture.get_size().y > painting.texture.get_size().y,
		"装裱层应比画心大（木杆/青绫围在画心外），实际 %s vs 画心 %s" % [
			str(mount.texture.get_size()), str(painting.texture.get_size())]
	)
	assert_true(mount.z_index < 0, "装裱要垫在画心底下（画心盖住装裱里那块画心）")
	# 装裱里那块画心必须**正好**落在根节点画心底下。它**不在层中心**：分层 320×512 里画心区
	# (70,90)-(268,441)（= 平铺底图上画心实测区 x908-1092 / y288-624 减去层原点 (832,192)），
	# 中心 (169, 265.5)，而层中心是 (160, 256) → 装裱要偏 (−9, −9.5)。差一像素，墙上就会
	# 露出双影边。这个矩形是**量出来的**，所以下面对贴图本身再核一遍（防止有人重切了层）。
	var layer_core := Rect2(70, 90, 198, 351)
	assert_eq(
		layer_core.size, painting.texture.get_size(),
		"分层里那块画心的尺寸应与画心贴图一致（分层重切后要同步这个矩形）"
	)
	var expected := (mount.texture.get_size() * 0.5) - layer_core.get_center()
	assert_almost_eq(mount.position.x, expected.x, 0.01, "装裱的横向落点应让两层画心重合")
	assert_almost_eq(mount.position.y, expected.y, 0.01, "装裱的纵向落点应让两层画心重合")
	# 自证：按这个矩形去读贴图，那块必须基本上是实的 —— 否则说明层被重切、画心挪位了。
	var image: Image = mount.texture.get_image()
	if image == null:
		gut.p("跳过像素自证：headless 拿不到贴图 image")
		return
	var opaque := 0
	var total := 0
	for y in range(int(layer_core.position.y), int(layer_core.end.y)):
		for x in range(int(layer_core.position.x), int(layer_core.end.x)):
			total += 1
			if image.get_pixel(x, y).a > 0.03:
				opaque += 1
	assert_true(
		float(opaque) / float(maxi(total, 1)) >= 0.99,
		"分层里 (70,90)-(268,441) 这块应是实心画心（实测不透明占比 %.2f%%）—— 低于 99%% 说明层被重切过，装裱落点要重新量"
		% (100.0 * float(opaque) / float(maxi(total, 1)))
	)


## 飞行/盖满的度量必须落在**画心**上，不能落在带透明留白的装裱层上。
func test_flight_math_measures_the_opaque_core_not_the_mount() -> void:
	var painting := _make()
	if painting == null:
		return
	var mount: Sprite2D = painting.get_node_or_null("MountArt")
	if mount == null:
		return
	var core_cover: float = painting.cover_scale_for(painting.STAGE_SIZE)
	assert_almost_eq(
		core_cover,
		maxf(painting.STAGE_SIZE.x / painting.texture.get_size().x,
			painting.STAGE_SIZE.y / painting.texture.get_size().y) * painting.COVER_MARGIN,
		0.001,
		"盖满比例应按画心（不透明核心）算"
	)
	assert_true(
		core_cover * painting.texture.get_size().x >= painting.STAGE_SIZE.x
		and core_cover * painting.texture.get_size().y >= painting.STAGE_SIZE.y,
		"按画心算出来的比例必须真的盖满舞台"
	)


func test_glow_adds_light_instead_of_covering_the_painting() -> void:
	var painting := _make()
	if painting == null:
		return
	var wall_glow: Sprite2D = painting.get_node_or_null("WallGlow")
	if wall_glow == null:
		return
	var material := wall_glow.material as CanvasItemMaterial
	assert_not_null(material, "光晕应带 CanvasItemMaterial")
	if material == null:
		return
	assert_eq(
		material.blend_mode,
		CanvasItemMaterial.BLEND_MODE_ADD,
		"光晕必须是加法混合：换成普通混合会把画心糊住，读起来是'贴了张亮纸'而不是'画在发光'"
	)


func test_starts_dormant() -> void:
	var painting := _make()
	if painting == null:
		return
	assert_eq(painting.phase, painting.Phase.DORMANT, "开场应处于沉睡态")
	assert_false(painting.is_awake(), "开场不应是苏醒态")
	var awake_art: Sprite2D = painting.get_node_or_null("AwakeArt")
	var wall_glow: Sprite2D = painting.get_node_or_null("WallGlow")
	if awake_art:
		assert_almost_eq(awake_art.modulate.a, 0.0, 0.001, "沉睡时看不到苏醒态画心")
	if wall_glow:
		assert_almost_eq(wall_glow.modulate.a, 0.0, 0.001, "沉睡时没有光晕")


# ── 亮起来 ───────────────────────────────────────────────────────────

func test_awaken_lights_the_painting_in_place() -> void:
	var painting := _make()
	if painting == null:
		return
	watch_signals(painting)
	await painting.awaken(FAST)
	var awake_art: Sprite2D = painting.get_node_or_null("AwakeArt")
	var wall_glow: Sprite2D = painting.get_node_or_null("WallGlow")
	assert_almost_eq(awake_art.modulate.a, 1.0, 0.01, "亮起来后画心应完全换成苏醒态")
	assert_almost_eq(
		wall_glow.modulate.a, painting.GLOW_ALPHA_AWAKE, 0.02,
		"亮起来后应有暖光晕"
	)
	assert_eq(painting.phase, painting.Phase.AWAKE, "亮完应停在苏醒态")
	assert_false(painting.is_performing(), "亮完表演锁应释放（否则切视图按不动它）")
	assert_signal_emitted(painting, "awakened", "亮完应发 awakened 信号")
	# 亮起来时画还在墙上：位置与大小都不动。
	assert_eq(painting.position, HOME_POSITION, "亮起来是原地演出，画不应离开墙面")
	assert_almost_eq(painting.scale.x, 1.0, 0.001, "亮起来不应改变大小")
	assert_false(painting.covers_stage(), "亮起来时不该已经盖满舞台")


# ── 飞向玩家 ─────────────────────────────────────────────────────────

func test_flight_ends_covering_the_whole_stage() -> void:
	var painting := _make()
	if painting == null:
		return
	await painting.awaken(FAST)
	watch_signals(painting)
	await painting.fly_to_player(FAST)
	assert_eq(painting.phase, painting.Phase.FLYING, "飞完应停在飞行态（等书阁在它下面淡入）")
	assert_signal_emitted(painting, "flight_finished", "飞完应发 flight_finished 信号")
	assert_eq(
		painting.position, painting.STAGE_SIZE * 0.5,
		"飞向玩家 = 扑到舞台中心（世界坐标即屏幕坐标）"
	)
	assert_true(
		painting.covers_stage(),
		"飞完必须盖满舞台：实际画到 %s，舞台 %s（盖不满就会在书阁淡入时露出墙）" % [
			str(painting.drawn_size()), str(painting.STAGE_SIZE)]
	)
	assert_true(painting.is_performing(), "飞行结束后表演锁还没释放：画要留到淡出结束")


func test_flight_is_still_one_shot_after_it_landed() -> void:
	var painting := _make()
	if painting == null:
		return
	await painting.awaken(FAST)
	await painting.fly_to_player(FAST)
	var landed_scale: Vector2 = painting.scale
	await painting.fly_to_player(FAST)
	assert_eq(painting.scale, landed_scale, "已经飞到脸上的画不应再飞一次（重复调用应为空操作）")


# ── 切视图不能把正在飞的画按掉 ───────────────────────────────────────

func test_view_switch_mid_flight_does_not_cut_the_painting() -> void:
	var painting := _make()
	if painting == null:
		return
	await painting.awaken(FAST)
	# 原速飞（1.15s），这样"飞到一半"是确定可停的一帧；FAST 会一帧飞完，测不出中途。
	painting.fly_to_player()
	await wait_process_frames(2)
	assert_true(painting.is_performing(), "此刻应在飞行中")
	painting.stage_visible(false)
	assert_true(
		painting.visible,
		"飞行途中切视图不能把画按掉：请求只该被记下，等表演结束再兑现"
	)
	await wait_seconds(1.3)
	assert_true(painting.covers_stage(), "飞行应照常跑完")
	assert_true(painting.visible, "飞行刚跑完时画还在满屏状态")


func test_staged_visibility_is_honoured_once_the_performance_ends() -> void:
	var painting := _make()
	if painting == null:
		return
	await painting.awaken(FAST)
	painting.stage_visible(false)
	assert_false(painting.visible, "没有表演时，待机可见性立即生效")
	painting.stage_visible(true)
	assert_true(painting.visible, "回到主人房时画应重新上台")
	await painting.fly_to_player(FAST)
	painting.stage_visible(false)
	await painting.dissolve(FAST)
	assert_false(
		painting.visible,
		"淡出结束后兑现待机可见性：画让位给书阁（不然会一直罩在书阁上面）"
	)
	assert_almost_eq(painting.modulate.a, 0.0, 0.01, "淡出应把画淡到全透明")
	assert_false(painting.is_performing(), "淡出后表演锁应释放")


# ── 重演：把画请回墙上（组件能力，当前导览已不折回主人房）──────────────

func test_restaging_puts_the_painting_back_on_the_wall_and_keeps_it_awake() -> void:
	var painting := _make()
	if painting == null:
		return
	await painting.awaken(FAST)
	await painting.fly_to_player(FAST)
	painting.stage_visible(false)
	await painting.dissolve(FAST)

	painting.stage_visible(true)
	assert_true(painting.visible, "回到主人房时画应重新出现")
	assert_eq(painting.position, HOME_POSITION, "重演之前要回墙上原位（飞完那一版留在屏幕中心）")
	assert_almost_eq(painting.scale.x, 1.0, 0.001, "重演之前要复位大小（飞完那一版是满屏大小）")
	assert_false(painting.covers_stage(), "回到墙上时不该还是罩住全屏的大小")
	var awake_art: Sprite2D = painting.get_node_or_null("AwakeArt")
	if awake_art:
		assert_almost_eq(
			awake_art.modulate.a, 1.0, 0.01,
			"画卷醒了就不再睡回去：再进主人房应看到亮着的画"
		)


func test_reset_to_dormant_restores_the_opening_state() -> void:
	var painting := _make()
	if painting == null:
		return
	await painting.awaken(FAST)
	await painting.fly_to_player(FAST)
	painting.reset_to_dormant()
	assert_eq(painting.phase, painting.Phase.DORMANT, "复位后应回到沉睡态")
	assert_eq(painting.position, HOME_POSITION, "复位后应回到墙上原位")
	assert_almost_eq(painting.scale.x, 1.0, 0.001, "复位后应恢复原始大小")
	var awake_art: Sprite2D = painting.get_node_or_null("AwakeArt")
	if awake_art:
		assert_almost_eq(awake_art.modulate.a, 0.0, 0.001, "复位后苏醒态应重新藏起来")
	assert_false(painting.covers_stage(), "复位后不应盖住舞台")
